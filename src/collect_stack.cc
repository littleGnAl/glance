// Original BSD 3-Clause License
// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE-original file.

// Modifications and new contributions
// Copyright (c) 2024 Littlegnal. Licensed under the MIT License. See the LICENSE file for details.

#include <atomic>
#include <cstring>
#include <pthread.h>
#include <signal.h>
#include <ucontext.h>
#include <unistd.h>
#include <sys/errno.h>
#include <cxxabi.h>  // NOLINT
#include <dlfcn.h>   // NOLINT
#include <chrono>
// #include "dart_sdk/include/dart_tools_api.h"

#if defined(_M_X64) || defined(__x86_64__)
#define HOST_ARCH_X64 1
#elif defined(_M_IX86) || defined(__i386__)
#define HOST_ARCH_IA32 1
#elif defined(_M_ARM) || defined(__ARMEL__)
#define HOST_ARCH_ARM 1
#elif defined(_M_ARM64) || defined(__aarch64__)
#define HOST_ARCH_ARM64 1
#elif defined(__riscv)
#if __SIZEOF_POINTER__ == 4
#define HOST_ARCH_RISCV32 1
#define ARCH_IS_32_BIT 1
#elif __SIZEOF_POINTER__ == 8
#define HOST_ARCH_RISCV64 1
#define ARCH_IS_64_BIT 1
#else
#error Unknown XLEN
#endif
#else
#error Architecture was not detected
#endif

typedef uintptr_t uword;

namespace {

pthread_t target_thread;

struct Buffer {
  size_t size;
  int64_t* pcs;
};

std::atomic<Buffer*> buffer_to_fill;

uword GetProgramCounter(const mcontext_t &mcontext) {
#if defined(HOST_ARCH_IA32)
  return static_cast<uword>(mcontext.gregs[REG_EIP]);
#elif defined(HOST_ARCH_X64)
  return static_cast<uword>(mcontext.gregs[REG_RIP]);
#elif defined(HOST_ARCH_ARM)
  return static_cast<uword>(mcontext.arm_pc);
#elif defined(HOST_ARCH_ARM64)
  return static_cast<uword>(mcontext.pc);
#elif defined(HOST_ARCH_RISCV32)
  return static_cast<uword>(mcontext.__gregs[REG_PC]);
#elif defined(HOST_ARCH_RISCV64)
  return static_cast<uword>(mcontext.__gregs[REG_PC]);
#else
#error Unsupported architecture.
#endif // HOST_ARCH_...
}

uword GetFramePointer(const mcontext_t &mcontext) {
#if defined(HOST_ARCH_IA32)
  return static_cast<uword>(mcontext.gregs[REG_EBP]);
#elif defined(HOST_ARCH_X64)
  return static_cast<uword>(mcontext.gregs[REG_RBP]);
#elif defined(HOST_ARCH_ARM)
  // B1.3.3 Program Status Registers (PSRs)
  if ((mcontext.arm_cpsr & (1 << 5)) != 0) {
    // Thumb mode.
    return static_cast<uword>(mcontext.arm_r7);
  } else {
    // ARM mode.
    return static_cast<uword>(mcontext.arm_fp);
  }
#elif defined(HOST_ARCH_ARM64)
  return static_cast<uword>(mcontext.regs[29]);
#elif defined(HOST_ARCH_RISCV32)
  return static_cast<uword>(mcontext.__gregs[REG_S0]);
#elif defined(HOST_ARCH_RISCV64)
  return static_cast<uword>(mcontext.__gregs[REG_S0]);
#else
#error Unsupported architecture.
#endif // HOST_ARCH_...
}

uword GetCStackPointer(const mcontext_t &mcontext) {
#if defined(HOST_ARCH_IA32)
  return static_cast<uword>(mcontext.gregs[REG_ESP]);
#elif defined(HOST_ARCH_X64)
  return static_cast<uword>(mcontext.gregs[REG_RSP]);
#elif defined(HOST_ARCH_ARM)
  return static_cast<uword>(mcontext.arm_sp);
#elif defined(HOST_ARCH_ARM64)
  return static_cast<uword>(mcontext.sp);
#elif defined(HOST_ARCH_RISCV32)
  return static_cast<uword>(mcontext.__gregs[REG_SP]);
#elif defined(HOST_ARCH_RISCV64)
  return static_cast<uword>(mcontext.__gregs[REG_SP]);
#else
#error Unsupported architecture.
#endif // HOST_ARCH_...
}

uword GetDartStackPointer(const mcontext_t &mcontext) {
#if defined(HOST_ARCH_ARM64)
  return static_cast<uword>(mcontext.regs[15]);
#else
  return GetCStackPointer(mcontext);
#endif
}

bool IsBetween(uword v, uword low, uword high) { return low <= v && v <= high; }

bool ValidateFP(uword fp, uword sp, uword dart_sp) {
  if (fp == 0 || sp == 0) {
    return false;
  }

  // FP should be at least pointer size aligned.
  if ((fp & (sizeof(void *) - 1)) != 0) {
    return false;
  }

  return IsBetween(fp, sp, sp + 4096) || IsBetween(fp, dart_sp, dart_sp + 4096);
}

constexpr intptr_t kObscureSignal = SIGPWR;

void DumpHandler(int signal, siginfo_t *info, void *context) {
  if (signal != kObscureSignal) {
    return;
  }

  Buffer *buffer = buffer_to_fill.load();

  ucontext_t *ucontext = reinterpret_cast<ucontext_t *>(context);
  mcontext_t mcontext = ucontext->uc_mcontext;
  uword pc = GetProgramCounter(mcontext);
  uword fp = GetFramePointer(mcontext);
  // TODO(littlegnal): In my device the fp becomes null in some frames, need investigate why?
  // it most likely in debug mode.
  if (!fp) {
    return;
  }
  uword sp = GetCStackPointer(mcontext);
  uword dart_sp = GetDartStackPointer(mcontext);

  // Try unwinding starting at the current frame using FP links assuming that
  // stack slot at FP contains caller's FP and stack slot above that one
  // contains caller PC.
  //
  // This will not work for native code that does not preserve frame pointers
  // but will work for Dart AOT compiled code.
  intptr_t frame = 0;
  while (ValidateFP(fp, sp, dart_sp) && frame < (buffer->size - 1)) {
    buffer->pcs[frame++] = pc;

    uword caller_sp = fp + 2 * sizeof(void *);
    uword caller_fp = reinterpret_cast<uword *>(fp)[0];
    uword caller_pc = reinterpret_cast<uword *>(fp)[1];
    if (caller_fp == fp || caller_pc == 0) {
      break;
    }

    sp = dart_sp = caller_sp;
    fp = caller_fp;
    pc = caller_pc;
  }

  if (frame == 0) {
    buffer->pcs[frame++] = pc;
  }
  buffer->pcs[frame++] = 0;

  buffer_to_fill.store(nullptr);  // Signal completion
}

// std::mutex stack_traces_mutex;

} // namespace

// Set the current thread as a target for subsequent CollectStackTrace
// calls. Can only register one thread at a time.
extern "C" void SetCurrentThreadAsTarget() { target_thread = pthread_self(); }


// Collect stack trace of the target thread previously set by
// SetCurrentThreadAsTarget into the given |buf| buffer.
//
// Stack trace is collected as a sequence of PC (program counter values) for
// each frame and is terminated with 0 value.
//
// On success returns nullptr otherwise returns a string containing the error.
//
// Returned string must be freed by the caller.
extern "C" char* CollectStackTraceOfTargetThread(int64_t* buf, size_t buf_size) {
  // TODO: this function is not thread safe and should probably use locking.

  // Register a signal handler for the |kObscureSignal| signal which will dump
  // the stack for us.
  struct sigaction new_act, old_act;
  new_act.sa_sigaction = &DumpHandler;
  new_act.sa_flags = SA_RESTART | SA_SIGINFO;
  int result = sigaction(kObscureSignal, &new_act, &old_act);
  if (result != 0) {
    // Failed to register the signal handler. Report an error.
    char buf[512];
    strerror_r(errno, buf, sizeof(buf));
    return strdup(buf);
  }

  Buffer buffer { buf_size, buf };
  buffer_to_fill = &buffer;

  result = pthread_kill(target_thread, kObscureSignal);
  if (result != 0) {
    // Failed to send the signal.
    char buf[512];
    strerror_r(errno, buf, sizeof(buf));

    // Restore old action.
    sigaction(kObscureSignal, &old_act, nullptr);
    return strdup(buf);
  }

  // Wait for signal handler to trigger, but not too long.
  //
  // Note: can't use wait/notify here because it is not signal safe.
  int i = 0;
  while (buffer_to_fill.load() != nullptr && i++ < 50) {
    usleep(1000);
  }

  // Restore old action.
  sigaction(kObscureSignal, &old_act, nullptr);

  if (buffer_to_fill.load() != nullptr) {
    buffer_to_fill.store(nullptr);
    return strdup("signal handler did not trigger within 50ms");
  }

  return nullptr; // Success.
}

extern "C" char * LookupSymbolName(Dl_info *info) {
    if (info->dli_sname == nullptr) {
    return nullptr;
  }
  // if (start != nullptr) {
  //   *start = reinterpret_cast<uword>(info.dli_saddr);
  // }
  int status = 0;
  size_t len = 0;
  char* demangled = abi::__cxa_demangle(info->dli_sname, nullptr, &len, &status);
  if (status == 0) {
    return demangled;
  }
  
  return const_cast<char *>(info->dli_sname);
}

extern "C" int64_t TimestampNowInMicrosSinceEpoch() {
  const auto elapsed = std::chrono::system_clock::now().time_since_epoch();
  return std::chrono::duration_cast<std::chrono::nanoseconds>(elapsed).count() / 1000;
}

// static constexpr int64_t kNanosPerSecond = 1000000000;

// int64_t ConvertToNanos(int64_t ticks, int64_t frequency) {
//   int64_t nano_seconds = (ticks / frequency) * kNanosPerSecond;
//   int64_t leftover_ticks = ticks % frequency;
//   int64_t leftover_nanos = (leftover_ticks * kNanosPerSecond) / frequency;
//   return nano_seconds + leftover_nanos;
// }

// extern "C" int64_t TimestampNowInMicrosSinceEpoch() {
//   const int64_t ticks = Dart_TimelineGetTicks();
//   const int64_t frequency = Dart_TimelineGetTicksFrequency();
//   // optimization for the most common case.
//   if (frequency != kNanosPerSecond) {
//     return ConvertToNanos(ticks, frequency) / 1000;
//   } else {
//     return ticks / 1000;
//   }
// }


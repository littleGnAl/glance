// Original BSD 3-Clause License
// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE-original file.

// Modifications and new contributions
// Copyright (c) 2024 Littlegnal. Licensed under the MIT License. See the LICENSE file for details.

#include <atomic>
// #include <cstring>
// #include <pthread.h>
#include <signal.h>
#if defined(DART_HOST_OS_ANDROID)
#include <ucontext.h>
#elif defined(DART_HOST_OS_IOS)
#include <sys/ucontext.h>
#endif

// #include <unistd.h>
#include <sys/errno.h>
// #include <cxxabi.h> // NOLINT
// #include <dlfcn.h>  // NOLINT
#include <chrono>
#include "collect_stack.h"

// Borrowed from https://github.com/dart-lang/sdk/blob/main/runtime/platform/globals.h#L107
//
// Target OS detection.
// for more information on predefined macros:
//   - http://msdn.microsoft.com/en-us/library/b0084kay.aspx
//   - with gcc, run: "echo | gcc -E -dM -"
// #if defined(__ANDROID__)

// // Check for Android first, to determine its difference from Linux.
// #define DART_HOST_OS_ANDROID 1

// #elif defined(__linux__) || defined(__FreeBSD__)

// // Generic Linux.
// #define DART_HOST_OS_LINUX 1

// #elif defined(__APPLE__)

// // Define the flavor of Mac OS we are running on.
// #include <TargetConditionals.h>
// #define DART_HOST_OS_MACOS 1
// #if TARGET_OS_IPHONE
// #define DART_HOST_OS_IOS 1
// #endif
// #endif

// #if defined(_M_X64) || defined(__x86_64__)
// #define HOST_ARCH_X64 1
// #elif defined(_M_IX86) || defined(__i386__)
// #define HOST_ARCH_IA32 1
// #elif defined(_M_ARM) || defined(__ARMEL__)
// #define HOST_ARCH_ARM 1
// #elif defined(_M_ARM64) || defined(__aarch64__)
// #define HOST_ARCH_ARM64 1
// #elif defined(__riscv)
// #if __SIZEOF_POINTER__ == 4
// #define HOST_ARCH_RISCV32 1
// #define ARCH_IS_32_BIT 1
// #elif __SIZEOF_POINTER__ == 8
// #define HOST_ARCH_RISCV64 1
// #define ARCH_IS_64_BIT 1
// #else
// #error Unknown XLEN
// #endif
// #else
// #error Architecture was not detected
// #endif

// typedef uintptr_t uword;

namespace
{

  // pthread_t target_thread;

  // struct Buffer
  // {
  //   size_t size;
  //   int64_t *pcs;
  // };

  std::atomic<Buffer *> buffer_to_fill;

#if defined(DART_HOST_OS_ANDROID)
  uword GetProgramCounter(const mcontext_t &mcontext)
  {
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
#elif defined(DART_HOST_OS_IOS)
  // Borrowed from https://github.com/dart-lang/sdk/blob/a9b706e19f2d5af60f6b90b2f75165ca55fe6874/runtime/vm/signal_handler_macos.cc#L13
  uword GetProgramCounter(const mcontext_t &mcontext)
  {
    uword pc = 0;

#if defined(HOST_ARCH_IA32)
    pc = static_cast<uword>(mcontext->__ss.__eip);
#elif defined(HOST_ARCH_X64)
    pc = static_cast<uword>(mcontext->__ss.__rip);
#elif defined(HOST_ARCH_ARM)
    pc = static_cast<uword>(mcontext->__ss.__pc);
#elif defined(HOST_ARCH_ARM64)
    pc = static_cast<uword>(mcontext->__ss.__pc);
#else
#error Unsupported architecture.
#endif // HOST_ARCH_...

    return pc;
  }
#endif

#if defined(DART_HOST_OS_ANDROID)
  uword GetFramePointer(const mcontext_t &mcontext)
  {
#if defined(HOST_ARCH_IA32)
    return static_cast<uword>(mcontext.gregs[REG_EBP]);
#elif defined(HOST_ARCH_X64)
    return static_cast<uword>(mcontext.gregs[REG_RBP]);
#elif defined(HOST_ARCH_ARM)
    // B1.3.3 Program Status Registers (PSRs)
    if ((mcontext.arm_cpsr & (1 << 5)) != 0)
    {
      // Thumb mode.
      return static_cast<uword>(mcontext.arm_r7);
    }
    else
    {
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
#elif defined(DART_HOST_OS_IOS)
  // Borrowed https://github.com/dart-lang/sdk/blob/a9b706e19f2d5af60f6b90b2f75165ca55fe6874/runtime/vm/signal_handler_macos.cc#L31
  uword GetFramePointer(const mcontext_t &mcontext)
  {
    uword fp = 0;

#if defined(HOST_ARCH_IA32)
    fp = static_cast<uword>(mcontext->__ss.__ebp);
#elif defined(HOST_ARCH_X64)
    fp = static_cast<uword>(mcontext->__ss.__rbp);
#elif defined(HOST_ARCH_ARM)
    fp = static_cast<uword>(mcontext->__ss.__r[7]);
#elif defined(HOST_ARCH_ARM64)
    fp = static_cast<uword>(mcontext->__ss.__fp);
#else
#error Unsupported architecture.
#endif // HOST_ARCH_...

    return fp;
  }
#endif

#if defined(DART_HOST_OS_ANDROID)
  uword GetCStackPointer(const mcontext_t &mcontext)
  {
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
#elif defined(DART_HOST_OS_IOS)
  // Borrowed from https://github.com/dart-lang/sdk/blob/a9b706e19f2d5af60f6b90b2f75165ca55fe6874/runtime/vm/signal_handler_macos.cc#L49
  uword GetCStackPointer(const mcontext_t &mcontext)
  {
    uword sp = 0;

#if defined(HOST_ARCH_IA32)
    sp = static_cast<uword>(mcontext->__ss.__esp);
#elif defined(HOST_ARCH_X64)
    sp = static_cast<uword>(mcontext->__ss.__rsp);
#elif defined(HOST_ARCH_ARM)
    sp = static_cast<uword>(mcontext->__ss.__sp);
#elif defined(HOST_ARCH_ARM64)
    sp = static_cast<uword>(mcontext->__ss.__sp);
#else
    UNIMPLEMENTED();
#endif // HOST_ARCH_...

    return sp;
  }
#endif

#if defined(DART_HOST_OS_ANDROID)
  uword GetDartStackPointer(const mcontext_t &mcontext)
  {
#if defined(HOST_ARCH_ARM64)
    return static_cast<uword>(mcontext.regs[15]);
#else
    return GetCStackPointer(mcontext);
#endif
  }
#elif defined(DART_HOST_OS_IOS)
  // Borrow from https://github.com/dart-lang/sdk/blob/a9b706e19f2d5af60f6b90b2f75165ca55fe6874/runtime/vm/signal_handler_macos.cc#L67
  uword GetDartStackPointer(const mcontext_t &mcontext)
  {
#if defined(TARGET_ARCH_ARM64)
    // SPREG = R15 = 15, see
    // https://github.com/dart-lang/sdk/blob/525a63786cd3227c000ec6f23a0004637a08b3fa/runtime/vm/constants_arm64.h#L50
    return static_cast<uword>(mcontext->__ss.__x[15 /*SPREG*/]);
#else
    return GetCStackPointer(mcontext);
#endif
  }
#endif

  // bool IsBetween(uword v, uword low, uword high) { return low <= v && v <= high; }

  // bool ValidateFP(uword fp, uword sp, uword dart_sp)
  // {
  //   if (fp == 0 || sp == 0)
  //   {
  //     return false;
  //   }

  //   // FP should be at least pointer size aligned.
  //   if ((fp & (sizeof(void *) - 1)) != 0)
  //   {
  //     return false;
  //   }

  //   return IsBetween(fp, sp, sp + 4096) || IsBetween(fp, dart_sp, dart_sp + 4096);
  // }

#if defined(DART_HOST_OS_ANDROID)
constexpr intptr_t kObscureSignal = SIGPWR;
#elif defined(DART_HOST_OS_IOS)
constexpr intptr_t kObscureSignal = SIGPROF;
#endif
  

  void DumpHandler(int signal, siginfo_t *info, void *context)
  {
    if (signal != kObscureSignal)
    {
      return;
    }

    Buffer *buffer = buffer_to_fill.load();

    ucontext_t *ucontext = reinterpret_cast<ucontext_t *>(context);
    mcontext_t mcontext = ucontext->uc_mcontext;
    uword pc = GetProgramCounter(mcontext);
    uword fp = GetFramePointer(mcontext);
    uword sp = GetCStackPointer(mcontext);
    uword dart_sp = GetDartStackPointer(mcontext);

    FillBuffer(buffer, pc, fp, sp, dart_sp);

    // // Try unwinding starting at the current frame using FP links assuming that
    // // stack slot at FP contains caller's FP and stack slot above that one
    // // contains caller PC.
    // //
    // // This will not work for native code that does not preserve frame pointers
    // // but will work for Dart AOT compiled code.
    // intptr_t frame = 0;
    // while (ValidateFP(fp, sp, dart_sp) && frame < (buffer->size - 1))
    // {
    //   buffer->pcs[frame++] = pc;

    //   uword caller_sp = fp + 2 * sizeof(void *);
    //   uword caller_fp = reinterpret_cast<uword *>(fp)[0];
    //   uword caller_pc = reinterpret_cast<uword *>(fp)[1];
    //   if (caller_fp == fp || caller_pc == 0)
    //   {
    //     break;
    //   }

    //   sp = dart_sp = caller_sp;
    //   fp = caller_fp;
    //   pc = caller_pc;
    // }

    // if (frame == 0)
    // {
    //   buffer->pcs[frame++] = pc;
    // }
    // buffer->pcs[frame++] = 0;

    buffer_to_fill.store(nullptr); // Signal completion
  }

  // std::mutex stack_traces_mutex;

} // namespace

// Set the current thread as a target for subsequent CollectStackTrace
// calls. Can only register one thread at a time.
// extern "C" void SetCurrentThreadAsTarget() { target_thread = pthread_self(); }

// Collect stack trace of the target thread previously set by
// SetCurrentThreadAsTarget into the given |buf| buffer.
//
// Stack trace is collected as a sequence of PC (program counter values) for
// each frame and is terminated with 0 value.
//
// On success returns nullptr otherwise returns a string containing the error.
//
// Returned string must be freed by the caller.
extern "C" char *CollectStackTraceOfTargetThread(int64_t *buf, size_t buf_size)
{
  // TODO: this function is not thread safe and should probably use locking.

  // Register a signal handler for the |kObscureSignal| signal which will dump
  // the stack for us.
  struct sigaction new_act, old_act;
  new_act.sa_sigaction = &DumpHandler;
  new_act.sa_flags = SA_RESTART | SA_SIGINFO;
  int result = sigaction(kObscureSignal, &new_act, &old_act);
  if (result != 0)
  {
    // Failed to register the signal handler. Report an error.
    char buf[512];
    strerror_r(errno, buf, sizeof(buf));
    return strdup(buf);
  }

  Buffer buffer{buf_size, buf};
  buffer_to_fill = &buffer;

  result = pthread_kill(target_thread, kObscureSignal);
  if (result != 0)
  {
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
  while (buffer_to_fill.load() != nullptr && i++ < 50)
  {
    usleep(1000);
  }

  // Restore old action.
  sigaction(kObscureSignal, &old_act, nullptr);

  if (buffer_to_fill.load() != nullptr)
  {
    buffer_to_fill.store(nullptr);
    return strdup("signal handler did not trigger within 50ms");
  }

  return nullptr; // Success.
}

// extern "C" char *LookupSymbolName(Dl_info *info)
// {
//   if (info->dli_sname == nullptr)
//   {
//     return nullptr;
//   }

//   int status = 0;
//   size_t len = 0;
//   char *demangled = abi::__cxa_demangle(info->dli_sname, nullptr, &len, &status);
//   if (status == 0)
//   {
//     return strdup(demangled);
//   }

//   return strdup(info->dli_sname);
// }

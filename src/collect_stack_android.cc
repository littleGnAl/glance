// Original BSD 3-Clause License
// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE-original file.

// Modifications and new contributions
// Copyright (c) 2024 Littlegnal. Licensed under the MIT License. See the LICENSE file for details.

#include <atomic>
#include <signal.h>
#include <ucontext.h>
#include <sys/errno.h>
#include <chrono>
#include <unistd.h>
#include "collect_stack.h"

namespace glance
{

  std::atomic<Buffer *> buffer_to_fill;

  bool StackWalker::GetCurrentStackBoundsIfNeeded(pthread_t target_thread)
  {
    if (stack_lower_ != 0 && stack_upper_ != 0)
    {
      return true;
    }

    pthread_attr_t attr;
    if (pthread_getattr_np(target_thread, &attr) != 0)
    {
      return false;
    }

    void *base;
    size_t size;
    int error = pthread_attr_getstack(&attr, &base, &size);
    pthread_attr_destroy(&attr);
    if (error != 0)
    {
      return false;
    }

    stack_lower_ = reinterpret_cast<uword>(base);
    stack_upper_ = stack_lower_ + size;
    return true;
  }

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

  uword GetDartStackPointer(const mcontext_t &mcontext)
  {
#if defined(HOST_ARCH_ARM64)
    return static_cast<uword>(mcontext.regs[15]);
#else
    return GetCStackPointer(mcontext);
#endif
  }

  constexpr intptr_t kObscureSignal = SIGPROF;

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

    glance::StackWalker stack_walker(glance::g_target_thread_, buffer, pc, fp, sp, dart_sp);
    stack_walker.Walk();

    buffer_to_fill.store(nullptr); // Signal completion
  }

} // namespace glance

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

  //   struct sigaction act = {};
  // act.sa_sigaction = action;
  // sigemptyset(&act.sa_mask);
  // sigaddset(&act.sa_mask, SIGPROF);  // Prevent nested signals.
  // act.sa_flags = SA_RESTART | SA_SIGINFO | SA_ONSTACK;
  // int r = sigaction(SIGPROF, &act, nullptr);

  // Register a signal handler for the |kObscureSignal| signal which will dump
  // the stack for us.
  struct sigaction new_act, old_act;
  new_act.sa_sigaction = &glance::DumpHandler;
  sigemptyset(&new_act.sa_mask);
  sigaddset(&new_act.sa_mask, SIGPROF);  // Prevent nested signals.
  // new_act.sa_flags = SA_RESTART | SA_SIGINFO;
  new_act.sa_flags = SA_RESTART | SA_SIGINFO | SA_ONSTACK;
  int result = sigaction(kObscureSignal, &new_act, &old_act);
  if (result != 0)
  {
    // Failed to register the signal handler. Report an error.
    char buf[512];
    strerror_r(errno, buf, sizeof(buf));
    return strdup(buf);
  }

  Buffer buffer{buf_size, buf};
  glance::buffer_to_fill = &buffer;

  result = pthread_kill(glance::g_target_thread_, glance::kObscureSignal);
  if (result != 0)
  {
    // Failed to send the signal.
    char buf[512];
    strerror_r(errno, buf, sizeof(buf));

    // Restore old action.
    sigaction(glance::kObscureSignal, &old_act, nullptr);
    return strdup(buf);
  }

  // Wait for signal handler to trigger, but not too long.
  //
  // Note: can't use wait/notify here because it is not signal safe.
  int i = 0;
  while (glance::buffer_to_fill.load() != nullptr && i++ < 50)
  {
    usleep(1000);
  }

  // Restore old action.
  sigaction(glance::kObscureSignal, &old_act, nullptr);

  if (glance::buffer_to_fill.load() != nullptr)
  {
    glance::buffer_to_fill.store(nullptr);
    return strdup("signal handler did not trigger within 50ms");
  }

  return nullptr; // Success.
}

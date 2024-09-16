#include "stack_collector.h"

#include <errno.h>       // NOLINT
#include <sys/syscall.h> // NOLINT
#include <signal.h>
#include <ucontext.h>
#include <sys/errno.h>
#include <chrono>

namespace glance
{
    constexpr intptr_t kObscureSignal = SIGPROF;

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

    // void StackHandler::InterruptThread(pthread_t thread)
    void StackCapturer::InterruptThread(pthread_t thread)
    {
        // int result = syscall(__NR_tgkill, getpid(), thread->id(), SIGPROF);

        int result = pthread_kill(thread, SIGPROF);
    }

    void StackCapturer::InstallHandler()
    {
        struct sigaction act = {};
        act.sa_sigaction = &StackCapturer::StackHandlerMain;
        sigemptyset(&act.sa_mask);
        sigaddset(&act.sa_mask, SIGPROF); // Prevent nested signals.
        act.sa_flags = SA_RESTART | SA_SIGINFO | SA_ONSTACK;
        int r = sigaction(SIGPROF, &act, nullptr);
    }

    void StackCapturer::StackHandlerMain(int signal, siginfo_t *info, void *context)
    {
        // LOGCATE("StackCapturer::StackHandlerMain");
        if (signal != kObscureSignal)
        {
            return;
        }

        // Buffer *buffer = buffer_to_fill.load();

        ucontext_t *ucontext = reinterpret_cast<ucontext_t *>(context);
        mcontext_t mcontext = ucontext->uc_mcontext;
        uword pc = GetProgramCounter(mcontext);
        uword fp = GetFramePointer(mcontext);
        uword sp = GetCStackPointer(mcontext);
        uword dart_sp = GetDartStackPointer(mcontext);

        Stack *stack = new Stack();

        // Try unwinding starting at the current frame using FP links assuming that
        // stack slot at FP contains caller's FP and stack slot above that one
        // contains caller PC.
        //
        // This will not work for native code that does not preserve frame pointers
        // but will work for Dart AOT compiled code.
        intptr_t frame = 0;
        // while (ValidateFP(fp, sp, dart_sp) && frame < (buffer->size - 1))
        while (ValidateFP(fp, sp, dart_sp) && frame < 640)
        {
            // stack->pcs[frame++] = pc;
            stack->pcs.push_back(pc);
            frame++;

            uword caller_sp = fp + 2 * sizeof(void *);
        //     uword * tmp_fp = reinterpret_cast<uword *>(fp);
        //     if (!tmp_fp) {
        //         break;
        //     }
        //     if (!tmp_fp[0]) {
        //         break;
        //     }
            uword caller_fp = reinterpret_cast<uword *>(fp)[0];
            uword caller_pc = reinterpret_cast<uword *>(fp)[1];
            if (caller_fp == fp || caller_pc == 0)
            {
                break;
            }

            sp = dart_sp = caller_sp;
            fp = caller_fp;
            pc = caller_pc;
        }

        if (stack->pcs.empty())
        {
            // buffer->pcs[frame++] = pc;
            stack->pcs.push_back(pc);
        }
        // buffer->pcs[frame++] = 0;
        // stack->pcs.push_back(0);

        buffer_.put(stack);
        // LOGCATE("buffer_.put(stack);");




        
    }
}

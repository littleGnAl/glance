#include <assert.h>             // NOLINT
#include <errno.h>              // NOLINT
#include <mach/kern_return.h>   // NOLINT
#include <mach/mach.h>          // NOLINT
#include <mach/thread_act.h>    // NOLINT
#include <mach/thread_status.h> // NOLINT
#include <stdbool.h>            // NOLINT
#include <sys/sysctl.h>         // NOLINT
#include <sys/types.h>          // NOLINT
#include <unistd.h>             // NOLINT

#include "collect_stack.h"

// Borrowed from https://github.com/dart-lang/sdk/blob/master/runtime/vm/thread_interrupter_macos.cc

#if defined(HOST_ARCH_X64)
#define THREAD_STATE_FLAVOR x86_THREAD_STATE64
#define THREAD_STATE_FLAVOR_SIZE x86_THREAD_STATE64_COUNT
typedef x86_thread_state64_t __thread_state_flavor_t;
#elif defined(HOST_ARCH_ARM64)
#define THREAD_STATE_FLAVOR ARM_THREAD_STATE64
#define THREAD_STATE_FLAVOR_SIZE ARM_THREAD_STATE64_COUNT
typedef arm_thread_state64_t __thread_state_flavor_t;
#elif defined(HOST_ARCH_ARM)
#define THREAD_STATE_FLAVOR ARM_THREAD_STATE32
#define THREAD_STATE_FLAVOR_SIZE ARM_THREAD_STATE32_COUNT
typedef arm_thread_state32_t __thread_state_flavor_t;
#else
#error "Unsupported architecture."
#endif // HOST_ARCH_...

namespace glance
{
    struct InterruptedThreadState
    {
        uintptr_t pc;
        uintptr_t csp;
        uintptr_t dsp;
        uintptr_t fp;
        uintptr_t lr;
    };

    class ThreadInterrupterMacOS
    {
    public:
        explicit ThreadInterrupterMacOS(pthread_t os_thread) : os_thread_(os_thread)
        {
            mach_thread_ = pthread_mach_thread_np(os_thread);
            res = thread_suspend(mach_thread_);
        }

        void CollectSample(int64_t *buf, size_t buf_size)
        {
            if (res != KERN_SUCCESS)
            {
                return;
            }
            auto count = static_cast<mach_msg_type_number_t>(THREAD_STATE_FLAVOR_SIZE);
            __thread_state_flavor_t state;
            kern_return_t res =
                thread_get_state(mach_thread_, THREAD_STATE_FLAVOR,
                                 reinterpret_cast<thread_state_t>(&state), &count);
            if (os_thread_ == nullptr)
            {
                return;
            }
            InterruptedThreadState its = ProcessState(state);

            Buffer buffer{buf_size, buf};
            FillBuffer(&buffer, its.pc, its.fp, its.csp, its.dsp);
        }

        ~ThreadInterrupterMacOS()
        {
            if (res != KERN_SUCCESS)
            {
                return;
            }
            res = thread_resume(mach_thread_);
        }

    private:
        static InterruptedThreadState ProcessState(__thread_state_flavor_t state)
        {
            InterruptedThreadState its;
#if defined(HOST_ARCH_X64)
            its.pc = state.__rip;
            its.fp = state.__rbp;
            its.csp = state.__rsp;
            its.dsp = state.__rsp;
            its.lr = 0;
#elif defined(HOST_ARCH_ARM64)
            its.pc = state.__pc;
            its.fp = state.__fp;
            its.csp = state.__sp;
            its.dsp = state.__sp;
            its.lr = state.__lr;
#elif defined(HOST_ARCH_ARM)
            its.pc = state.__pc;
            its.fp = state.__r[7];
            its.csp = state.__sp;
            its.dsp = state.__sp;
            its.lr = state.__lr;
#endif // HOST_ARCH_...

#if defined(HOST_ARCH_ARM64)
            // SPREG = R15 = 15, see
            // https://github.com/dart-lang/sdk/blob/525a63786cd3227c000ec6f23a0004637a08b3fa/runtime/vm/constants_arm64.h#L50
            its.dsp = state.__x[15];
#endif
            return its;
        }

        kern_return_t res;
        pthread_t os_thread_;
        mach_port_t mach_thread_;
    };
} // namespace glance

extern "C" char *CollectStackTraceOfTargetThread(int64_t *buf, size_t buf_size)
{
    glance::ThreadInterrupterMacOS interrupter(target_thread);
    interrupter.CollectSample(buf, buf_size);

    return nullptr;
}
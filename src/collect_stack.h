// #include <atomic>
#include <cstring>
#include <pthread.h>
// #include <signal.h>
// #include <ucontext.h>
#include <unistd.h>
// #include <sys/errno.h>
#include <cxxabi.h> // NOLINT
#include <dlfcn.h>  // NOLINT
// #include <chrono>

// Borrowed from https://github.com/dart-lang/sdk/blob/main/runtime/platform/globals.h#L107
//
// Target OS detection.
// for more information on predefined macros:
//   - http://msdn.microsoft.com/en-us/library/b0084kay.aspx
//   - with gcc, run: "echo | gcc -E -dM -"
#if defined(__ANDROID__)

// Check for Android first, to determine its difference from Linux.
#define DART_HOST_OS_ANDROID 1

#elif defined(__linux__) || defined(__FreeBSD__)

// Generic Linux.
#define DART_HOST_OS_LINUX 1

#elif defined(__APPLE__)

// Define the flavor of Mac OS we are running on.
#include <TargetConditionals.h>
#define DART_HOST_OS_MACOS 1
#if TARGET_OS_IPHONE
#define DART_HOST_OS_IOS 1
#endif
#endif

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

namespace
{

    pthread_t target_thread;

    struct Buffer
    {
        size_t size;
        int64_t *pcs;
    };

    bool IsBetween(const uword &v, const uword &low, const uword &high) { return low <= v && v <= high; }

    bool ValidateFP(const uword &fp, const uword &sp, const uword &dart_sp)
    {
        if (fp == 0 || sp == 0)
        {
            return false;
        }

        // FP should be at least pointer size aligned.
        if ((fp & (sizeof(void *) - 1)) != 0)
        {
            return false;
        }

        return IsBetween(fp, sp, sp + 4096) || IsBetween(fp, dart_sp, dart_sp + 4096);
    }

    void FillBuffer(Buffer *buffer, uword pc, uword fp, uword sp, uword dart_sp)
    {
        // Try unwinding starting at the current frame using FP links assuming that
        // stack slot at FP contains caller's FP and stack slot above that one
        // contains caller PC.
        //
        // This will not work for native code that does not preserve frame pointers
        // but will work for Dart AOT compiled code.
        intptr_t frame = 0;
        while (ValidateFP(fp, sp, dart_sp) && frame < (buffer->size - 1))
        {
            buffer->pcs[frame++] = pc;

            uword caller_sp = fp + 2 * sizeof(void *);
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

        if (frame == 0)
        {
            buffer->pcs[frame++] = pc;
        }
        buffer->pcs[frame++] = 0;
    }
}

extern "C" void SetCurrentThreadAsTarget() { target_thread = pthread_self(); }

extern "C" char *CollectStackTraceOfTargetThread(int64_t *buf, size_t buf_size);

extern "C" char *LookupSymbolName(Dl_info *info)
{
    if (info->dli_sname == nullptr)
    {
        return nullptr;
    }

    int status = 0;
    size_t len = 0;
    char *demangled = abi::__cxa_demangle(info->dli_sname, nullptr, &len, &status);
    if (status == 0)
    {
        return strdup(demangled);
    }

    return strdup(info->dli_sname);
}
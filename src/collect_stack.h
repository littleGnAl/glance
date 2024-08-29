// Original BSD 3-Clause License
// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE-original file.

// Modifications and new contributions
// Copyright (c) 2024 Littlegnal. Licensed under the MIT License. See the LICENSE file for details.

#ifndef COLLECT_STACK_H_
#define COLLECT_STACK_H_

#include <pthread.h>
#include <dlfcn.h> // NOLINT

// Borrowed from https://github.com/dart-lang/sdk/blob/main/runtime/platform/globals.h#L107

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

struct Buffer
{
    size_t size;
    int64_t *pcs;
};

namespace glance
{

    extern pthread_t g_target_thread_;

    /// Borrowed from https://github.com/dart-lang/sdk/blob/3cc6105316be32e2d48b1b9b253247ad4fc89698/runtime/vm/profiler.cc#L217
    class StackWalker
    {
    public:
        StackWalker(
            pthread_t target_thread,
            Buffer *buffer,
            uword pc,
            uword fp,
            uword sp,
            uword dart_sp);

        ~StackWalker() = default;

        bool GetCurrentStackBoundsIfNeeded(pthread_t target_thread);

        void Walk();

    private:
        uword *CallerPC(uword *fp);

        uword *CallerFP(uword *fp);

        bool ValidFramePointer(uword *fp, uword &lower_bound, uword &stack_upper);

        bool ValidateThreadStackBounds(uword fp,
                                       uword sp,
                                       uword stack_lower,
                                       uword stack_upper);

        bool GetAndValidateThreadStackBounds(
            uintptr_t fp,
            uintptr_t sp,
            uword *stack_lower,
            uword *stack_upper);

        static uword stack_lower_;

        static uword stack_upper_;

        pthread_t target_thread_;

        Buffer *buffer_;

        // const uword stack_upper_;
        const uword original_pc_;
        const uword original_fp_;
        const uword original_sp_;
        const uword original_dart_sp_;
        uword lower_bound_;
    };

}

extern "C" void SetCurrentThreadAsTarget();

extern "C" char *CollectStackTraceOfTargetThread(int64_t *buf, size_t buf_size);

extern "C" char *LookupSymbolName(Dl_info *info);

#endif // COLLECT_STACK_H_
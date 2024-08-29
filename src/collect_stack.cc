// Original BSD 3-Clause License
// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE-original file.

// Modifications and new contributions
// Copyright (c) 2024 Littlegnal. Licensed under the MIT License. See the LICENSE file for details.

#include "collect_stack.h"

#include <cstring>
#include <pthread.h>
#include <unistd.h>
#include <cxxabi.h> // NOLINT
#include <dlfcn.h>  // NOLINT

// The layout of C stack frames.
#if defined(HOST_ARCH_IA32) || defined(HOST_ARCH_X64) || \
    defined(HOST_ARCH_ARM) || defined(HOST_ARCH_ARM64)
// +-------------+
// | saved IP/LR |
// +-------------+
// | saved FP    |  <- FP
// +-------------+
intptr_t kHostSavedCallerPcSlotFromFp = 1;
intptr_t kHostSavedCallerFpSlotFromFp = 0;
#elif defined(HOST_ARCH_RISCV32) || defined(HOST_ARCH_RISCV64)
// +-------------+
// |             | <- FP
// +-------------+
// | saved RA    |
// +-------------+
// | saved FP    |
// +-------------+
intptr_t kHostSavedCallerPcSlotFromFp = -1;
intptr_t kHostSavedCallerFpSlotFromFp = -2;
#else
#error What architecture?
#endif

#define MSAN_UNPOISON(ptr, len) \
    do                          \
    {                           \
    } while (false && (ptr) == nullptr && (len) == 0)

#define ASAN_UNPOISON(ptr, len) \
    do                          \
    {                           \
    } while (false && (ptr) == nullptr && (len) == 0)

namespace glance
{
    pthread_t g_target_thread_ = 0;

    uword StackWalker::stack_lower_ = 0;

    uword StackWalker::stack_upper_ = 0;

    StackWalker::StackWalker(
        pthread_t target_thread,
        Buffer *buffer,
        uword pc,
        uword fp,
        uword sp,
        uword dart_sp)
        : target_thread_(target_thread),
          buffer_(buffer),
          original_pc_(pc),
          original_fp_(fp),
          original_sp_(sp),
          original_dart_sp_(dart_sp)
    {
    }

    void StackWalker::Walk()
    {
        intptr_t frame = 0;
        uword lower_bound = 0;
        uword stack_upper = 0;
        if (!GetAndValidateThreadStackBounds(original_fp_, original_sp_, &lower_bound, &stack_upper))
        {
            buffer_->pcs[frame++] = 0;
            return;
        }

        buffer_->pcs[frame++] = original_pc_;

        uword *pc = reinterpret_cast<uword *>(original_pc_);
        uword *fp = reinterpret_cast<uword *>(original_fp_);
        uword *previous_fp = fp;

        if (!ValidFramePointer(fp, lower_bound, stack_upper))
        {
            buffer_->pcs[frame++] = 0;
            return;
        }

        size_t maxFrameSize = buffer_->size - 1;

        while (frame < maxFrameSize)
        {
            pc = CallerPC(fp);
            previous_fp = fp;
            fp = CallerFP(fp);

            if (fp == nullptr)
            {
                break;
            }

            if (fp <= previous_fp)
            {
                break;
            }

            if (!ValidFramePointer(fp, lower_bound, stack_upper))
            {
                break;
            }

            const uword pc_value = reinterpret_cast<uword>(pc);
            if ((pc_value + 1) < pc_value)
            {
                // It is not uncommon to encounter an invalid pc as we
                // traverse a stack frame.  Most of these we can tolerate.  If
                // the pc is so large that adding one to it will cause an
                // overflow it is invalid and it will cause headaches later
                // while we are building the profile.  Discard it.
                break;
            }

            // Move the lower bound up.
            lower_bound = reinterpret_cast<uword>(fp);

            buffer_->pcs[frame++] = pc_value;
        }

        buffer_->pcs[frame++] = 0;
    }

    uword *StackWalker::CallerPC(uword *fp)
    {
        uword *caller_pc_ptr = fp + kHostSavedCallerPcSlotFromFp;
        // This may actually be uninitialized, by design (see class comment above).
        // `1 << 3` is the `kWordSize` from https://github.com/dart-lang/sdk/blob/3cc6105316be32e2d48b1b9b253247ad4fc89698/runtime/vm/profiler.cc#L295
        MSAN_UNPOISON(caller_pc_ptr, 1 << 3);
        ASAN_UNPOISON(caller_pc_ptr, 1 << 3);
        return reinterpret_cast<uword *>(*caller_pc_ptr);
    }

    uword *StackWalker::CallerFP(uword *fp)
    {
        uword *caller_fp_ptr = fp + kHostSavedCallerFpSlotFromFp;
        // This may actually be uninitialized, by design (see class comment above).
        // `1 << 3` is the `kWordSize` from https://github.com/dart-lang/sdk/blob/3cc6105316be32e2d48b1b9b253247ad4fc89698/runtime/vm/profiler.cc#L304
        MSAN_UNPOISON(caller_fp_ptr, 1 << 3);
        ASAN_UNPOISON(caller_fp_ptr, 1 << 3);
        return reinterpret_cast<uword *>(*caller_fp_ptr);
    }

    bool StackWalker::ValidFramePointer(uword *fp, uword &lower_bound, uword &stack_upper)
    {
        if (fp == nullptr)
        {
            return false;
        }
        uword cursor = reinterpret_cast<uword>(fp);
        cursor += sizeof(fp);
        bool r = (cursor >= lower_bound) && (cursor < stack_upper);

        return r;
    }

    bool StackWalker::ValidateThreadStackBounds(uword fp,
                                                uword sp,
                                                uword stack_lower,
                                                uword stack_upper)
    {
        if (stack_lower >= stack_upper)
        {
            // Stack boundary is invalid.
            return false;
        }

        if ((sp < stack_lower) || (sp >= stack_upper))
        {
            // Stack pointer is outside thread's stack boundary.
            return false;
        }

        if ((fp < stack_lower) || (fp >= stack_upper))
        {
            // Frame pointer is outside threads's stack boundary.
            return false;
        }

        return true;
    }

    bool StackWalker::GetAndValidateThreadStackBounds(
        uintptr_t fp,
        uintptr_t sp,
        uword *stack_lower,
        uword *stack_upper)
    {
        if (!GetCurrentStackBoundsIfNeeded(target_thread_))
        {
            return false;
        }

        *stack_lower = stack_lower_;
        *stack_upper = stack_upper_;

        if ((*stack_lower == 0) || (*stack_upper == 0))
        {
            return false;
        }

        if (sp > *stack_lower)
        {
            // The stack pointer gives us a tighter lower bound.
            *stack_lower = sp;
        }

        return ValidateThreadStackBounds(fp, sp, *stack_lower, *stack_upper);
    }
} // namespace glance

extern "C" void SetCurrentThreadAsTarget()
{
    glance::g_target_thread_ = pthread_self();
}

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
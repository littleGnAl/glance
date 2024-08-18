#ifndef STACK_CAPTURER_C_H_
#define STACK_CAPTURER_C_H_

#include <android/log.h>

#define LOG_TAG "glance"
#define LOGCATE(...) \
    __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

#define LOGCATD(...) \
    __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)

typedef void *StackCapturerHandle;

typedef struct NativeStack
{
    int64_t *pcs;

    int size;
} NativeStack;

typedef struct CapturedSamples
{
    NativeStack *stacks;

    int size;
} CapturedSamples;

extern "C" StackCapturerHandle CreateStackCapturer();

extern "C" void ReleaseStackCapturer(StackCapturerHandle handle);

extern "C" void SetCurrentThreadAsTarget();

extern "C" void StartStackCapture(StackCapturerHandle handle);

extern "C" void StopStackCapture(StackCapturerHandle handle);

extern "C" void GetCapturedSamples(StackCapturerHandle handle, CapturedSamples *out_samples);

extern "C" void DisableThreadInterrupts(StackCapturerHandle handle);

extern "C" void EnableThreadInterrupts(StackCapturerHandle handle);

extern "C" char *LookupSymbolName(Dl_info *info);

#endif // STACK_CAPTURER_C_H_

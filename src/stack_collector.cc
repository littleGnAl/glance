#include "stack_collector.h"

#include <condition_variable>
#include <functional>
#include <mutex>
#include <queue>
#include <thread>
#include <vector>
#include <chrono>

namespace glance
{
    bool IsBetween(const uword &v, const uword &low, const uword &high) { return low <= v && v <= high; }

    bool ValidateFP(const uword &fp, const uword &sp, const uword &dart_sp)
    {
        if (!fp || fp == 0 || sp == 0)
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

    // StackHandler::StackHandler() : buffer_(kDefaultBufferCount);

    // RingBuffer StackHandler::buffer_(kDefaultBufferCount);

    // std::atomic<uintptr_t> StackHandler::thread_interrupt_disabled_{1};
    //

    pthread_t StackCapturer::capture_thread_ = 0;

    pthread_t StackCapturer::target_thread_ = 0;

    bool StackCapturer::shutdown_ = false;

    std::condition_variable StackCapturer::cv_;
    std::mutex StackCapturer::monitor_;

    RingBuffer StackCapturer::buffer_(kDefaultBufferCount);

    std::atomic<uintptr_t> StackCapturer::thread_interrupt_disabled_{1};

    StackCapturer::StackCapturer()
    {
        // InstallHandler();
    }

    StackCapturer::~StackCapturer()
    {
    }

    // bool StackCapturer::shutdown_ = false;

    void *StackCapturer::ThreadMain(void *param)
    {
        LOGCATE("StackCapturer::ThreadMain");
        // std::mutex mtx;
        // std::condition_variable cv;

        const auto interval = std::chrono::microseconds(1000);

        // intptr_t interrupt_period = 1000;
        while (!shutdown_)
        {
            // LOGCATE("StackCapturer::ThreadMain222");
            // std::unique_lock<std::mutex> lock(monitor_);
            // cv_.wait_for(lock, interval);
            // LOGCATE("StackCapturer::ThreadMain111");

            usleep(16000);

            if (ThreadInterruptsEnabled())
            {
                // LOGCATE("ThreadInterruptsEnabled %ld", target_thread_);
                InterruptThread(target_thread_);
                // stack_handler_->InterruptThread(capture_thread_);
            }
        }
    }

    void StackCapturer::Start()
    {
        LOGCATE("StackCapturer::Start");

        InstallHandler();
        EnableThreadInterrupts();

        pthread_attr_t attr;
        int result = pthread_attr_init(&attr);

        // const int kStackSize = (128 * (1 << 3) * (1 << 10));
        // result = pthread_attr_setstacksize(&attr, kStackSize);

        if (pthread_create(&capture_thread_, &attr, ThreadMain, nullptr))
        {
            pthread_detach(capture_thread_);
        }

        // void *fps_writing_thread(void *param)
        // else {
        // }

        result = pthread_attr_destroy(&attr);
    }

    void StackCapturer::Stop()
    {
    }

    void StackCapturer::GetCapturedSamples(CapturedSamples *out_samples)
    {
        LOGCATE("GetCapturedSamples");

        // RingBuffer buffer = StackHandler::GetBuffer();
        std::vector<Stack *> stacks = buffer_.get_all();
        LOGCATE("stacks.size(): %d", stacks.size());

        int size = stacks.size();
        LOGCATE("size: %d", size);
        for (int i = 0; i < size; ++i) {
            // LOGCATE("UUUUUU: %d", i);
        }

        std::vector<NativeStack> native_stacks;
        // for (Stack *s : stacks)
        for (int i = 0; i < stacks.size(); ++i)
        {
            // LOGCATE("iiiii: %d", i);

            Stack *s = stacks[i];
            if (s != nullptr)
            {
                NativeStack ns; //{s->pcs, s->pcs.size()};
                ns.pcs = s->pcs.data();
                ns.size = s->pcs.size();

                // LOGCATE("s->pcs.size(): %d", s->pcs.size());

                native_stacks.push_back(ns);
            }

            // LOGCATE("native_stacks.size()222: %d", native_stacks.size());
        }

        LOGCATE("native_stacks.size()111: %d", native_stacks.size());

        out_samples->stacks = native_stacks.data();
        out_samples->size = native_stacks.size();

        LOGCATE("out_samples->size: %d", out_samples->size);
        LOGCATE("native_stacks.size(): %d", native_stacks.size());
    }
} // namespace glance

extern "C" StackCapturerHandle CreateStackCapturer()
{
    return new glance::StackCapturer();
}

extern "C" void ReleaseStackCapturer(StackCapturerHandle handle)
{
    delete reinterpret_cast<glance::StackCapturer *>(handle);
}

extern "C" void SetCurrentThreadAsTarget() { glance::StackCapturer::SetCurrentThreadAsTarget(); }

extern "C" void StartStackCapture(StackCapturerHandle handle)
{
    reinterpret_cast<glance::StackCapturer *>(handle)->Start();
}

extern "C" void StopStackCapture(StackCapturerHandle handle)
{
    reinterpret_cast<glance::StackCapturer *>(handle)->Stop();
}

extern "C" void GetCapturedSamples(StackCapturerHandle handle, CapturedSamples *out_samples)
{
    reinterpret_cast<glance::StackCapturer *>(handle)->GetCapturedSamples(out_samples);
}

extern "C" void DisableThreadInterrupts(StackCapturerHandle handle)
{
    reinterpret_cast<glance::StackCapturer *>(handle)->DisableThreadInterrupts();
}

extern "C" void EnableThreadInterrupts(StackCapturerHandle handle)
{
    reinterpret_cast<glance::StackCapturer *>(handle)->EnableThreadInterrupts();
}

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

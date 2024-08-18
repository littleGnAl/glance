#ifndef STACK_CAPTURER_H_
#define STACK_CAPTURER_H_

#include <thread>
#include <vector>
#include <cstring>
#include <pthread.h>
#include <unistd.h>
#include <cxxabi.h> // NOLINT
#include <dlfcn.h>  // NOLINT
#include "stack_collector_c.h"

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

namespace glance
{
    typedef uintptr_t uword;

    // static const _bufferCount = 641;

    const int kDefaultBufferCount = 641;

    bool IsBetween(const uword &v, const uword &low, const uword &high);

    bool ValidateFP(const uword &fp, const uword &sp, const uword &dart_sp);

    struct Stack
    {
        std::vector<int64_t> pcs;
    };

    class RingBuffer
    {
    public:
        explicit RingBuffer(size_t size) : buffer_(size, nullptr), head_(0), tail_(0), full_(false) {}

        // 添加数据到缓冲区
        void put(Stack *item)
        {
            if (item == nullptr)
            {
                // throw std::invalid_argument("Null pointer passed to put method");
                return;
            }
            if (buffer_[head_] != nullptr)
            {
                delete buffer_[head_]; // 删除旧数据，防止内存泄漏
            }
            buffer_[head_] = item;
            // LOGCATE(" head_: %d", head_);
            if (full_)
            {
                tail_ = (tail_ + 1) % buffer_.size(); // 覆盖旧数据
            }
            head_ = (head_ + 1) % buffer_.size();
            full_ = head_ == tail_;
        }

        // 从缓冲区读取数据
        Stack *get()
        {
            if (empty())
            {
                // throw std::runtime_error("Buffer is empty");
                return nullptr;
            }

            Stack *item = buffer_[tail_];
            buffer_[tail_] = nullptr; // 防止悬空指针
            full_ = false;
            tail_ = (tail_ + 1) % buffer_.size();

            return item;
        }

        // 获取缓冲区中所有的值
        std::vector<Stack *> get_all() const
        {
            std::vector<Stack *> values;
            if (empty())
            {
                return values;
            }

            size_t current = tail_;
            do
            {
                // LOGCATE("current: %d", current);
                values.push_back(buffer_[current]);
                current = (current + 1) % buffer_.size();
            } while (current != head_ || (full_ && values.size() < buffer_.size()));

            // LOGCATE("values.size(): %d", values.size());

            return values;
        }

        // 检查缓冲区是否为空
        bool empty() const
        {
            return (!full_ && (head_ == tail_));
        }

        // 检查缓冲区是否已满
        bool full() const
        {
            return full_;
        }

        // 获取缓冲区的大小
        size_t size() const
        {
            size_t size = buffer_.size();

            if (!full_)
            {
                if (head_ >= tail_)
                {
                    size = head_ - tail_;
                }
                else
                {
                    size = buffer_.size() + head_ - tail_;
                }
            }

            return size;
        }

        // 获取缓冲区的容量
        size_t capacity() const
        {
            return buffer_.size();
        }

        // 析构函数
        ~RingBuffer()
        {
            for (auto item : buffer_)
            {
                delete item; // 释放所有动态分配的内存
            }
        }

    private:
        std::vector<Stack *> buffer_;
        size_t head_;
        size_t tail_;
        bool full_;
    };

    // class StackHandler
    // {
    // public:
    //     // explicit StackHandler();

    //     // ~StackHandler() = default;

    //     static void InterruptThread(pthread_t thread);

    //     static void InstallHandler();

    //     static void HandlerMain(int signal, siginfo_t *info, void *context);

    //     static void DisableThreadInterrupts()
    //     {
    //         thread_interrupt_disabled_.fetch_add(1u);
    //     }

    //     static void EnableThreadInterrupts()
    //     {
    //         thread_interrupt_disabled_.fetch_sub(1u);
    //     }

    //     static bool ThreadInterruptsEnabled()
    //     {
    //         return thread_interrupt_disabled_ == 0;
    //     }

    //     static RingBuffer &GetBuffer()
    //     {
    //         return buffer_;
    //     }

    // private:
    //     static RingBuffer buffer_;

    //     static std::atomic<uintptr_t> thread_interrupt_disabled_;
    // };

    class StackCapturer
    {
    public:
        StackCapturer();
        ~StackCapturer();

        static void SetCurrentThreadAsTarget()
        {
            LOGCATE("SetCurrentThreadAsTarget");
            target_thread_ = pthread_self();
            LOGCATE("SetCurrentThreadAsTarget %ld", target_thread_);
        }

        static void *ThreadMain(void *param);

        void Start();

        void Stop();

        void GetCapturedSamples(CapturedSamples *out_samples);

        static void InterruptThread(pthread_t thread);

        void InstallHandler();

        static void StackHandlerMain(int signal, siginfo_t *info, void *context);

        static bool ThreadInterruptsEnabled()
        {
            return thread_interrupt_disabled_ == 0;
        }

        void DisableThreadInterrupts()
        {
            LOGCATE("DisableThreadInterrupts");
            thread_interrupt_disabled_.fetch_add(1u);
        }

        void EnableThreadInterrupts()
        {
            LOGCATE("EnableThreadInterrupts");
            thread_interrupt_disabled_.fetch_sub(1u);
        }

    private:
        static pthread_t capture_thread_;

        static pthread_t target_thread_;

        static bool shutdown_;

        // std::mutex mtx;
        static std::condition_variable cv_;

        //   static Monitor* monitor_;

        static std::mutex monitor_;
        //   static intptr_t interrupt_period_;

        // std::unique_ptr<StackHandler> stack_handler_;
        //

        static RingBuffer buffer_;

        static std::atomic<uintptr_t> thread_interrupt_disabled_;
    };

    // class StackCapturerThread
    // {
    // public:
    //     static void *ThreadMain(void *param);

    //     static void Start();

    //     static void Stop();

    //     void GetCapturedSamples(CapturedSamples &out_samples);

    //     void DisableThreadInterrupts()
    //     {
    //         StackHandler::DisableThreadInterrupts();
    //     }

    //     void EnableThreadInterrupts()
    //     {

    //         StackHandler::EnableThreadInterrupts();
    //     }

    // private:
    //     static std::unique_ptr<StackCapturer> stackCapturer_;
    // };
} // namespace glance

#endif // STACK_CAPTURER_H_

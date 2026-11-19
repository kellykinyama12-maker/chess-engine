#pragma once

#include <thread>
#include <queue>
#include <mutex>
#include <condition_variable>
#include <functional>
#include <vector>
#include <memory>
#include <atomic>
#include <cstdint>

// Simple thread-safe task queue based thread pool
class ThreadPool {
public:
    using Task = std::function<void()>;

    // Constructor: creates num_threads worker threads
    explicit ThreadPool(size_t num_threads = 0);

    // Destructor: waits for all tasks to complete and stops workers
    ~ThreadPool();

    // Submit a task to the pool
    void enqueue(Task task);

    // Wait for all queued tasks to complete
    void wait_all();

    // Get number of worker threads
    size_t num_workers() const { return workers_.size(); }

    // Get number of pending tasks
    size_t pending_tasks() const;

    // Shutdown and wait for completion
    void shutdown();

    // Check if thread pool is running
    bool is_running() const { return running_; }

private:
    // Worker thread main loop
    void worker_loop();

    // Thread-safe task queue
    std::queue<Task> task_queue_;
    mutable std::mutex queue_mutex_;
    std::condition_variable task_cv_;
    std::condition_variable completion_cv_;

    // Worker threads
    std::vector<std::thread> workers_;

    // Control flags
    std::atomic<bool> running_{false};
    std::atomic<uint32_t> active_tasks_{0};
};

#include "thread_pool.hpp"
#include <iostream>

ThreadPool::ThreadPool(size_t num_threads) {
    if (num_threads == 0) {
        num_threads = std::thread::hardware_concurrency();
        if (num_threads == 0) num_threads = 2;
    }

    running_ = true;
    workers_.reserve(num_threads);

    for (size_t i = 0; i < num_threads; i++) {
        workers_.emplace_back([this] { worker_loop(); });
    }
}

ThreadPool::~ThreadPool() {
    shutdown();
}

void ThreadPool::worker_loop() {
    while (running_) {
        Task task;

        {
            std::unique_lock<std::mutex> lock(queue_mutex_);
            
            // Wait for a task or shutdown signal
            task_cv_.wait(lock, [this] {
                return !task_queue_.empty() || !running_;
            });

            if (!running_ && task_queue_.empty()) {
                break;
            }

            if (task_queue_.empty()) {
                continue;
            }

            task = std::move(task_queue_.front());
            task_queue_.pop();
            active_tasks_++;
        }

        // Execute task outside lock
        try {
            task();
        } catch (const std::exception& e) {
            std::cerr << "Task execution error: " << e.what() << "\n";
        } catch (...) {
            std::cerr << "Unknown task execution error\n";
        }

        {
            std::unique_lock<std::mutex> lock(queue_mutex_);
            active_tasks_--;
            
            if (active_tasks_ == 0 && task_queue_.empty()) {
                completion_cv_.notify_all();
            }
        }
    }
}

void ThreadPool::enqueue(Task task) {
    {
        std::unique_lock<std::mutex> lock(queue_mutex_);
        if (!running_) {
            throw std::runtime_error("ThreadPool is not running");
        }
        task_queue_.push(std::move(task));
    }
    task_cv_.notify_one();
}

void ThreadPool::wait_all() {
    std::unique_lock<std::mutex> lock(queue_mutex_);
    completion_cv_.wait(lock, [this] {
        return task_queue_.empty() && active_tasks_ == 0;
    });
}

size_t ThreadPool::pending_tasks() const {
    std::unique_lock<std::mutex> lock(queue_mutex_);
    return task_queue_.size() + active_tasks_;
}

void ThreadPool::shutdown() {
    {
        std::unique_lock<std::mutex> lock(queue_mutex_);
        running_ = false;
    }
    task_cv_.notify_all();

    for (auto& worker : workers_) {
        if (worker.joinable()) {
            worker.join();
        }
    }

    workers_.clear();
}

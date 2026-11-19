#pragma once

#include "types.hpp"
#include <vector>
#include <unordered_map>
#include <cstdint>
#include <memory>
#include <cmath>

// MCTS Algorithm Constants
constexpr double DEFAULT_EXPLORATION = 0.7;
constexpr double DEFAULT_BACKUP_MINIMAX = 1.0;
constexpr double DEFAULT_PRIOR_LEARNING_RATE = 0.5;
constexpr int DEFAULT_MAX_PLY = 128;

// UCB Formula Constants
constexpr double UCB_UNEXPANDED_NODE = 1.0;
constexpr double UCB_LOSSES_AVOIDANCE = 0.1;
constexpr double UCB_LOG_TERM_FACTOR = 0.75;

// Reward Conversion Constants (logistic scaling)
constexpr double LOGISTIC_K = -0.00490739829861;
constexpr double REWARD_SCALING = 203.77396313709564;

// Forward declarations
class Position;

// Edge: Represents a move and its associated statistics
struct Edge {
    Move move;
    double prior = 0.0;           // Prior probability from expansion
    double action_value = 0.0;    // Sum of rewards
    double mean_action_value = 0.0; // Average reward (action_value / visits)
    uint32_t visits = 0;          // Visit count

    Edge() = default;
    Edge(Move m, double p = 0.0) : move(m), prior(p) {}
};

// Node: Represents a position in the search tree
struct Node {
    uint64_t key = 0;              // Zobrist hash of position
    uint32_t node_visits = 0;      // Total visits to this node
    std::vector<Edge> children;    // Child edges

    Node() = default;
    explicit Node(uint64_t zobrist) : key(zobrist) {}
};

// MultiHashMap: Hash table for quick node lookups during search
class MultiHashMap {
public:
    static constexpr size_t DEFAULT_BUCKET_SIZE = 32;

    explicit MultiHashMap(size_t bucket_size = DEFAULT_BUCKET_SIZE)
        : bucket_size_(bucket_size), buckets_(bucket_size) {}

    // Find node by zobrist key
    Node* find(uint64_t key) const {
        if (bucket_size_ == 0) return nullptr;
        size_t bucket_idx = key % bucket_size_;
        const auto& bucket = buckets_[bucket_idx];
        for (const auto& node : bucket) {
            if (node && node->key == key) {
                return node.get();
            }
        }
        return nullptr;
    }

    // Insert or update node (non-const version)
    Node* insert_or_find(uint64_t key) {
        if (bucket_size_ == 0) return nullptr;
        size_t bucket_idx = key % bucket_size_;
        auto& bucket = buckets_[bucket_idx];

        // Check if already exists
        for (auto& node : bucket) {
            if (node && node->key == key) {
                return node.get();
            }
        }

        // Add new node
        bucket.emplace_back(std::make_unique<Node>(key));
        return bucket.back().get();
    }

    // Get all nodes (for debugging/statistics)
    size_t size() const {
        size_t count = 0;
        for (const auto& bucket : buckets_) {
            for (const auto& node : bucket) {
                if (node) count++;
            }
        }
        return count;
    }

    // Clear all nodes
    void clear() {
        for (auto& bucket : buckets_) {
            bucket.clear();
        }
    }

private:
    size_t bucket_size_;
    std::vector<std::vector<std::unique_ptr<Node>>> buckets_;
};

// Reward conversion utilities
inline double value_to_reward(int centipawns) {
    // Logistic function: 1 / (1 + exp(k * cp))
    // Maps centipawn values to [0, 1] probability space
    // +600cp → ~0.95, -600cp → ~0.05
    return 1.0 / (1.0 + std::exp(LOGISTIC_K * centipawns));
}

inline int reward_to_value(double reward) {
    // Inverse logistic: log(r / (1-r)) / k
    // Maps reward back to centipawn value
    if (reward > 0.99) return 10000;
    if (reward < 0.01) return -10000;
    return static_cast<int>(REWARD_SCALING * std::log(reward / (1.0 - reward)));
}

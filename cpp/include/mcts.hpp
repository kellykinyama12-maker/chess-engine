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

// Phase 6C: Alpha-Beta node types for typed search
enum class NodeType {
    pv = 0,   // Exact (searched inside the window)
    all = 1,  // Upper bound (failed low)
    cut = 2   // Lower bound (failed high)
};

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

// Phase 6C: TypedEdge extends Edge with node type tracking
struct TypedEdge : public Edge {
    NodeType type = NodeType::pv;  // Alpha-beta node type

    TypedEdge() = default;
    TypedEdge(Move m, double p = 0.0, NodeType t = NodeType::pv)
        : Edge(m, p), type(t) {}
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

// Phase 6D: Transposition Table (TT) for caching evaluated positions
// Stores exact values and bounds to avoid re-searching the same positions

// TranspositionEntry: Single cache entry storing position evaluation
struct TranspositionEntry {
    uint64_t key = 0;              // Zobrist hash for position verification
    int depth = 0;                 // Search depth remaining when stored
    double value = 0.0;            // Cached node value (reward: 0.0-1.0)
    NodeType type = NodeType::pv;  // Entry type: pv (exact), all (upper bound), cut (lower bound)
    uint32_t timestamp = 0;        // Age for replacement strategy

    TranspositionEntry() = default;
    TranspositionEntry(uint64_t k, int d, double v, NodeType t, uint32_t ts)
        : key(k), depth(d), value(v), type(t), timestamp(ts) {}
};

// TranspositionTable: Hash table for caching position evaluations
class TranspositionTable {
public:
    static constexpr size_t DEFAULT_SIZE = 16777216;  // 16M entries (~384 MB with entries)
    static constexpr size_t BUCKET_SIZE = 4;          // 4-way associative

    explicit TranspositionTable(size_t size = DEFAULT_SIZE);
    ~TranspositionTable() = default;

    // Probe: Check if position is cached and applicable for current search
    TranspositionEntry* probe(uint64_t key, int depth);

    // Store: Cache a position evaluation
    void store(uint64_t key, int depth, double value, NodeType type);

    // Check if cached entry can be used for alpha-beta cutoff
    bool can_use_entry(const TranspositionEntry* entry, int depth, 
                       double alpha, double beta) const;

    // Statistics
    uint64_t get_hits() const { return hits_; }
    uint64_t get_probes() const { return probes_; }
    uint64_t get_stores() const { return stores_; }
    double get_hit_rate() const {
        return probes_ > 0 ? (100.0 * hits_ / probes_) : 0.0;
    }

    void print_stats() const;
    void clear();
    size_t size() const { return table_.size(); }

private:
    struct Bucket {
        TranspositionEntry entries[BUCKET_SIZE];
        uint8_t count = 0;  // Number of valid entries in bucket
    };

    std::vector<Bucket> table_;
    uint32_t generation_ = 0;  // Current generation/timestamp
    uint64_t hits_ = 0;        // Cache hits count
    uint64_t probes_ = 0;      // Total probes count
    uint64_t stores_ = 0;      // Total stores count

    // Find entry in bucket, returns index or -1 if not found
    int find_entry_in_bucket(const Bucket& bucket, uint64_t key) const;

    // Find replacement slot in bucket (-1 if bucket full, use oldest)
    int find_replacement_slot(Bucket& bucket) const;
};

// Transposition table utility: Bounds checking for cutoff decision
inline bool TranspositionTable::can_use_entry(const TranspositionEntry* entry, 
                                               int depth, 
                                               double alpha, double beta) const {
    if (!entry || entry->depth < depth) return false;

    switch (entry->type) {
        case NodeType::pv:
            return true;  // Exact value, always usable
        case NodeType::all:
            return entry->value <= alpha;  // Upper bound, fail-low cutoff
        case NodeType::cut:
            return entry->value >= beta;   // Lower bound, fail-high cutoff
        default:
            return false;
    }
}

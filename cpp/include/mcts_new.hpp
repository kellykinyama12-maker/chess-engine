#pragma once

#include "mcts.hpp"
#include "position.hpp"
#include "thread_pool.hpp"
#include <vector>
#include <memory>
#include <cstdint>
#include <chrono>
#include <mutex>

// Forward declarations
class MonteCarlo;
class ThreadPool;

// Search statistics
struct SearchStats {
    uint32_t total_simulations = 0;
    uint32_t tree_nodes = 0;
    double avg_branching_factor = 0.0;
    double max_depth = 0;
    std::chrono::milliseconds elapsed_time{0};
};

// Search result for a position
struct SearchResult {
    Move best_move;
    double best_value = 0.0;
    uint32_t visits = 0;
    std::vector<Move> principal_variation;  // Best line found
};

// Main MCTS Algorithm Implementation
class MonteCarlo {
public:
    // Constructor
    explicit MonteCarlo(size_t max_simulations = 10000,
                       double exploration = DEFAULT_EXPLORATION,
                       double backup_minimax = DEFAULT_BACKUP_MINIMAX,
                       double prior_learning_rate = DEFAULT_PRIOR_LEARNING_RATE);

    // Core search methods
    SearchResult search(Position& root_position, int time_limit_ms = 5000);
    SearchResult search_parallel(Position& root_position, int num_threads, int time_limit_ms = 5000);
    
    // Tree policy (selection & expansion)
    void tree_policy();
    
    // Playout policy (simulation)
    double playout_policy();
    
    // Backup (backpropagation)
    void backup(double reward);
    
    // Create root node
    Node* create_root(const Position& root_position);
    
    // Helper methods
    Edge* best_child(const Node& node, EdgeStatistic stat);
    double ucb(const Node& node, const Edge& edge) const;
    
    // Threading configuration
    void set_num_threads(size_t n) { num_threads_ = n; }
    size_t get_num_threads() const { return num_threads_; }
    
    // Accessors
    Node* current_node() const;
    uint32_t get_ply() const { return ply_; }
    uint32_t get_simulations() const { return num_simulations_; }
    const SearchStats& get_stats() const { return stats_; }
    
    // Configuration
    void set_exploration(double c) { exploration_ = c; }
    void set_backup_minimax(double w) { backup_minimax_ = w; }
    void set_prior_learning_rate(double lr) { prior_learning_rate_ = lr; }
    void set_max_simulations(size_t n) { max_simulations_ = n; }

private:
    // Search state
    Position search_position_;     // Current search position
    std::vector<Edge*> edges_;     // Path through tree
    std::vector<Node*> nodes_;     // Node path for backup
    uint32_t ply_ = 0;            // Current ply in search
    uint32_t num_simulations_ = 0; // Number of simulations completed
    
    // Tree storage
    MultiHashMap tree_;            // Zobrist-indexed node table
    
    // Configuration parameters
    size_t max_simulations_ = 10000;
    double exploration_ = DEFAULT_EXPLORATION;
    double backup_minimax_ = DEFAULT_BACKUP_MINIMAX;
    double prior_learning_rate_ = DEFAULT_PRIOR_LEARNING_RATE;
    int max_ply_ = DEFAULT_MAX_PLY;
    
    // Threading
    std::unique_ptr<ThreadPool> thread_pool_;
    size_t num_threads_ = 1;
    std::mutex tree_mutex_;  // Protects tree access
    
    // Statistics
    SearchStats stats_;
    std::chrono::steady_clock::time_point search_start_;
    
    // Helper methods for internal use
    bool is_terminal() const;
    bool is_drawn(const Position& pos) const;
    void reset_search();
    void advance_move(Edge* edge);
    void retreat_move();
    
    // Threaded simulation worker
    void run_simulation(const Position& root_position, Node* root, 
                       std::chrono::steady_clock::time_point search_start,
                       int time_limit_ms);
};

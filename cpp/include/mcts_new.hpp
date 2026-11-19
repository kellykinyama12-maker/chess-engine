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

// Phase 6A: Enhanced Move Ordering
// Killer moves heuristic for move ordering
struct KillerMoves {
    static constexpr int MAX_PLY = 128;
    static constexpr int MAX_KILLERS = 2;
    Move moves[MAX_PLY][MAX_KILLERS];
    
    KillerMoves() {
        for (int ply = 0; ply < MAX_PLY; ply++) {
            for (int i = 0; i < MAX_KILLERS; i++) {
                moves[ply][i] = Move();
            }
        }
    }
    
    void clear() {
        for (int ply = 0; ply < MAX_PLY; ply++) {
            for (int i = 0; i < MAX_KILLERS; i++) {
                moves[ply][i] = Move();
            }
        }
    }
    
    void record(Move move, int ply) {
        if (ply >= MAX_PLY) return;
        if (move == moves[ply][0]) return;  // Already the best killer
        moves[ply][1] = moves[ply][0];
        moves[ply][0] = move;
    }
};

// History heuristic: tracks success of moves in causing cutoffs
struct HistoryTable {
    static constexpr int HISTORY_SIZE = 2 * 128 * 128;  // [color][from][to]
    int table[HISTORY_SIZE];
    
    HistoryTable() {
        for (int i = 0; i < HISTORY_SIZE; i++) {
            table[i] = 0;
        }
    }
    
    void clear() {
        for (int i = 0; i < HISTORY_SIZE; i++) {
            table[i] = 0;
        }
    }
    
    int index(int color, int from, int to) const {
        return color * 128 * 128 + from * 128 + to;
    }
    
    int get(int color, int from, int to) const {
        return table[index(color, from, to)];
    }
    
    void update(int color, int from, int to, int depth) {
        int idx = index(color, from, to);
        table[idx] += (1 << depth);  // Depth-based bonus
    }
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
    
    // Phase 6A: Move ordering and heuristics
    void reset_search_heuristics();
    void record_cutoff(Move move, int ply, int depth, const Position& pos);
    int score_move(const Position& pos, Move move, int ply, Move pv_move = Move()) const;
    
    // Phase 6B: Alpha-beta search with Late Move Reductions
    int alpha_beta_search(Position& pos, int depth, int alpha, int beta, int ply);
    int quiescence_search(Position& pos, int alpha, int beta, int ply);
    int evaluate_position(const Position& pos) const;
    bool is_move_check(const Position& pos, Move move) const;
    
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

protected:
    // Protected members for derived classes (Phase 6C TypedMonteCarlo)
    Position search_position_;     // Current search position
    std::vector<Edge*> edges_;     // Path through tree
    std::vector<Node*> nodes_;     // Node path for backup
    uint32_t ply_ = 0;            // Current ply in search
    
    // Tree storage and heuristics
    MultiHashMap tree_;            // Zobrist-indexed node table
    
    // Phase 6A: Move ordering heuristics
    KillerMoves killer_moves_;
    HistoryTable history_;
    
    // Configuration parameters (accessible to derived classes)
    double backup_minimax_ = DEFAULT_BACKUP_MINIMAX;
    double prior_learning_rate_ = DEFAULT_PRIOR_LEARNING_RATE;
    int max_ply_ = DEFAULT_MAX_PLY;

private:
    // Private search state
    uint32_t num_simulations_ = 0; // Number of simulations completed
    
    // Configuration parameters (private)
    size_t max_simulations_ = 10000;
    double exploration_ = DEFAULT_EXPLORATION;
    
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

// Phase 6C: TypedMonteCarlo with node type tracking and type-aware search
class TypedMonteCarlo : public MonteCarlo {
public:
    // Inherit constructor from MonteCarlo
    using MonteCarlo::MonteCarlo;
    
    // Type-aware tree policy (choose PV first, then ALL nodes)
    void tree_policy_typed();
    
    // Type-aware backup with bound blending
    void backup_typed(double reward);
    
    // Phase 6D: Transposition table integration
    void set_transposition_table(TranspositionTable* tt) { tt_ = tt; }
    TranspositionTable* get_transposition_table() { return tt_; }

private:
    // Helper: Find best PV edge and best ALL edge if improving
    struct PVAndChallenger {
        TypedEdge* pv = nullptr;
        TypedEdge* challenger = nullptr;  // ALL node if its bound > PV
    };
    
    // Find PV and challenger edges in a node
    PVAndChallenger find_pv_and_challenger(Node* node) const;
    
    // Check if a node's value is exact (no improving ALL nodes)
    bool is_exact_value(Node* node) const;
    
    // Helper to cast edge to TypedEdge (use static_cast since Edge is base)
    TypedEdge* to_typed_edge(Edge* edge) const {
        return static_cast<TypedEdge*>(edge);
    }
    
    // Phase 6D: Transposition table pointer
    TranspositionTable* tt_ = nullptr;
};

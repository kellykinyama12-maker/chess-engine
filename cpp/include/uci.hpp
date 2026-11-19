#pragma once

#include "position.hpp"
#include "mcts_new.hpp"
#include <string>
#include <vector>
#include <unordered_map>
#include <memory>
#include <chrono>
#include <atomic>

// UCI Protocol Handler
// Implements Universal Chess Interface standard for engine-GUI communication
class UciHandler {
public:
    // Constructor
    UciHandler(const std::string& name = "ChessEngine",
               const std::string& author = "Copilot");

    // Main UCI loop - runs until quit command
    void run();

    // Public accessors
    const Position& get_position() const { return current_position_; }
    std::string get_name() const { return engine_name_; }
    std::string get_author() const { return engine_author_; }

private:
    // Engine information
    std::string engine_name_;
    std::string engine_author_;
    static constexpr const char* VERSION = "1.0";

    // Current game state
    Position current_position_;
    std::unique_ptr<TypedMonteCarlo> search_engine_;
    std::atomic<bool> search_running_{false};
    std::chrono::steady_clock::time_point search_start_;

    // Engine options
    std::unordered_map<std::string, std::string> options_;
    int hash_mb_ = 512;        // Transposition table size in MB
    int num_threads_ = 1;      // Number of search threads

    // UCI Command Handlers
    void handle_uci();
    void handle_isready();
    void handle_setoption(const std::vector<std::string>& tokens);
    void handle_ucinewgame();
    void handle_position(const std::vector<std::string>& tokens);
    void handle_go(const std::vector<std::string>& tokens);
    void handle_stop();
    void handle_quit();

    // Helper methods
    static std::vector<std::string> tokenize(const std::string& line);
    
    // Position loading utilities
    void load_fen(const std::string& fen);
    void apply_moves(const std::vector<std::string>& moves);
    
    // Search execution
    void execute_search(int depth = -1, int movetime_ms = -1, 
                       int wtime_ms = -1, int btime_ms = -1,
                       int winc_ms = -1, int binc_ms = -1);
    
    // Output utilities
    static void send_id(const std::string& name, const std::string& author);
    static void send_option(const std::string& name, const std::string& type,
                           const std::string& default_val = "",
                           const std::string& min_val = "",
                           const std::string& max_val = "");
    static void send_uciok();
    static void send_readyok();
    static void send_bestmove(const Move& move, const Move& ponder = Move());
    static void send_info(int depth, int seldepth, int score, 
                         uint64_t nodes, int time_ms,
                         const std::string& pv = "");

    // Helper: Check if position is in starting position
    static bool is_start_position(const Position& pos);
    
    // Helper: Convert move to UCI notation (e.g., "e2e4")
    static std::string move_to_uci(Move move);
    
    // Helper: Parse UCI move notation to Move object
    static Move uci_to_move(const Position& pos, const std::string& uci_move);
};

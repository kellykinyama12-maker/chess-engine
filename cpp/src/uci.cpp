#include "uci.hpp"
#include "move_gen.hpp"
#include <iostream>
#include <sstream>
#include <algorithm>
#include <cstring>

// ============================================================================
// UCI Handler Implementation
// ============================================================================

UciHandler::UciHandler(const std::string& name, const std::string& author)
    : engine_name_(name),
      engine_author_(author) {
    // Initialize with default starting position
    current_position_ = Position("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    
    // Create search engine
    search_engine_ = std::make_unique<TypedMonteCarlo>(10000);
}

void UciHandler::run() {
    std::string line;
    while (std::getline(std::cin, line)) {
        if (line.empty()) continue;
        
        // Tokenize input line
        auto tokens = tokenize(line);
        if (tokens.empty()) continue;
        
        std::string cmd = tokens[0];
        
        // Handle commands
        if (cmd == "uci") {
            handle_uci();
        } else if (cmd == "isready") {
            handle_isready();
        } else if (cmd == "setoption") {
            handle_setoption(tokens);
        } else if (cmd == "ucinewgame") {
            handle_ucinewgame();
        } else if (cmd == "position") {
            handle_position(tokens);
        } else if (cmd == "go") {
            handle_go(tokens);
        } else if (cmd == "stop") {
            handle_stop();
        } else if (cmd == "quit") {
            handle_quit();
            break;
        }
    }
}

std::vector<std::string> UciHandler::tokenize(const std::string& line) {
    std::istringstream iss(line);
    std::vector<std::string> tokens;
    std::string token;
    while (iss >> token) {
        tokens.push_back(token);
    }
    return tokens;
}

void UciHandler::handle_uci() {
    // Send engine identification
    std::cout << "id name " << engine_name_ << " " << VERSION << std::endl;
    std::cout << "id author " << engine_author_ << std::endl;
    
    // Send options
    std::cout << "option name Hash type spin default 512 min 32 max 2048" << std::endl;
    std::cout << "option name Threads type spin default 1 min 1 max 8" << std::endl;
    
    // Acknowledge UCI initialization complete
    std::cout << "uciok" << std::endl;
}

void UciHandler::handle_isready() {
    // Send ready acknowledgment (always ready in this implementation)
    std::cout << "readyok" << std::endl;
}

void UciHandler::handle_setoption(const std::vector<std::string>& tokens) {
    // Format: setoption name <id> value <x>
    if (tokens.size() < 5 || tokens[1] != "name" || tokens[3] != "value") {
        return;
    }
    
    std::string option_name = tokens[2];
    std::string option_value = tokens[4];
    
    // Store option
    options_[option_name] = option_value;
    
    // Handle specific options
    if (option_name == "Hash") {
        try {
            hash_mb_ = std::stoi(option_value);
        } catch (...) {
            hash_mb_ = 512;
        }
    } else if (option_name == "Threads") {
        try {
            num_threads_ = std::stoi(option_value);
            if (search_engine_) {
                search_engine_->set_num_threads(num_threads_);
            }
        } catch (...) {
            num_threads_ = 1;
        }
    }
}

void UciHandler::handle_ucinewgame() {
    // Reset for new game
    current_position_ = Position("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    search_running_ = false;
}

void UciHandler::handle_position(const std::vector<std::string>& tokens) {
    if (tokens.size() < 2) return;
    
    // Parse position command
    if (tokens[1] == "startpos") {
        // Load starting position
        current_position_ = Position("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
        
        // Apply moves if provided
        if (tokens.size() > 2 && tokens[2] == "moves") {
            std::vector<std::string> moves(tokens.begin() + 3, tokens.end());
            apply_moves(moves);
        }
    } else if (tokens[1] == "fen") {
        // Load from FEN
        if (tokens.size() < 3) return;
        
        // Collect FEN string (can have spaces)
        std::string fen;
        int fen_parts = 0;
        size_t i = 2;
        while (i < tokens.size() && fen_parts < 6) {
            if (!fen.empty()) fen += " ";
            fen += tokens[i];
            fen_parts++;
            i++;
        }
        
        load_fen(fen);
        
        // Apply moves if provided
        if (i < tokens.size() && tokens[i] == "moves") {
            std::vector<std::string> moves(tokens.begin() + static_cast<int>(i) + 1, tokens.end());
            apply_moves(moves);
        }
    }
}

void UciHandler::load_fen(const std::string& fen) {
    try {
        current_position_ = Position(fen);
    } catch (...) {
        // Invalid FEN, keep current position
    }
}

void UciHandler::apply_moves(const std::vector<std::string>& moves) {
    for (const auto& uci_move : moves) {
        Move move = uci_to_move(current_position_, uci_move);
        // Check if move is valid (at least one field should be non-zero)
        if (move.from != 0 || move.to != 0) {
            current_position_.make_move(move);
        }
    }
}

Move UciHandler::uci_to_move(const Position& pos, const std::string& uci_move) {
    if (uci_move.length() < 4) return Move();
    
    // Parse UCI notation: e2e4 or e7e8q (promotion)
    int from_file = uci_move[0] - 'a';
    int from_rank = uci_move[1] - '1';
    int to_file = uci_move[2] - 'a';
    int to_rank = uci_move[3] - '1';
    
    if (from_file < 0 || from_file > 7 || from_rank < 0 || from_rank > 7 ||
        to_file < 0 || to_file > 7 || to_rank < 0 || to_rank > 7) {
        return Move();
    }
    
    int from_square = from_rank * 8 + from_file;
    int to_square = to_rank * 8 + to_file;
    
    // Get all legal moves and find matching one
    auto legal_moves = pos.legal_moves();
    for (const auto& move : legal_moves) {
        if (move.from == from_square && move.to == to_square) {
            // Check promotion if specified
            if (uci_move.length() == 5) {
                // Parse promotion piece: n=knight, b=bishop, r=rook, q=queen
                PieceType promo_type = PieceType::NONE;
                switch (uci_move[4]) {
                    case 'n': promo_type = PieceType::KNIGHT; break;
                    case 'b': promo_type = PieceType::BISHOP; break;
                    case 'r': promo_type = PieceType::ROOK; break;
                    case 'q': promo_type = PieceType::QUEEN; break;
                    default: break;
                }
                if (promo_type != PieceType::NONE) {
                    return Move(Square(from_square), Square(to_square), promo_type);
                }
            }
            return move;
        }
    }
    
    return Move();
}

std::string UciHandler::move_to_uci(Move move) {
    std::string uci;
    uci += static_cast<char>('a' + (move.from % 8));
    uci += static_cast<char>('1' + (move.from / 8));
    uci += static_cast<char>('a' + (move.to % 8));
    uci += static_cast<char>('1' + (move.to / 8));
    
    // Add promotion character if applicable
    // This would require additional move information
    
    return uci;
}

void UciHandler::handle_go(const std::vector<std::string>& tokens) {
    // Parse go parameters
    int depth = -1;
    int movetime_ms = -1;
    int wtime_ms = -1;
    int btime_ms = -1;
    int winc_ms = -1;
    int binc_ms = -1;
    
    for (size_t i = 1; i < tokens.size(); ++i) {
        if (tokens[i] == "depth" && i + 1 < tokens.size()) {
            try { depth = std::stoi(tokens[++i]); } catch (...) {}
        } else if (tokens[i] == "movetime" && i + 1 < tokens.size()) {
            try { movetime_ms = std::stoi(tokens[++i]); } catch (...) {}
        } else if (tokens[i] == "wtime" && i + 1 < tokens.size()) {
            try { wtime_ms = std::stoi(tokens[++i]); } catch (...) {}
        } else if (tokens[i] == "btime" && i + 1 < tokens.size()) {
            try { btime_ms = std::stoi(tokens[++i]); } catch (...) {}
        } else if (tokens[i] == "winc" && i + 1 < tokens.size()) {
            try { winc_ms = std::stoi(tokens[++i]); } catch (...) {}
        } else if (tokens[i] == "binc" && i + 1 < tokens.size()) {
            try { binc_ms = std::stoi(tokens[++i]); } catch (...) {}
        }
    }
    
    // Execute search
    execute_search(depth, movetime_ms, wtime_ms, btime_ms, winc_ms, binc_ms);
}

void UciHandler::execute_search(int /*depth*/, int movetime_ms,
                               int wtime_ms, int btime_ms,
                               int winc_ms, int binc_ms) {
    if (!search_engine_) return;
    
    search_running_ = true;
    search_start_ = std::chrono::steady_clock::now();
    
    // Calculate time limit
    int time_limit_ms = movetime_ms;
    if (time_limit_ms < 0) {
        // Use remaining time with increment
        bool is_white = (current_position_.side_to_move() == Color::WHITE);
        int my_time = is_white ? wtime_ms : btime_ms;
        int my_inc = is_white ? winc_ms : binc_ms;
        
        if (my_time > 0) {
            // Simple time management: use 2% of remaining time
            time_limit_ms = std::max(100, my_time / 50);
            if (my_inc > 0) {
                time_limit_ms += my_inc;
            }
        } else {
            time_limit_ms = 1000;  // Default 1 second
        }
    }
    
    // Perform search
    SearchResult result = search_engine_->search(current_position_, time_limit_ms);
    
    // Send best move
    send_bestmove(result.best_move);
    
    search_running_ = false;
}

void UciHandler::handle_stop() {
    search_running_ = false;
}

void UciHandler::handle_quit() {
    search_running_ = false;
}

bool UciHandler::is_start_position(const Position& /*pos*/) {
    // Check if position is the standard starting position
    // This is a simple check; a more robust version would compare FEN
    return true;  // Simplified for now
}

// Output utilities implementation
void UciHandler::send_id(const std::string& name, const std::string& author) {
    std::cout << "id name " << name << std::endl;
    std::cout << "id author " << author << std::endl;
}

void UciHandler::send_option(const std::string& name, const std::string& type,
                             const std::string& default_val,
                             const std::string& min_val,
                             const std::string& max_val) {
    std::cout << "option name " << name << " type " << type;
    if (!default_val.empty()) {
        std::cout << " default " << default_val;
    }
    if (!min_val.empty()) {
        std::cout << " min " << min_val;
    }
    if (!max_val.empty()) {
        std::cout << " max " << max_val;
    }
    std::cout << std::endl;
}

void UciHandler::send_uciok() {
    std::cout << "uciok" << std::endl;
}

void UciHandler::send_readyok() {
    std::cout << "readyok" << std::endl;
}

void UciHandler::send_bestmove(const Move& move, const Move& ponder) {
    std::cout << "bestmove " << move_to_uci(move);
    if (ponder.from != 0 || ponder.to != 0) {
        std::cout << " ponder " << move_to_uci(ponder);
    }
    std::cout << std::endl;
}

void UciHandler::send_info(int depth, int seldepth, int score,
                          uint64_t nodes, int time_ms,
                          const std::string& pv) {
    std::cout << "info depth " << depth << " seldepth " << seldepth
              << " score cp " << score << " nodes " << nodes
              << " time " << time_ms;
    if (!pv.empty()) {
        std::cout << " pv " << pv;
    }
    std::cout << std::endl;
}

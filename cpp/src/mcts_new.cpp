#include "mcts_new.hpp"
#include "move_gen.hpp"
#include <algorithm>
#include <cmath>
#include <chrono>

MonteCarlo::MonteCarlo(size_t max_simulations,
                       double exploration,
                       double backup_minimax,
                       double prior_learning_rate)
    : max_simulations_(max_simulations),
      exploration_(exploration),
      backup_minimax_(backup_minimax),
      prior_learning_rate_(prior_learning_rate) {
    edges_.resize(max_ply_);
    nodes_.resize(max_ply_);
}

SearchResult MonteCarlo::search(Position& root_position, int time_limit_ms) {
    // Reset search state
    reset_search();
    search_position_ = root_position;
    search_start_ = std::chrono::steady_clock::now();
    
    // Create root node
    Node* root = create_root(root_position);
    if (!root || root->children.empty()) {
        // No legal moves available (checkmate or stalemate)
        return SearchResult{Move(), 0.0, 0, {}};
    }
    
    // Main search loop
    while (num_simulations_ < max_simulations_) {
        // Check time limit
        auto elapsed = std::chrono::steady_clock::now() - search_start_;
        if (std::chrono::duration_cast<std::chrono::milliseconds>(elapsed).count() > time_limit_ms) {
            break;
        }
        
        // Reset position for new simulation
        search_position_ = root_position;
        ply_ = 0;
        
        // Tree policy (selection & expansion)
        tree_policy();
        
        // Playout policy (simulation)
        double reward = playout_policy();
        
        // Backup (backpropagation)
        backup(reward);
        
        num_simulations_++;
        stats_.total_simulations++;
    }
    
    // Extract best move from root
    SearchResult result;
    result.best_move = root->children[0].move;
    result.best_value = root->children[0].prior;
    result.visits = root->node_visits;
    
    // Find move with highest visit count
    for (const auto& edge : root->children) {
        if (edge.visits > result.visits) {
            result.best_move = edge.move;
            result.best_value = edge.mean_action_value;
            result.visits = edge.visits;
        }
    }
    
    // Calculate statistics
    stats_.tree_nodes = tree_.size();
    stats_.elapsed_time = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - search_start_);
    
    return result;
}

SearchResult MonteCarlo::search_parallel(Position& root_position, int num_threads, int time_limit_ms) {
    // Reset search state
    reset_search();
    num_simulations_ = 0;
    stats_.total_simulations = 0;
    search_position_ = root_position;
    search_start_ = std::chrono::steady_clock::now();
    
    // Create root node
    Node* root = create_root(root_position);
    if (!root || root->children.empty()) {
        return SearchResult{Move(), 0.0, 0, {}};
    }
    
    // Create thread pool if needed
    if (!thread_pool_ || num_threads != static_cast<int>(thread_pool_->num_workers())) {
        thread_pool_ = std::make_unique<ThreadPool>(num_threads);
    }
    
    // Distribute simulations across threads
    while (num_simulations_ < max_simulations_) {
        auto elapsed = std::chrono::steady_clock::now() - search_start_;
        if (std::chrono::duration_cast<std::chrono::milliseconds>(elapsed).count() > time_limit_ms) {
            break;
        }
        
        // Enqueue work for each thread
        for (int i = 0; i < num_threads && num_simulations_ < max_simulations_; i++) {
            thread_pool_->enqueue([this, &root_position, root, time_limit_ms]() {
                run_simulation(root_position, root, search_start_, time_limit_ms);
            });
            num_simulations_++;
        }
    }
    
    // Wait for all simulations to complete
    thread_pool_->wait_all();
    
    // Extract best move from root
    SearchResult result;
    result.best_move = root->children[0].move;
    result.best_value = root->children[0].prior;
    result.visits = root->node_visits;
    
    // Find move with highest visit count
    for (const auto& edge : root->children) {
        if (edge.visits > result.visits) {
            result.best_move = edge.move;
            result.best_value = edge.mean_action_value;
            result.visits = edge.visits;
        }
    }
    
    // Calculate statistics
    stats_.tree_nodes = tree_.size();
    stats_.elapsed_time = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - search_start_);
    
    return result;
}

void MonteCarlo::run_simulation(const Position& root_position, Node* root,
                                std::chrono::steady_clock::time_point search_start,
                                int time_limit_ms) {
    // Thread-local search state
    Position thread_pos = root_position;
    std::vector<Edge*> thread_edges(max_ply_);
    std::vector<Node*> thread_nodes(max_ply_);
    uint32_t thread_ply = 0;
    
    // Tree policy (selection & expansion)
    while (thread_ply < static_cast<uint32_t>(max_ply_ - 2)) {
        // Lock-free node lookup for thread safety
        Node* current = nullptr;
        {
            std::lock_guard<std::mutex> lock(tree_mutex_);
            current = tree_.find(thread_pos.get_zobrist());
        }
        
        if (!current || current->children.empty()) {
            break;
        }
        
        // Find best child using UCB (no lock needed, read-only)
        Edge* best = nullptr;
        double best_ucb = -1e9;
        for (auto& edge : current->children) {
            double ucb_val = ucb(*current, edge);
            if (ucb_val > best_ucb) {
                best_ucb = ucb_val;
                best = &edge;
            }
        }
        
        if (!best) break;
        
        {
            std::lock_guard<std::mutex> lock(tree_mutex_);
            current->node_visits++;
            best->visits++;
        }
        
        thread_edges[thread_ply] = best;
        thread_nodes[thread_ply] = current;
        thread_pos.make_move(best->move);
        thread_ply++;
    }
    
    // Playout policy (simulation)
    double reward = playout_policy();
    
    // Backup (backpropagation with locking)
    {
        std::lock_guard<std::mutex> lock(tree_mutex_);
        
        double child_best = reward;
        while (thread_ply > 0) {
            thread_ply--;
            thread_pos.unmake_move();
            
            reward = 1.0 - reward;
            
            Edge& edge = *thread_edges[thread_ply];
            Node& node = *thread_nodes[thread_ply];
            
            // Update prior
            double best_prior = 0.0;
            for (const auto& child_edge : node.children) {
                best_prior = std::max(best_prior, child_edge.prior);
            }
            edge.prior += prior_learning_rate_ * ((1.0 - child_best) - edge.prior);
            
            // Update rewards
            edge.action_value += reward;
            edge.mean_action_value = edge.action_value / edge.visits;
            
            // Minimax blending
            child_best = edge.mean_action_value;
            double best_mean = 0.0;
            for (const auto& child_edge : node.children) {
                best_mean = std::max(best_mean, child_edge.mean_action_value);
            }
            reward = reward * (1.0 - backup_minimax_) + best_mean * backup_minimax_;
        }
    }
    
    stats_.total_simulations++;
}

Node* MonteCarlo::create_root(const Position& root_position) {
    uint64_t zobrist = root_position.get_zobrist();
    Node* root = tree_.insert_or_find(zobrist);
    
    if (root->node_visits > 0) {
        // Node already exists in tree (transposition)
        return root;
    }
    
    // Generate children via pseudo-legal move generation
    // For now, we'll expand with equal priors; in full MCTS, 
    // this would call a prior network or iterative deepening
    auto moves = MoveGenerator::generate_legal(root_position);
    
    if (moves.empty()) {
        // No legal moves (mate or stalemate)
        return root;
    }
    
    // Add children with equal priors
    double prior_value = 1.0 / moves.size();
    for (const auto& move : moves) {
        root->children.emplace_back(move, prior_value);
    }
    
    root->node_visits = 1;
    return root;
}

void MonteCarlo::tree_policy() {
    // Selection phase: descend tree using UCB until finding unexpanded node
    while (ply_ < static_cast<uint32_t>(max_ply_ - 2)) {
        Node* current = current_node();
        if (!current || current->children.empty()) {
            // Reached terminal node or leaf
            return;
        }
        
        if (current->node_visits == 0) {
            // Unexpanded node - stop selection
            return;
        }
        
        // Check for game-ending conditions
        if (is_terminal() || is_drawn(search_position_)) {
            return;
        }
        
        // Select best child using UCB
        Edge* ucb_edge = best_child(*current, EdgeStatistic::UCB);
        if (!ucb_edge) return;
        
        // Update statistics
        current->node_visits++;
        ucb_edge->visits++;
        
        // Advance move in search position
        advance_move(ucb_edge);
        edges_[ply_] = ucb_edge;
        nodes_[ply_] = current;
        ply_++;
    }
}

double MonteCarlo::playout_policy() {
    // Simple playout: generate moves and return first legal move as reward
    // In a full MCTS, this could be:
    // 1. Random playout (rollout with random moves)
    // 2. Lightweight evaluation
    // 3. Zero (always return 0 for estimation)
    // For now, we return a nominal value based on game state
    
    if (search_position_.is_checkmate()) {
        // Current side is checkmated (losing)
        return 0.0;
    }
    
    if (search_position_.is_stalemate()) {
        // Stalemate is a draw
        return 0.5;
    }
    
    // Return nominal value (could be replaced with evaluation)
    return 0.5;
}

void MonteCarlo::backup(double reward) {
    // Backpropagation phase: update statistics along the path
    // Reward alternates sign as we back up (perspective of moving side)
    
    while (ply_ > 0) {
        ply_--;
        retreat_move();
        
        // Flip reward from child's perspective to current player's perspective
        reward = 1.0 - reward;
        
        Edge& edge = *edges_[ply_];
        Node& node = *nodes_[ply_];
        
        // Update prior (learning rate blending)
        double best_prior = 0.0;
        for (const auto& child_edge : node.children) {
            best_prior = std::max(best_prior, child_edge.prior);
        }
        
        // Update edge statistics
        edge.action_value += reward;
        edge.visits++;
        edge.mean_action_value = edge.action_value / edge.visits;
        
        // Update prior with blending
        double target = best_prior;  // Target is best prior among siblings
        edge.prior += prior_learning_rate_ * (target - edge.prior);
        
        // Minimax backup: blend current reward with best child's mean
        double best_child_mean = 0.0;
        if (!node.children.empty()) {
            const Edge& best = *best_child(node, EdgeStatistic::MEAN);
            best_child_mean = best.mean_action_value;
        }
        reward = reward * (1.0 - backup_minimax_) + 
                 best_child_mean * backup_minimax_;
    }
}

Edge* MonteCarlo::best_child(const Node& node, EdgeStatistic stat) {
    if (node.children.empty()) return nullptr;
    
    Edge* best = nullptr;
    double best_value = -1e9;
    
    for (auto& edge : const_cast<std::vector<Edge>&>(node.children)) {
        double value = 0.0;
        
        switch (stat) {
            case EdgeStatistic::UCB:
                value = ucb(node, edge);
                break;
            case EdgeStatistic::VISITS:
                value = edge.visits;
                break;
            case EdgeStatistic::MEAN:
                value = edge.visits > 0 ? edge.mean_action_value : -1e9;
                break;
            case EdgeStatistic::PRIOR:
                value = edge.prior;
                break;
        }
        
        if (value > best_value) {
            best_value = value;
            best = &edge;
        }
    }
    
    return best;
}

double MonteCarlo::ucb(const Node& node, const Edge& edge) const {
    // UCB formula: Q(a) + c * sqrt(ln(N) / (1 + n(a)))
    // With modifications for prior and losses avoidance
    
    if (node.node_visits == 0) return 0.0;
    
    // Base value: prior or mean action value
    double result = (edge.visits > 0) ? edge.mean_action_value : edge.prior;
    
    // Exploration term
    double c = exploration_ * std::sqrt(static_cast<double>(node.node_visits));
    double losses = edge.visits > 0 ? (edge.visits - edge.action_value) : 0.0;
    double divisor = losses * UCB_LOSSES_AVOIDANCE + 
                     edge.visits * (1.0 - UCB_LOSSES_AVOIDANCE);
    
    result += c * edge.prior / (1.0 + divisor);
    
    // Logarithmic term for visit balancing
    if (edge.visits > 0 && node.node_visits > 0) {
        result += UCB_LOG_TERM_FACTOR * std::sqrt(std::log(node.node_visits) / edge.visits);
    }
    
    return result;
}

Node* MonteCarlo::current_node() const {
    if (ply_ == 0) {
        return tree_.find(search_position_.get_zobrist());
    }
    return nodes_[ply_];
}

void MonteCarlo::advance_move(Edge* edge) {
    search_position_.make_move(edge->move);
}

void MonteCarlo::retreat_move() {
    search_position_.unmake_move();
}

// ============================================================================
// Phase 6A: Enhanced Move Ordering (Killer Moves + History Heuristic)
// ============================================================================

void MonteCarlo::reset_search_heuristics() {
    killer_moves_.clear();
    history_.clear();
}

void MonteCarlo::record_cutoff(Move move, int ply, int depth, const Position& pos) {
    if (ply >= KillerMoves::MAX_PLY) return;
    
    // Record killer move (for quiet moves only)
    if (pos.piece_at(Square(move.to)).is_empty() && move.promotion == PieceType::NONE) {
        killer_moves_.record(move, ply);
    }
    
    // Update history heuristic with depth-based bonus
    int color = static_cast<int>(pos.side_to_move());
    history_.update(color, move.from, move.to, depth);
}

// MVV-LVA (Most Valuable Victim - Least Valuable Attacker) scoring
// Returns higher value for better captures
static int mvv_lva_score(Piece victim, Piece attacker) {
    static const int victim_scores[] = {0, 1, 3, 3, 5, 9, 0, 0};  // PAWN to KING
    static const int attacker_scores[] = {6, 5, 4, 3, 2, 1, 0, 0};
    
    int victim_val = victim_scores[static_cast<int>(victim.type)];
    int attacker_val = attacker_scores[static_cast<int>(attacker.type)];
    
    return victim_val * 16 + (16 - attacker_val);
}

// Simple Static Exchange Evaluation for move ordering
// Positive = winning capture, Negative = losing capture
static int see(const Position& pos, Move move) {
    Piece victim = pos.piece_at(Square(move.to));
    Piece attacker = pos.piece_at(Square(move.from));
    
    if (victim.is_empty()) return 0;  // Not a capture
    
    // Simple SEE: just return victim value - attacker value
    // A full SEE would recursively evaluate recaptures
    static const int piece_values[] = {1, 3, 3, 5, 9, 0, 0, 0};  // PAWN to KING
    
    int victim_val = piece_values[static_cast<int>(victim.type)];
    int attacker_val = piece_values[static_cast<int>(attacker.type)];
    
    return victim_val - attacker_val;
}

int MonteCarlo::score_move(const Position& pos, Move move, int ply, Move pv_move) const {
    // 1. PV move from principal variation (highest priority)
    if (pv_move == move) {
        return 1000000;
    }
    
    Piece moving_piece = pos.piece_at(Square(move.from));
    Piece target_piece = pos.piece_at(Square(move.to));
    
    // 2. Captures and promotions
    if (!target_piece.is_empty()) {
        // Capture
        int see_value = see(pos, move);
        if (see_value >= 0) {
            // Winning or equal capture: 100k base + MVV-LVA
            return 100000 + mvv_lva_score(target_piece, moving_piece);
        } else {
            // Losing capture: worse than quiet moves, but ordered by value
            return -100000 + mvv_lva_score(target_piece, moving_piece);
        }
    }
    
    if (move.promotion != PieceType::NONE) {
        // Promotion
        if (move.promotion == PieceType::QUEEN) {
            return 95000;  // Queen promotion is very strong
        } else if (move.promotion == PieceType::ROOK) {
            return 94000;
        } else {
            return 93000;  // Minor promotions
        }
    }
    
    // 3. Killer moves (quiet moves that caused cutoffs at this ply)
    if (ply < KillerMoves::MAX_PLY) {
        if (move == killer_moves_.moves[ply][0]) return 90000;
        if (move == killer_moves_.moves[ply][1]) return 80000;
    }
    
    // 4. Quiet moves: ordered by history heuristic
    int color = static_cast<int>(pos.side_to_move());
    int history_score = history_.get(color, move.from, move.to);
    
    return history_score;  // 0-79999 range from history table
}


void MonteCarlo::reset_search() {
    ply_ = 0;
    num_simulations_ = 0;
    stats_ = SearchStats();
    // Don't clear tree_ - it persists across searches for reuse
}

bool MonteCarlo::is_terminal() const {
    return search_position_.is_checkmate() || 
           search_position_.is_stalemate();
}

bool MonteCarlo::is_drawn(const Position& pos) const {
    // Check draw conditions (simplified - full implementation would check:
    // - 50-move rule
    // - threefold repetition  
    // - insufficient material)
    return pos.is_drawn();
}

// ============================================================================
// Phase 6B: Late Move Reductions (LMR) with Alpha-Beta Search
// ============================================================================

// Simple evaluation function (placeholder - would be enhanced)
int MonteCarlo::evaluate_position(const Position& pos) const {
    // Simplified evaluation: material count
    int score = 0;
    
    // Piece values: Pawn=1, Knight=3, Bishop=3, Rook=5, Queen=9, King=0
    static const int piece_values[] = {1, 3, 3, 5, 9, 0};
    
    // Count material for both sides
    for (int sq = 0; sq < 64; sq++) {
        Piece piece = pos.piece_at(Square(sq));
        if (piece.type != PieceType::NONE && piece.type < PieceType::KING) {
            int value = piece_values[static_cast<int>(piece.type)];
            if (piece.color == Color::WHITE) {
                score += value;
            } else {
                score -= value;
            }
        }
    }
    
    return score;
}

bool MonteCarlo::is_move_check(const Position& pos, Move move) const {
    // Check if move gives check (simplified - just check destination square)
    // A full implementation would check if the move puts opponent's king in check
    // For now, use const_cast to avoid const issues - this is a limitation of the current API
    // A better solution would be to have a non-const version
    Position& mutable_pos = const_cast<Position&>(pos);
    mutable_pos.make_move(move);
    bool result = mutable_pos.is_check();
    mutable_pos.unmake_move();
    return result;
}

// Quiescence search: search only captures and checks until quiet
int MonteCarlo::quiescence_search(Position& pos, int alpha, int beta, int ply) {
    // Terminal conditions
    if (ply >= MAX_PLY) {
        return evaluate_position(pos);
    }
    
    // Check for draw
    if (ply > 0 && is_drawn(pos)) {
        return 0;
    }
    
    // Evaluate quiet position
    int static_eval = evaluate_position(pos);
    
    // Fail-soft: if eval already beats beta, return beta
    if (static_eval >= beta) {
        return beta;
    }
    
    // Update alpha
    if (static_eval > alpha) {
        alpha = static_eval;
    }
    
    // Generate moves
    std::vector<Move> moves = MoveGenerator::generate_legal(pos);
    
    // Search only captures and checks
    for (const auto& move : moves) {
        // Only search captures and checks in quiescence
        bool is_capture = !pos.piece_at(Square(move.to)).is_empty();
        bool is_check = is_move_check(pos, move);
        
        if (!is_capture && !is_check) {
            continue;
        }
        
        pos.make_move(move);
        int score = -quiescence_search(pos, -beta, -alpha, ply + 1);
        pos.unmake_move();
        
        if (score >= beta) {
            return beta;
        }
        
        if (score > alpha) {
            alpha = score;
        }
    }
    
    return alpha;
}

// Alpha-beta search with Late Move Reductions
int MonteCarlo::alpha_beta_search(Position& pos, int depth, int alpha, int beta, int ply) {
    // Terminal conditions
    if (ply >= MAX_PLY || depth <= 0) {
        return quiescence_search(pos, alpha, beta, ply);
    }
    
    // Check for draw
    if (ply > 0 && is_drawn(pos)) {
        return 0;
    }
    
    // Check if position is terminal
    if (pos.is_checkmate()) {
        return -MATE_SCORE + ply;
    }
    if (pos.is_stalemate()) {
        return 0;
    }
    
    // Generate and score moves
    std::vector<Move> moves = MoveGenerator::generate_legal(pos);
    
    // Sort moves using Phase 6A heuristics
    std::sort(moves.begin(), moves.end(), [this, &pos, ply](Move a, Move b) {
        return score_move(pos, a, ply) > score_move(pos, b, ply);
    });
    
    int best_score = -MATE_SCORE;
    bool is_pv_node = (beta - alpha > 1);  // Principal variation node
    
    for (int move_idx = 0; move_idx < static_cast<int>(moves.size()); move_idx++) {
        Move move = moves[move_idx];
        
        // Check move properties
        bool is_capture = !pos.piece_at(Square(move.to)).is_empty();
        bool is_promotion = move.promotion != PieceType::NONE;
        bool is_quiet = !is_capture && !is_promotion;
        
        int reduction = 0;
        
        // Phase 6B: Late Move Reduction logic
        // Apply LMR to quiet moves at ALL nodes (zero-window)
        if (is_quiet && 
            !is_pv_node && 
            !pos.is_check() && 
            depth >= 3 && 
            move_idx >= 3) {
            
            // Reduction formula: 1 ply for moves 3-5, 2 plies for move 6+
            reduction = (move_idx >= 6) ? 2 : 1;
        }
        
        // Make move and search
        pos.make_move(move);
        
        int score;
        int new_depth = std::max(1, depth - 1 - reduction);
        
        // First move or reduced search
        if (move_idx == 0) {
            score = -alpha_beta_search(pos, depth - 1, -beta, -alpha, ply + 1);
        } else {
            // Zero-window search
            score = -alpha_beta_search(pos, new_depth, -alpha - 1, -alpha, ply + 1);
            
            // If reduction failed (score > alpha), re-search at full depth
            if (reduction > 0 && score > alpha) {
                score = -alpha_beta_search(pos, depth - 1, -beta, -alpha, ply + 1);
            }
            
            // If this move is the new best and we're in PV node
            if (is_pv_node && score > alpha && score < beta) {
                score = -alpha_beta_search(pos, depth - 1, -beta, -alpha, ply + 1);
            }
        }
        
        pos.unmake_move();
        
        // Record cutoff for killer/history heuristics
        if (score >= beta && is_quiet) {
            record_cutoff(move, ply, depth, pos);
        }
        
        // Update best score
        if (score > best_score) {
            best_score = score;
        }
        
        // Alpha-beta pruning
        if (score >= beta) {
            return beta;  // Fail-soft: return at least beta
        }
        
        if (score > alpha) {
            alpha = score;
        }
    }
    
    return best_score;
}

            // ============================================================================
            // Phase 6C: TypedMonteCarlo Implementation
            // ============================================================================

            TypedMonteCarlo::PVAndChallenger TypedMonteCarlo::find_pv_and_challenger(Node* node) const {
                PVAndChallenger result;
    
                if (!node || node->children.empty()) {
                    return result;
                }
    
                // Find best PV edge and best ALL edge
                for (auto& edge : node->children) {
                    auto* typed_edge = static_cast<TypedEdge*>(&edge);
        
                    if (typed_edge->type == NodeType::pv) {
                        // Best PV edge (highest prior)
                        if (result.pv == nullptr || typed_edge->prior > result.pv->prior) {
                            result.pv = typed_edge;
                        }
                    } else {
                        // ALL edge (upper bound) - consider as challenger
                        if (result.challenger == nullptr || typed_edge->prior > result.challenger->prior) {
                            result.challenger = typed_edge;
                        }
                    }
                }
    
                // Challenger is only interesting if it beats PV score
                if (result.pv != nullptr && result.challenger != nullptr) {
                    if (result.challenger->prior <= result.pv->prior) {
                        result.challenger = nullptr;
                    }
                }
    
                return result;
            }

            bool TypedMonteCarlo::is_exact_value(Node* node) const {
                if (!node || node->children.empty()) {
                    return true;
                }
    
                auto [pv, challenger] = find_pv_and_challenger(node);
    
                // Value is exact only if:
                // 1. We have a PV node (exact value), AND
                // 2. No ALL node has a better bound than it
                return pv != nullptr && challenger == nullptr;
            }

            void TypedMonteCarlo::tree_policy_typed() {
                // Traverse tree following type-aware strategy:
                // 1. Prefer PV nodes (exact moves)
                // 2. Then try ALL nodes that might improve
                // 3. Stop at uninitialized nodes or exact values
    
                while (ply_ > 0 && 
                       nodes_[ply_]->node_visits > 0 &&
                       !nodes_[ply_]->children.empty() &&
                       ply_ < static_cast<uint32_t>(max_ply_ - 2)) {
        
                    Node* current = nodes_[ply_];
                    auto [pv, challenger] = find_pv_and_challenger(current);
        
                    // Choose which edge to follow
                    TypedEdge* edge_to_follow = nullptr;
                    if (challenger != nullptr) {
                        // Follow challenger (ALL node with improving bound)
                        edge_to_follow = challenger;
                    } else if (pv != nullptr) {
                        // Follow PV (exact value)
                        edge_to_follow = pv;
                    } else {
                        break;  // No edges to follow
                    }
        
                    // Update statistics
                    current->node_visits++;
                    edge_to_follow->visits++;
        
                    // Record edge and make move
                    edges_[ply_] = edge_to_follow;
                    search_position_.make_move(edge_to_follow->move);
                    ply_++;
                    nodes_[ply_] = tree_.insert_or_find(search_position_.get_zobrist());
                }
            }

            void TypedMonteCarlo::backup_typed(double reward) {
                // Type-aware backup:
                // - Exact values (PV): directly replace parent priors
                // - Bounds (ALL): blend into priors using learning rate
                // - Type promotion: ALL → PV when bound becomes exact
    
                double child_best = reward;
                bool child_exact = is_exact_value(nodes_[ply_]);
    
                while (ply_ > 0) {
                    // Undo move
                    search_position_.unmake_move();
                    reward = 1.0 - reward;
        
                    TypedEdge* edge = static_cast<TypedEdge*>(edges_[ply_]);
                    double target = 1.0 - child_best;
        
                    if (child_exact) {
                        // Exact value: direct update and promote to PV
                        edge->prior = target;
                        edge->type = NodeType::pv;
                    } else {
                        // Bound: blend update (move towards target at learning rate)
                        edge->prior += prior_learning_rate_ * (target - edge->prior);
                        // Keep type as-is (ALL for upper bounds)
                    }
        
                    // Update action statistics
                    edge->action_value += reward;
                    edge->mean_action_value = edge->action_value / edge->visits;
        
                    // Move to parent
                    ply_--;
        
                    // Update best child and check if parent is exact
                    Node* parent = nodes_[ply_];
                    auto [pv, _] = find_pv_and_challenger(parent);
        
                    if (pv != nullptr) {
                        child_best = pv->prior;
                    } else {
                        child_best = 0.0;
                    }
        
                    child_exact = is_exact_value(parent);
        
                    // Apply minimax blending with alpha-beta bounds
                    // Mix between pure averaging and minimax value
                    double minimax_value = 0.0;
                    for (const auto& e : parent->children) {
                        const auto* typed = static_cast<const TypedEdge*>(&e);
                        if (typed->mean_action_value > minimax_value) {
                            minimax_value = typed->mean_action_value;
                        }
                    }
        
                    reward = reward * (1.0 - backup_minimax_) + minimax_value * backup_minimax_;
                }
            }

// ============================================================================
// PHASE 6D: Transposition Table Implementation
// ============================================================================

TranspositionTable::TranspositionTable(size_t size)
    : table_(size) {
    // Initialize all buckets
    for (auto& bucket : table_) {
        bucket.count = 0;
    }
}

int TranspositionTable::find_entry_in_bucket(const Bucket& bucket, uint64_t key) const {
    for (uint8_t i = 0; i < bucket.count && i < BUCKET_SIZE; ++i) {
        if (bucket.entries[i].key == key) {
            return i;
        }
    }
    return -1;
}

int TranspositionTable::find_replacement_slot(Bucket& bucket) const {
    // If bucket not full, return next empty slot
    if (bucket.count < BUCKET_SIZE) {
        return bucket.count;
    }
    
    // Bucket full: find oldest (smallest timestamp)
    int oldest_idx = 0;
    uint32_t oldest_ts = bucket.entries[0].timestamp;
    
    for (uint8_t i = 1; i < BUCKET_SIZE; ++i) {
        if (bucket.entries[i].timestamp < oldest_ts) {
            oldest_ts = bucket.entries[i].timestamp;
            oldest_idx = i;
        }
    }
    
    return oldest_idx;
}

TranspositionEntry* TranspositionTable::probe(uint64_t key, int depth) {
    if (table_.empty()) return nullptr;
    
    ++probes_;
    
    size_t bucket_idx = key % table_.size();
    Bucket& bucket = table_[bucket_idx];
    
    int entry_idx = find_entry_in_bucket(bucket, key);
    if (entry_idx == -1) {
        return nullptr;  // Miss
    }
    
    TranspositionEntry* entry = &bucket.entries[entry_idx];
    
    // Update timestamp and return if applicable
    if (entry->depth >= depth) {
        ++hits_;
        entry->timestamp = generation_;
        return entry;
    }
    
    return nullptr;  // Entry too shallow for this depth
}

void TranspositionTable::store(uint64_t key, int depth, double value, NodeType type) {
    if (table_.empty()) return;
    
    ++stores_;
    ++generation_;
    
    size_t bucket_idx = key % table_.size();
    Bucket& bucket = table_[bucket_idx];
    
    // Check if entry already exists
    int entry_idx = find_entry_in_bucket(bucket, key);
    
    if (entry_idx != -1) {
        // Update existing entry if new depth is deeper
        if (depth > bucket.entries[entry_idx].depth) {
            bucket.entries[entry_idx] = TranspositionEntry(key, depth, value, type, generation_);
        }
        return;
    }
    
    // Find replacement slot
    int slot_idx = find_replacement_slot(bucket);
    bucket.entries[slot_idx] = TranspositionEntry(key, depth, value, type, generation_);
    
    // Update bucket count if adding new entry
    if (slot_idx == bucket.count && bucket.count < BUCKET_SIZE) {
        ++bucket.count;
    }
}

void TranspositionTable::print_stats() const {
    if (probes_ == 0) {
        printf("TranspositionTable: No probes yet\n");
        return;
    }
    
    printf("TranspositionTable Statistics:\n");
    printf("  Total entries:   %zu\n", table_.size());
    printf("  Probes:          %llu\n", static_cast<unsigned long long>(probes_));
    printf("  Hits:            %llu\n", static_cast<unsigned long long>(hits_));
    printf("  Stores:          %llu\n", static_cast<unsigned long long>(stores_));
    printf("  Hit rate:        %.2f%%\n", get_hit_rate());
    
    // Calculate average bucket fill
    uint64_t total_filled = 0;
    for (const auto& bucket : table_) {
        total_filled += bucket.count;
    }
    printf("  Avg bucket fill: %.2f / %zu\n", 
           static_cast<double>(total_filled) / table_.size(), 
           BUCKET_SIZE);
}

void TranspositionTable::clear() {
    for (auto& bucket : table_) {
        for (uint8_t i = 0; i < bucket.count; ++i) {
            bucket.entries[i] = TranspositionEntry();
        }
        bucket.count = 0;
    }
    
    hits_ = 0;
    probes_ = 0;
    stores_ = 0;
    generation_ = 0;
}


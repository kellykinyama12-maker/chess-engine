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

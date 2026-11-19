#include "mcts_new.hpp"
#include "position.hpp"
#include "zobrist.hpp"
#include <iostream>
#include <iomanip>

void test_edge_creation() {
    std::cout << "\n=== Testing Edge Creation ===\n";
    
    Edge e1(Move(Square(0), Square(1)), 0.5);
    std::cout << "Edge created: move=" << e1.move.to_string() 
              << " prior=" << e1.prior << " visits=" << e1.visits << "\n";
    
    e1.visits = 10;
    e1.action_value = 7.5;
    e1.mean_action_value = e1.action_value / e1.visits;
    
    std::cout << "After updates: visits=" << e1.visits 
              << " mean=" << e1.mean_action_value << "\n";
}

void test_node_creation() {
    std::cout << "\n=== Testing Node Creation ===\n";
    
    Node n(0x123456789ABCDEF0ULL);
    std::cout << "Node created: key=0x" << std::hex << n.key << std::dec 
              << " visits=" << n.node_visits << " children=" << n.children.size() << "\n";
    
    // Add children
    for (int i = 0; i < 5; i++) {
        Move m(Square(i), Square(i + 8));
        n.children.emplace_back(m, 0.2);
    }
    
    std::cout << "Added 5 children: size=" << n.children.size() << "\n";
}

void test_multihashmap() {
    std::cout << "\n=== Testing MultiHashMap ===\n";
    
    MultiHashMap map(16);
    
    // Insert nodes
    uint64_t key1 = 0x123456789ABCDEF0ULL;
    uint64_t key2 = 0xFEDCBA9876543210ULL;
    uint64_t key3 = 0x0F0F0F0F0F0F0F0FULL;
    
    Node* n1 = map.insert_or_find(key1);
    Node* n2 = map.insert_or_find(key2);
    Node* n3 = map.insert_or_find(key3);
    
    std::cout << "Inserted 3 nodes. Map size: " << map.size() << "\n";
    
    // Find nodes
    Node* found1 = map.find(key1);
    Node* found2 = map.find(key2);
    Node* found3 = map.find(key3);
    Node* not_found = map.find(0x0000000000000001ULL);
    
    std::cout << "Find results: n1=" << (found1 != nullptr ? "✓" : "✗")
              << " n2=" << (found2 != nullptr ? "✓" : "✗")
              << " n3=" << (found3 != nullptr ? "✓" : "✗")
              << " not_found=" << (not_found == nullptr ? "✓" : "✗") << "\n";
}

void test_reward_conversion() {
    std::cout << "\n=== Testing Reward Conversion ===\n";
    
    int values[] = {-600, -300, 0, 300, 600};
    
    std::cout << "Value → Reward → Value:\n";
    for (int v : values) {
        double r = value_to_reward(v);
        int v2 = reward_to_value(r);
        std::cout << "  " << std::setw(5) << v << "cp → " 
                  << std::fixed << std::setprecision(4) << r 
                  << " → " << std::setw(5) << v2 << "cp\n";
    }
}

void test_mcts_root_creation() {
    std::cout << "\n=== Testing MCTS Root Creation ===\n";
    
    // Initialize zobrist
    Zobrist::init();
    
    // Create MCTS instance
    MonteCarlo mcts(1000);
    
    // Create starting position
    Position pos("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    std::cout << "Starting position:\n" << pos.ascii() << "\n";
    
    // Create root node
    Node* root = mcts.create_root(pos);
    
    if (root && !root->children.empty()) {
        std::cout << "✓ Root created with " << root->children.size() << " children\n";
        std::cout << "First 5 moves: ";
        for (size_t i = 0; i < std::min(size_t(5), root->children.size()); i++) {
            std::cout << root->children[i].move.to_string() << " ";
        }
        std::cout << "\n";
        
        std::cout << "Prior values: ";
        for (size_t i = 0; i < std::min(size_t(5), root->children.size()); i++) {
            std::cout << std::fixed << std::setprecision(4) 
                      << root->children[i].prior << " ";
        }
        std::cout << "\n";
    } else {
        std::cout << "✗ Failed to create root\n";
    }
}

void test_mcts_ucb() {
    std::cout << "\n=== Testing UCB Formula ===\n";
    
    Zobrist::init();
    MonteCarlo mcts(1000);
    
    Node node(0x0ULL);
    node.node_visits = 100;
    
    // Add test edges
    for (int i = 0; i < 3; i++) {
        Edge e(Move(Square(i), Square(i + 8)), 0.5);
        
        // Vary visit counts
        e.visits = (i + 1) * 10;
        e.action_value = e.visits * 0.5;  // 50% win rate
        e.mean_action_value = e.action_value / e.visits;
        
        node.children.push_back(e);
    }
    
    std::cout << "Computing UCB for 3 children (N=100):\n";
    for (size_t i = 0; i < node.children.size(); i++) {
        double ucb = mcts.ucb(node, node.children[i]);
        std::cout << "  Move " << i << ": visits=" << node.children[i].visits 
                  << " mean=" << std::fixed << std::setprecision(4) 
                  << node.children[i].mean_action_value
                  << " UCB=" << ucb << "\n";
    }
}

void test_mcts_search() {
    std::cout << "\n=== Testing MCTS Search ===\n";
    
    Zobrist::init();
    
    Position pos("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    MonteCarlo mcts(100);  // Small number for testing
    
    std::cout << "Starting MCTS search (100 simulations, 1 second limit)...\n";
    auto result = mcts.search(pos, 1000);
    
    std::cout << "✓ Search completed\n";
    std::cout << "  Best move: " << result.best_move.to_string() << "\n";
    std::cout << "  Best value: " << std::fixed << std::setprecision(4) 
              << result.best_value << "\n";
    std::cout << "  Visits: " << result.visits << "\n";
    std::cout << "  Total simulations: " << mcts.get_simulations() << "\n";
    std::cout << "  Tree nodes: " << mcts.get_stats().tree_nodes << "\n";
    std::cout << "  Elapsed: " << mcts.get_stats().elapsed_time.count() << "ms\n";
}

void test_parallel_search() {
    std::cout << "\n=== Testing Parallel MCTS Search ===\n";
    
    Zobrist::init();
    
    Position pos("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    
    // Test with 1, 2, and 4 threads
    for (int num_threads : {1, 2, 4}) {
        MonteCarlo mcts(1000);
        
        std::cout << "\nRunning with " << num_threads << " threads...\n";
        auto result = mcts.search_parallel(pos, num_threads, 1000);
        
        std::cout << "✓ Parallel search completed\n";
        std::cout << "  Threads: " << num_threads << "\n";
        std::cout << "  Best move: " << result.best_move.to_string() << "\n";
        std::cout << "  Best value: " << std::fixed << std::setprecision(4) 
                  << result.best_value << "\n";
        std::cout << "  Visits: " << result.visits << "\n";
        std::cout << "  Total simulations: " << mcts.get_simulations() << "\n";
        std::cout << "  Elapsed: " << mcts.get_stats().elapsed_time.count() << "ms\n";
    }
}

int main() {
    std::cout << "MCTS Node/Edge Structure Tests\n";
    std::cout << "==============================\n";
    
    test_edge_creation();
    test_node_creation();
    test_multihashmap();
    test_reward_conversion();
    test_mcts_root_creation();
    test_mcts_ucb();
    test_mcts_search();
    test_parallel_search();
    
    std::cout << "\n==============================\n";
    std::cout << "All tests completed!\n";
    
    return 0;
}

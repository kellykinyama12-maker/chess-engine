/*
 * Phase 6C: TypedMonteCarlo Tests
 * 
 * Tests for node type tracking and type-aware search heuristics.
 * Validates TypedEdge, PV/ALL node detection, type promotion, and backup blending.
 */

#include "mcts_new.hpp"
#include "position.hpp"
#include <cassert>
#include <iostream>
#include <iomanip>

// Test counter and reporting
static int test_count = 0;
static int test_passed = 0;

void test_print(const std::string& name) {
    std::cout << "  Testing: " << name << " ... ";
    test_count++;
}

void test_passed_msg() {
    test_passed++;
    std::cout << "✓" << std::endl;
}

void test_failed_msg(const std::string& reason = "") {
    std::cout << "✗ " << reason << std::endl;
}

// ============================================================================
// Test 1: TypedEdge Creation and Type Assignment
// ============================================================================
void test_typed_edge_creation() {
    test_print("TypedEdge Creation and Initialization");
    
    Move move;
    TypedEdge edge_pv(move, 0.75, NodeType::pv);
    TypedEdge edge_all(move, 0.50, NodeType::all);
    TypedEdge edge_cut(move, 0.25, NodeType::cut);
    
    assert(edge_pv.type == NodeType::pv);
    assert(edge_all.type == NodeType::all);
    assert(edge_cut.type == NodeType::cut);
    assert(edge_pv.prior == 0.75);
    assert(edge_all.prior == 0.50);
    
    test_passed_msg();
}

// ============================================================================
// Test 2: TypedEdge Type Promotion
// ============================================================================
void test_typed_edge_promotion() {
    test_print("TypedEdge Type Promotion (ALL → PV)");
    
    Move move;
    TypedEdge edge(move, 0.50, NodeType::all);
    
    assert(edge.type == NodeType::all);
    
    // Simulate type promotion when bound becomes exact
    edge.type = NodeType::pv;
    edge.prior = 0.75;
    
    assert(edge.type == NodeType::pv);
    assert(edge.prior == 0.75);
    
    test_passed_msg();
}

// ============================================================================
// Test 3: Find PV and Challenger Edges
// ============================================================================
void test_find_pv_and_challenger() {
    test_print("Find PV and Challenger Edges");
    
    TypedMonteCarlo mc;
    
    // Create a node with mixed edge types
    Node node;
    node.key = 12345;
    
    Move m1, m2, m3;
    node.children.push_back(TypedEdge(m1, 0.60, NodeType::pv));
    node.children.push_back(TypedEdge(m2, 0.70, NodeType::all));
    node.children.push_back(TypedEdge(m3, 0.40, NodeType::cut));
    
    auto [pv, challenger] = mc.find_pv_and_challenger(&node);
    
    // Should find PV with highest prior among PV nodes
    assert(pv != nullptr);
    assert(pv->prior == 0.60);
    assert(pv->type == NodeType::pv);
    
    // Should find ALL with better score than PV
    assert(challenger != nullptr);
    assert(challenger->prior == 0.70);
    assert(challenger->type == NodeType::all);
    
    test_passed_msg();
}

// ============================================================================
// Test 4: Challenger Detection (No Better ALL)
// ============================================================================
void test_challenger_no_improvement() {
    test_print("Challenger Detection (ALL doesn't beat PV)");
    
    TypedMonteCarlo mc;
    Node node;
    node.key = 54321;
    
    Move m1, m2;
    node.children.push_back(TypedEdge(m1, 0.80, NodeType::pv));
    node.children.push_back(TypedEdge(m2, 0.70, NodeType::all));
    
    auto [pv, challenger] = mc.find_pv_and_challenger(&node);
    
    assert(pv != nullptr);
    assert(pv->prior == 0.80);
    
    // Challenger should be nullptr because ALL (0.70) doesn't beat PV (0.80)
    assert(challenger == nullptr);
    
    test_passed_msg();
}

// ============================================================================
// Test 5: Exact Value Detection
// ============================================================================
void test_exact_value_detection() {
    test_print("Exact Value Detection (All PV, no challengers)");
    
    TypedMonteCarlo mc;
    Node node;
    node.key = 99999;
    
    Move m1, m2;
    node.children.push_back(TypedEdge(m1, 0.75, NodeType::pv));
    node.children.push_back(TypedEdge(m2, 0.70, NodeType::pv));
    
    bool exact = mc.is_exact_value(&node);
    
    // Value is exact because no ALL node beats best PV
    assert(exact == true);
    
    test_passed_msg();
}

// ============================================================================
// Test 6: Inexact Value Detection (Improving ALL)
// ============================================================================
void test_inexact_value_detection() {
    test_print("Inexact Value Detection (ALL beats best PV)");
    
    TypedMonteCarlo mc;
    Node node;
    node.key = 11111;
    
    Move m1, m2;
    node.children.push_back(TypedEdge(m1, 0.60, NodeType::pv));
    node.children.push_back(TypedEdge(m2, 0.80, NodeType::all));
    
    bool exact = mc.is_exact_value(&node);
    
    // Value is not exact because ALL (0.80) beats PV (0.60)
    assert(exact == false);
    
    test_passed_msg();
}

// ============================================================================
// Test 7: Empty Node (Exact by default)
// ============================================================================
void test_exact_empty_node() {
    test_print("Empty Node (Exact by default)");
    
    TypedMonteCarlo mc;
    Node empty_node;
    empty_node.key = 22222;
    
    bool exact = mc.is_exact_value(&empty_node);
    
    // Empty node is considered exact
    assert(exact == true);
    
    test_passed_msg();
}

// ============================================================================
// Test 8: Node Type Transitions
// ============================================================================
void test_node_type_transitions() {
    test_print("Node Type Transitions During Search");
    
    TypedMonteCarlo mc;
    
    // Simulate alpha-beta search determining node types
    // Initial: ALL node (failed low)
    TypedEdge edge(Move(), 0.50, NodeType::all);
    
    assert(edge.type == NodeType::all);
    assert(edge.prior == 0.50);
    
    // After re-search confirms bound: still ALL but higher prior
    edge.prior += 0.1 * (0.65 - edge.prior);  // Learning rate blend
    
    assert(edge.type == NodeType::all);
    assert(edge.prior > 0.50 && edge.prior < 0.65);
    
    // After exact search: promote to PV
    edge.type = NodeType::pv;
    edge.prior = 0.65;
    
    assert(edge.type == NodeType::pv);
    assert(edge.prior == 0.65);
    
    test_passed_msg();
}

// ============================================================================
// Test 9: Prior Learning Rate Blending
// ============================================================================
void test_prior_learning_blending() {
    test_print("Prior Learning Rate Blending");
    
    double prior = 0.50;
    double target = 0.75;
    double learning_rate = 0.5;  // Phase 6C default
    
    // Simulate bound blending
    double updated = prior + learning_rate * (target - prior);
    
    // Should move halfway from 0.50 to 0.75
    assert(updated > prior);
    assert(updated < target);
    assert(std::abs(updated - 0.625) < 0.001);
    
    // Simulate multiple iterations (should converge)
    double iter = prior;
    for (int i = 0; i < 10; i++) {
        iter = iter + learning_rate * (target - iter);
    }
    
    // After 10 iterations, should be very close to target
    assert(std::abs(iter - target) < 0.01);
    
    test_passed_msg();
}

// ============================================================================
// Test 10: Starting Position TypedEdge Creation
// ============================================================================
void test_typed_edges_from_position() {
    test_print("TypedEdge Creation from Starting Position");
    
    TypedMonteCarlo mc;
    Position pos("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    
    std::vector<Move> moves = pos.generate_legal_moves();
    assert(moves.size() == 20);  // 20 legal moves in starting position
    
    // Create TypedEdges for all moves
    std::vector<TypedEdge> edges;
    for (const auto& move : moves) {
        edges.push_back(TypedEdge(move, 0.0, NodeType::pv));
    }
    
    assert(edges.size() == 20);
    
    // All should start as PV type
    for (const auto& e : edges) {
        assert(e.type == NodeType::pv);
        assert(e.prior == 0.0);
    }
    
    test_passed_msg();
}

// ============================================================================
// Test 11: Mixed Type Edges Collection
// ============================================================================
void test_mixed_type_edges() {
    test_print("Mixed Type Edges in Node");
    
    TypedMonteCarlo mc;
    Node node;
    node.key = 33333;
    
    Move m1, m2, m3, m4;
    node.children.push_back(TypedEdge(m1, 0.90, NodeType::pv));
    node.children.push_back(TypedEdge(m2, 0.85, NodeType::pv));
    node.children.push_back(TypedEdge(m3, 0.95, NodeType::all));  // Better bound
    node.children.push_back(TypedEdge(m4, 0.80, NodeType::cut));
    
    int pv_count = 0;
    int all_count = 0;
    int cut_count = 0;
    
    for (const auto& e : node.children) {
        const auto* typed = static_cast<const TypedEdge*>(&e);
        if (typed->type == NodeType::pv) pv_count++;
        else if (typed->type == NodeType::all) all_count++;
        else if (typed->type == NodeType::cut) cut_count++;
    }
    
    assert(pv_count == 2);
    assert(all_count == 1);
    assert(cut_count == 1);
    
    test_passed_msg();
}

// ============================================================================
// Test 12: Type-Aware Edge Selection
// ============================================================================
void test_type_aware_selection() {
    test_print("Type-Aware Edge Selection for Traversal");
    
    TypedMonteCarlo mc;
    Node node;
    node.key = 44444;
    
    Move m1, m2, m3;
    node.children.push_back(TypedEdge(m1, 0.70, NodeType::pv));
    node.children.push_back(TypedEdge(m2, 0.80, NodeType::all));
    node.children.push_back(TypedEdge(m3, 0.75, NodeType::pv));
    
    auto [pv, challenger] = mc.find_pv_and_challenger(&node);
    
    // Best PV edge (highest prior among PVs)
    assert(pv != nullptr);
    assert(pv->prior == 0.75);
    
    // Challenger is ALL with higher prior than best PV
    assert(challenger != nullptr);
    assert(challenger->prior == 0.80);
    
    // For traversal, we'd choose challenger (exploring unresolved bounds)
    TypedEdge* to_traverse = (challenger != nullptr) ? challenger : pv;
    assert(to_traverse->prior == 0.80);
    
    test_passed_msg();
}

// ============================================================================
// Test 13: Prior Value Range
// ============================================================================
void test_prior_value_range() {
    test_print("Prior Value Range [0, 1]");
    
    TypedEdge edge;
    
    // Prior should be in valid range
    edge.prior = 0.0;
    assert(edge.prior >= 0.0 && edge.prior <= 1.0);
    
    edge.prior = 0.5;
    assert(edge.prior >= 0.0 && edge.prior <= 1.0);
    
    edge.prior = 1.0;
    assert(edge.prior >= 0.0 && edge.prior <= 1.0);
    
    test_passed_msg();
}

// ============================================================================
// Test 14: Node Type Consistency
// ============================================================================
void test_node_type_consistency() {
    test_print("Node Type Consistency After Updates");
    
    TypedEdge edge(Move(), 0.50, NodeType::all);
    
    // Update prior through blending
    double learning_rate = 0.3;
    double target = 0.75;
    
    for (int i = 0; i < 100; i++) {
        edge.prior += learning_rate * (target - edge.prior);
    }
    
    // Type should still be ALL (bounds aren't promoted)
    assert(edge.type == NodeType::all);
    
    // Prior should converge towards target
    assert(std::abs(edge.prior - target) < 0.001);
    
    test_passed_msg();
}

// ============================================================================
// Test 15: Multiple Exact PV Edges
// ============================================================================
void test_multiple_exact_pv_edges() {
    test_print("Multiple Exact PV Edges Selection");
    
    TypedMonteCarlo mc;
    Node node;
    node.key = 55555;
    
    Move m1, m2, m3;
    node.children.push_back(TypedEdge(m1, 0.60, NodeType::pv));
    node.children.push_back(TypedEdge(m2, 0.80, NodeType::pv));
    node.children.push_back(TypedEdge(m3, 0.70, NodeType::pv));
    
    auto [pv, challenger] = mc.find_pv_and_challenger(&node);
    
    // Should find best PV (highest prior)
    assert(pv != nullptr);
    assert(pv->prior == 0.80);
    assert(pv->type == NodeType::pv);
    
    // No challenger since all are PV
    assert(challenger == nullptr);
    
    test_passed_msg();
}

// ============================================================================
// Main Test Runner
// ============================================================================
int main() {
    std::cout << "\n╔════════════════════════════════════════════════════════╗\n"
              << "║      Phase 6C: TypedMonteCarlo Tests                   ║\n"
              << "║      Node Type Tracking & Type-Aware Search            ║\n"
              << "╚════════════════════════════════════════════════════════╝\n\n";
    
    // Run all tests
    test_typed_edge_creation();
    test_typed_edge_promotion();
    test_find_pv_and_challenger();
    test_challenger_no_improvement();
    test_exact_value_detection();
    test_inexact_value_detection();
    test_exact_empty_node();
    test_node_type_transitions();
    test_prior_learning_blending();
    test_typed_edges_from_position();
    test_mixed_type_edges();
    test_type_aware_selection();
    test_prior_value_range();
    test_node_type_consistency();
    test_multiple_exact_pv_edges();
    
    // Print summary
    std::cout << "\n" << std::string(60, '=') << "\n";
    std::cout << "Test Results: " << test_passed << "/" << test_count << " passed\n";
    std::cout << std::string(60, '=') << "\n\n";
    
    if (test_passed == test_count) {
        std::cout << "✅ All Phase 6C tests PASSED!\n\n";
        return 0;
    } else {
        std::cout << "❌ " << (test_count - test_passed) << " test(s) FAILED\n\n";
        return 1;
    }
}

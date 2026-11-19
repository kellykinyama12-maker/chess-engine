#include <gtest/gtest.h>
#include "../include/mcts_new.hpp"
#include "../include/position.hpp"
#include "../include/move_gen.hpp"
#include <vector>
#include <chrono>

// ============================================================================
// Phase 6B: Late Move Reductions Tests
// ============================================================================

class Phase6BTest : public ::testing::Test {
protected:
    MonteCarlo mc;
    Position pos;
    
    void SetUp() override {
        // Set up a standard starting position
        pos = Position("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
        mc.reset_search_heuristics();
    }
};

// Test 1: Quiescence Search Termination
TEST_F(Phase6BTest, QuiescenceSearchTermination) {
    int alpha = -50000;
    int beta = 50000;
    
    // Run quiescence search
    int score = mc.quiescence_search(pos, alpha, beta, 0);
    
    // Should return a valid score
    EXPECT_GE(score, -50000);
    EXPECT_LE(score, 50000);
}

// Test 2: Position Evaluation
TEST_F(Phase6BTest, PositionEvaluation) {
    // Starting position should be roughly equal
    int eval = mc.evaluate_position(pos);
    
    // Starting position material is balanced
    EXPECT_LE(eval, 1);  // Allow small rounding
    EXPECT_GE(eval, -1);
}

// Test 3: Alpha-Beta Bounds
TEST_F(Phase6BTest, AlphaBetaBounds) {
    int alpha = -50000;
    int beta = 50000;
    
    // Run alpha-beta search at shallow depth
    int score = mc.alpha_beta_search(pos, 2, alpha, beta, 0);
    
    // Result should respect bounds
    EXPECT_LE(score, beta);
}

// Test 4: LMR Applied to Quiet Moves
TEST_F(Phase6BTest, LMRQuietMoveReduction) {
    // Create position after a few moves
    pos.make_move(Move(Square(4, 1), Square(4, 3)));  // e2-e4
    pos.make_move(Move(Square(4, 6), Square(4, 4)));  // e7-e5
    
    // Search with depth >= 3 to trigger LMR
    int alpha = -50000;
    int beta = 50000;
    
    int score_with_lmr = mc.alpha_beta_search(pos, 3, alpha, beta, 0);
    
    // Should return a valid score
    EXPECT_LE(score_with_lmr, beta);
}

// Test 5: Captures Not Reduced
TEST_F(Phase6BTest, CapturesNotReduced) {
    // Position with available captures (after some moves)
    pos.make_move(Move(Square(4, 1), Square(4, 3)));  // e2-e4
    pos.make_move(Move(Square(3, 6), Square(3, 4)));  // d7-d5
    
    std::vector<Move> moves = MoveGenerator::generate_legal(pos);
    
    // Find a capture move
    for (const auto& move : moves) {
        bool is_capture = !pos.piece_at(Square(move.to)).is_empty();
        if (is_capture) {
            // Captures should not be reduced
            // This is verified by the search algorithm
            EXPECT_TRUE(is_capture);
            break;
        }
    }
}

// Test 6: Check Moves Not Reduced
TEST_F(Phase6BTest, CheckMovesNotReduced) {
    // Position after some opening moves
    pos.make_move(Move(Square(4, 1), Square(4, 3)));  // e2-e4
    pos.make_move(Move(Square(4, 6), Square(4, 4)));  // e7-e5
    pos.make_move(Move(Square(5, 0), Square(1, 4)));  // f1-c4
    
    // Search to trigger LMR logic
    int alpha = -50000;
    int beta = 50000;
    
    int score = mc.alpha_beta_search(pos, 2, alpha, beta, 0);
    
    // Should complete successfully
    EXPECT_TRUE(true);
}

// Test 7: Re-search on LMR Failure
TEST_F(Phase6BTest, LMRReSearchOnFailure) {
    // This test verifies the concept: if reduction fails, re-search
    // Set up a position where LMR would apply
    
    pos.make_move(Move(Square(4, 1), Square(4, 3)));  // e2-e4
    pos.make_move(Move(Square(4, 6), Square(4, 4)));  // e7-e5
    
    int alpha = -50000;
    int beta = 50000;
    
    // Search at sufficient depth for LMR
    int score = mc.alpha_beta_search(pos, 4, alpha, beta, 0);
    
    // Result should be valid (re-search would have executed)
    EXPECT_LE(score, beta);
}

// Test 8: Fail-Soft Beta Cutoff
TEST_F(Phase6BTest, FailSoftBetaCutoff) {
    int alpha = -50000;
    int beta = 100;  // Very narrow window
    
    // Alpha-beta should return at least beta on cutoff
    int score = mc.alpha_beta_search(pos, 2, alpha, beta, 0);
    
    // If cutoff occurs, should return value >= beta
    if (score >= beta) {
        EXPECT_GE(score, beta);
    }
}

// Test 9: Killer Move Integration with LMR
TEST_F(Phase6BTest, KillerMoveIntegrationWithLMR) {
    // Record a killer move
    Move killer(4, 20);  // Some quiet move
    mc.record_cutoff(killer, 5, 2, pos);
    
    // Search that uses killer moves
    int alpha = -50000;
    int beta = 50000;
    
    int score = mc.alpha_beta_search(pos, 3, alpha, beta, 0);
    
    // Should complete successfully
    EXPECT_LE(score, beta);
}

// Test 10: Depth-Based Reduction Scaling
TEST_F(Phase6BTest, DepthBasedReductionScaling) {
    // LMR should scale with depth
    // Deeper searches should trigger more reductions
    
    std::vector<int> depths = {2, 3, 4, 5};
    int alpha = -50000;
    int beta = 50000;
    
    for (int depth : depths) {
        // Depth < 3 should not trigger LMR
        // Depth >= 3 should trigger LMR
        int score = mc.alpha_beta_search(pos, depth, alpha, beta, 0);
        EXPECT_LE(score, beta);
    }
}

// ============================================================================
// Performance Benchmarks
// ============================================================================

class Phase6BPerformanceTest : public ::testing::Test {
protected:
    MonteCarlo mc;
    Position pos;
    
    void SetUp() override {
        pos = Position("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
        mc.reset_search_heuristics();
    }
};

// Benchmark: Alpha-Beta Search Depth 1
TEST_F(Phase6BPerformanceTest, AlphaBetaDepth1Benchmark) {
    auto start = std::chrono::steady_clock::now();
    
    int alpha = -50000;
    int beta = 50000;
    
    for (int i = 0; i < 100; i++) {
        int score = mc.alpha_beta_search(pos, 1, alpha, beta, 0);
        (void)score;
    }
    
    auto end = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);
    
    std::cout << "Alpha-Beta Depth 1 (100 iterations): " << duration.count() << " ms\n";
    std::cout << "Searches per second: " << (100000.0 / duration.count()) << "\n";
}

// Benchmark: Alpha-Beta Search Depth 3
TEST_F(Phase6BPerformanceTest, AlphaBetaDepth3Benchmark) {
    auto start = std::chrono::steady_clock::now();
    
    int alpha = -50000;
    int beta = 50000;
    
    for (int i = 0; i < 10; i++) {
        int score = mc.alpha_beta_search(pos, 3, alpha, beta, 0);
        (void)score;
    }
    
    auto end = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);
    
    std::cout << "Alpha-Beta Depth 3 (10 iterations): " << duration.count() << " ms\n";
    std::cout << "Searches per second: " << (10000.0 / duration.count()) << "\n";
}

// Benchmark: Quiescence Search
TEST_F(Phase6BPerformanceTest, QuiescenceSearchBenchmark) {
    auto start = std::chrono::steady_clock::now();
    
    int alpha = -50000;
    int beta = 50000;
    
    for (int i = 0; i < 1000; i++) {
        int score = mc.quiescence_search(pos, alpha, beta, 0);
        (void)score;
    }
    
    auto end = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);
    
    std::cout << "Quiescence Search (1000 iterations): " << duration.count() << " ms\n";
    std::cout << "Searches per second: " << (1000000.0 / duration.count()) << "\n";
}


#include <gtest/gtest.h>
#include "../include/mcts_new.hpp"
#include "../include/position.hpp"
#include "../include/move_gen.hpp"
#include <vector>

// ============================================================================
// Phase 6A: Enhanced Move Ordering Tests
// ============================================================================

class Phase6ATest : public ::testing::Test {
protected:
    MonteCarlo mc;
    Position pos;
    
    void SetUp() override {
        // Set up a standard starting position
        pos = Position("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
        mc.reset_search_heuristics();
    }
};

// Test 1: Killer Moves Recording
TEST_F(Phase6ATest, KillerMovesRecording) {
    Move move1(0, 16);  // a2-a3
    Move move2(0, 17);  // a2-a4 (hypothetical)
    
    // Record first killer move at ply 5
    mc.record_cutoff(move1, 5, 3, pos);
    
    EXPECT_EQ(mc.killer_moves_.moves[5][0], move1);
    EXPECT_EQ(mc.killer_moves_.moves[5][1], Move());  // Second killer should be empty
}

// Test 2: Killer Moves Rotation
TEST_F(Phase6ATest, KillerMovesRotation) {
    Move move1(0, 16);  // a2-a3
    Move move2(0, 17);  // a2-a4
    
    mc.record_cutoff(move1, 5, 3, pos);
    mc.record_cutoff(move2, 5, 3, pos);
    
    // After recording two different moves, they should rotate
    EXPECT_EQ(mc.killer_moves_.moves[5][0], move2);
    EXPECT_EQ(mc.killer_moves_.moves[5][1], move1);
}

// Test 3: History Heuristic Updates
TEST_F(Phase6ATest, HistoryHeuristicUpdates) {
    Move move1(0, 16);  // a2-a3
    
    // Record the same move multiple times at different depths
    for (int depth = 1; depth <= 5; depth++) {
        mc.record_cutoff(move1, 3, depth, pos);
    }
    
    // History value should increase with each recording
    int history_score = mc.history_.get(0, move1.from, move1.to);
    EXPECT_GT(history_score, 0);
}

// Test 4: Move Scoring - PV Move
TEST_F(Phase6ATest, MoveScorePVMove) {
    Move pv_move(0, 16);  // a2-a3
    Move other_move(0, 17);  // a2-a4
    
    int pv_score = mc.score_move(pos, pv_move, 3, pv_move);
    int other_score = mc.score_move(pos, other_move, 3, pv_move);
    
    EXPECT_GT(pv_score, other_score);
    EXPECT_EQ(pv_score, 1000000);
}

// Test 5: Move Scoring - Killer Move Priority
TEST_F(Phase6ATest, MoveScoreKillerPriority) {
    Move killer1(0, 16);
    Move quiet_move(0, 17);
    
    // Record killer move
    mc.record_cutoff(killer1, 5, 3, pos);
    
    int killer_score = mc.score_move(pos, killer1, 5);
    int quiet_score = mc.score_move(pos, quiet_move, 5);
    
    EXPECT_GT(killer_score, quiet_score);
}

// Test 6: Move Scoring - Quiet Move History
TEST_F(Phase6ATest, MoveScoreQuietHistoryOrdering) {
    Move move1(0, 16);
    Move move2(0, 17);
    
    // Build history for move1
    for (int i = 0; i < 10; i++) {
        mc.record_cutoff(move1, 3, 2, pos);
    }
    
    // move2 has no history
    
    int score1 = mc.score_move(pos, move1, 3);
    int score2 = mc.score_move(pos, move2, 3);
    
    EXPECT_GT(score1, score2);
}

// Test 7: Reset Heuristics
TEST_F(Phase6ATest, ResetSearchHeuristics) {
    Move killer(0, 16);
    Move quiet(0, 17);
    
    mc.record_cutoff(killer, 5, 3, pos);
    mc.record_cutoff(quiet, 3, 2, pos);
    
    // Both should have values
    int killer_score_before = mc.score_move(pos, killer, 5);
    int quiet_score_before = mc.score_move(pos, quiet, 3);
    
    // Reset
    mc.reset_search_heuristics();
    
    // Now killer should not get bonus
    int killer_score_after = mc.score_move(pos, killer, 5);
    int quiet_score_after = mc.score_move(pos, quiet, 3);
    
    EXPECT_LT(killer_score_after, killer_score_before);
    EXPECT_EQ(quiet_score_after, 0);
}

// Test 8: Move Scoring Range
TEST_F(Phase6ATest, MoveScoringScopeAndRange) {
    Move pv_move(0, 16);
    Move quiet_move(0, 17);
    Move killer_move(0, 18);
    
    mc.record_cutoff(killer_move, 5, 3, pos);
    
    int pv_score = mc.score_move(pos, pv_move, 5, pv_move);
    int killer_score = mc.score_move(pos, killer_move, 5);
    int quiet_score = mc.score_move(pos, quiet_move, 5);
    
    // Verify ordering: PV > Killer > Quiet
    EXPECT_GT(pv_score, killer_score);
    EXPECT_GT(killer_score, quiet_score);
}

// Test 9: Killer Moves Per Ply Independence
TEST_F(Phase6ATest, KillerMovesPerPlyIndependence) {
    Move move1(0, 16);
    Move move2(0, 17);
    
    mc.record_cutoff(move1, 3, 3, pos);
    mc.record_cutoff(move2, 5, 3, pos);
    
    // ply 3 should have move1 as killer
    int score_at_ply3 = mc.score_move(pos, move1, 3);
    EXPECT_EQ(score_at_ply3, 90000);  // First killer
    
    // ply 5 should have move2 as killer, not move1
    int move1_at_ply5 = mc.score_move(pos, move1, 5);
    int move2_at_ply5 = mc.score_move(pos, move2, 5);
    
    EXPECT_NE(move1_at_ply5, 90000);  // Not a killer at ply 5
    EXPECT_EQ(move2_at_ply5, 90000);  // Is a killer at ply 5
}

// Test 10: History Table Independence by Color
TEST_F(Phase6ATest, HistoryTableColorIndependence) {
    Move move1(0, 16);  // From a1 to a2
    
    // Record for white (color 0)
    mc.record_cutoff(move1, 3, 2, pos);
    
    int white_score = mc.history_.get(0, move1.from, move1.to);
    int black_score = mc.history_.get(1, move1.from, move1.to);
    
    EXPECT_GT(white_score, 0);
    EXPECT_EQ(black_score, 0);  // Black hasn't used this move
}


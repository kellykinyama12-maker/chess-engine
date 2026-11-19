#include <gtest/gtest.h>
#include "mcts_new.hpp"
#include "position.hpp"
#include "zobrist.hpp"
#include <cstdint>

// ============================================================================
// PHASE 6D: Transposition Table Unit Tests
// ============================================================================

class TranspositionTableTest : public ::testing::Test {
protected:
    TranspositionTable tt{TranspositionTable::DEFAULT_SIZE};
    
    void SetUp() override {
        tt.clear();
    }
};

// Test 1: Probe empty table returns nullptr
TEST_F(TranspositionTableTest, ProbeEmptyTableReturnsMissing) {
    TranspositionEntry* entry = tt.probe(12345ULL, 10);
    EXPECT_EQ(entry, nullptr);
    EXPECT_EQ(tt.get_probes(), 1U);
    EXPECT_EQ(tt.get_hits(), 0U);
}

// Test 2: Store and retrieve exact value
TEST_F(TranspositionTableTest, StoreAndRetrieveExactValue) {
    uint64_t key = 0xABCD1234EFGH5678ULL;
    int depth = 15;
    double value = 0.65;
    
    tt.store(key, depth, value, NodeType::pv);
    
    TranspositionEntry* entry = tt.probe(key, depth);
    ASSERT_NE(entry, nullptr);
    EXPECT_EQ(entry->key, key);
    EXPECT_EQ(entry->depth, depth);
    EXPECT_DOUBLE_EQ(entry->value, value);
    EXPECT_EQ(entry->type, NodeType::pv);
    EXPECT_EQ(tt.get_hits(), 1U);
}

// Test 3: Probe with insufficient depth returns nullptr
TEST_F(TranspositionTableTest, ProbeWithInsufficientDepthReturnsMissing) {
    uint64_t key = 0x1111111111111111ULL;
    
    tt.store(key, 10, 0.5, NodeType::pv);
    
    // Probe with shallower depth
    TranspositionEntry* entry = tt.probe(key, 5);
    EXPECT_EQ(entry, nullptr);
    EXPECT_EQ(tt.get_probes(), 1U);
    EXPECT_EQ(tt.get_hits(), 0U);
}

// Test 4: Probe with sufficient depth returns entry
TEST_F(TranspositionTableTest, ProbeWithSufficientDepthReturnsEntry) {
    uint64_t key = 0x2222222222222222ULL;
    
    tt.store(key, 10, 0.5, NodeType::pv);
    
    // Probe with same or deeper depth
    TranspositionEntry* entry = tt.probe(key, 10);
    ASSERT_NE(entry, nullptr);
    EXPECT_EQ(tt.get_hits(), 1U);
    
    entry = tt.probe(key, 12);
    ASSERT_NE(entry, nullptr);
    EXPECT_EQ(tt.get_hits(), 2U);
}

// Test 5: Upper bound type (NodeType::all) stored correctly
TEST_F(TranspositionTableTest, StoreUpperBoundType) {
    uint64_t key = 0x3333333333333333ULL;
    double alpha = 0.4;
    
    tt.store(key, 12, alpha, NodeType::all);
    
    TranspositionEntry* entry = tt.probe(key, 12);
    ASSERT_NE(entry, nullptr);
    EXPECT_EQ(entry->type, NodeType::all);
    EXPECT_DOUBLE_EQ(entry->value, alpha);
}

// Test 6: Lower bound type (NodeType::cut) stored correctly
TEST_F(TranspositionTableTest, StoreLowerBoundType) {
    uint64_t key = 0x4444444444444444ULL;
    double beta = 0.6;
    
    tt.store(key, 12, beta, NodeType::cut);
    
    TranspositionEntry* entry = tt.probe(key, 12);
    ASSERT_NE(entry, nullptr);
    EXPECT_EQ(entry->type, NodeType::cut);
    EXPECT_DOUBLE_EQ(entry->value, beta);
}

// Test 7: can_use_entry for exact (pv) type
TEST_F(TranspositionTableTest, CanUseExactValueEntry) {
    TranspositionEntry entry(0x5555555555555555ULL, 12, 0.55, NodeType::pv, 0);
    
    // Exact values can always be used (regardless of alpha/beta)
    EXPECT_TRUE(tt.can_use_entry(&entry, 12, 0.3, 0.7));
    EXPECT_TRUE(tt.can_use_entry(&entry, 10, 0.3, 0.7));
}

// Test 8: can_use_entry for upper bound (all) type
TEST_F(TranspositionTableTest, CanUseUpperBoundEntry) {
    // Upper bound: value = alpha (fail-low)
    TranspositionEntry entry(0x6666666666666666ULL, 12, 0.4, NodeType::all, 0);
    
    // Can use if value <= alpha
    EXPECT_TRUE(tt.can_use_entry(&entry, 12, 0.5, 0.7));  // 0.4 <= 0.5
    EXPECT_FALSE(tt.can_use_entry(&entry, 12, 0.3, 0.7)); // 0.4 > 0.3
}

// Test 9: can_use_entry for lower bound (cut) type
TEST_F(TranspositionTableTest, CanUseLowerBoundEntry) {
    // Lower bound: value = beta (fail-high)
    TranspositionEntry entry(0x7777777777777777ULL, 12, 0.6, NodeType::cut, 0);
    
    // Can use if value >= beta
    EXPECT_TRUE(tt.can_use_entry(&entry, 12, 0.3, 0.5));   // 0.6 >= 0.5
    EXPECT_FALSE(tt.can_use_entry(&entry, 12, 0.3, 0.7));  // 0.6 < 0.7
}

// Test 10: can_use_entry returns false if depth too shallow
TEST_F(TranspositionTableTest, CanUseEntryDepthCheck) {
    TranspositionEntry entry(0x8888888888888888ULL, 10, 0.55, NodeType::pv, 0);
    
    // Depth requirement: entry.depth >= requested depth
    EXPECT_TRUE(tt.can_use_entry(&entry, 8, 0.3, 0.7));   // 10 >= 8: OK
    EXPECT_FALSE(tt.can_use_entry(&entry, 12, 0.3, 0.7)); // 10 < 12: Reject
}

// Test 11: can_use_entry returns false for nullptr
TEST_F(TranspositionTableTest, CanUseEntryNullptrReturnsFalse) {
    EXPECT_FALSE(tt.can_use_entry(nullptr, 10, 0.3, 0.7));
}

// Test 12: Multiple entries in different buckets
TEST_F(TranspositionTableTest, MultipleEntriesInDifferentBuckets) {
    std::vector<uint64_t> keys = {
        0x1111111111111111ULL,
        0x2222222222222222ULL,
        0x3333333333333333ULL,
        0x4444444444444444ULL,
        0x5555555555555555ULL
    };
    
    for (size_t i = 0; i < keys.size(); ++i) {
        tt.store(keys[i], static_cast<int>(10 + i), 0.4 + 0.1 * i, NodeType::pv);
    }
    
    // Verify all entries can be retrieved
    for (size_t i = 0; i < keys.size(); ++i) {
        TranspositionEntry* entry = tt.probe(keys[i], static_cast<int>(10 + i));
        ASSERT_NE(entry, nullptr) << "Failed to retrieve key " << i;
        EXPECT_EQ(entry->key, keys[i]);
        EXPECT_DOUBLE_EQ(entry->value, 0.4 + 0.1 * i);
    }
    
    EXPECT_EQ(tt.get_stores(), 5U);
    EXPECT_EQ(tt.get_hits(), 5U);
}

// Test 13: Deeper depth replaces shallower entry
TEST_F(TranspositionTableTest, DeeperDepthReplacesShallower) {
    uint64_t key = 0x9999999999999999ULL;
    
    // Store shallow
    tt.store(key, 8, 0.5, NodeType::pv);
    TranspositionEntry* entry1 = tt.probe(key, 8);
    ASSERT_NE(entry1, nullptr);
    EXPECT_EQ(entry1->depth, 8);
    
    // Store deeper (should replace)
    tt.store(key, 12, 0.55, NodeType::pv);
    TranspositionEntry* entry2 = tt.probe(key, 12);
    ASSERT_NE(entry2, nullptr);
    EXPECT_EQ(entry2->depth, 12);
    EXPECT_DOUBLE_EQ(entry2->value, 0.55);
    
    // Shallow probe should miss (depth too shallow)
    entry1 = tt.probe(key, 8);
    EXPECT_EQ(entry1, nullptr);
}

// Test 14: Statistics tracking
TEST_F(TranspositionTableTest, StatisticsTracking) {
    uint64_t key1 = 0xAAAAAAAAAAAAAAAAULL;
    uint64_t key2 = 0xBBBBBBBBBBBBBBBBULL;
    
    // Store two entries
    tt.store(key1, 10, 0.5, NodeType::pv);
    tt.store(key2, 12, 0.6, NodeType::all);
    
    EXPECT_EQ(tt.get_stores(), 2U);
    
    // Probe: 1 hit, 1 miss
    tt.probe(key1, 10);  // Hit
    tt.probe(key2, 8);   // Miss (depth too shallow)
    tt.probe(0xCCCCCCCCCCCCCCCCULL, 10);  // Miss (not stored)
    
    EXPECT_EQ(tt.get_probes(), 3U);
    EXPECT_EQ(tt.get_hits(), 1U);
    EXPECT_DOUBLE_EQ(tt.get_hit_rate(), 100.0 / 3.0);
}

// Test 15: Clear resets all statistics
TEST_F(TranspositionTableTest, ClearResetsStatistics) {
    uint64_t key = 0xDDDDDDDDDDDDDDDDULL;
    
    tt.store(key, 10, 0.5, NodeType::pv);
    tt.probe(key, 10);
    
    EXPECT_GT(tt.get_stores(), 0U);
    EXPECT_GT(tt.get_probes(), 0U);
    
    tt.clear();
    
    EXPECT_EQ(tt.get_stores(), 0U);
    EXPECT_EQ(tt.get_probes(), 0U);
    EXPECT_EQ(tt.get_hits(), 0U);
    
    // Should not find cleared entry
    TranspositionEntry* entry = tt.probe(key, 10);
    EXPECT_EQ(entry, nullptr);
}

// Test 16: Hash collision handling (4-way associative)
TEST_F(TranspositionTableTest, HashCollisionHandling) {
    // Create a small TT for predictable collision
    TranspositionTable small_tt(16);  // Very small to force collisions
    
    // These will likely hash to same bucket
    std::vector<uint64_t> keys;
    for (uint64_t i = 0; i < 8; ++i) {
        keys.push_back(i * 16 + 7);  // Likely to collide with size 16
    }
    
    // Store multiple entries
    for (size_t i = 0; i < keys.size(); ++i) {
        small_tt.store(keys[i], 10 + static_cast<int>(i), 0.4 + 0.05 * i, NodeType::pv);
    }
    
    // Verify retrievable entries (up to 4-way capacity)
    int retrieved = 0;
    for (size_t i = 0; i < keys.size(); ++i) {
        TranspositionEntry* entry = small_tt.probe(keys[i], 10 + static_cast<int>(i));
        if (entry != nullptr) {
            retrieved++;
            EXPECT_EQ(entry->key, keys[i]);
        }
    }
    
    // At least some should be retrievable with 4-way associativity
    EXPECT_GT(retrieved, 0);
}

// Test 17: Timestamp-based aging for replacement
TEST_F(TranspositionTableTest, TimestampBasedReplacement) {
    TranspositionTable small_tt(16);
    uint64_t key1 = 100;
    uint64_t key2 = 116;  // Likely same bucket with size 16
    
    // Store first entry
    small_tt.store(key1, 10, 0.5, NodeType::pv);
    
    // Store more entries to age first one
    for (int i = 0; i < 20; ++i) {
        small_tt.store(100000ULL + i, 10, 0.5, NodeType::pv);
    }
    
    // Store second entry (may replace first if same bucket and no space)
    small_tt.store(key2, 10, 0.6, NodeType::all);
    
    // This test verifies no crash and reasonable behavior
    TranspositionEntry* entry1 = small_tt.probe(key1, 10);
    TranspositionEntry* entry2 = small_tt.probe(key2, 10);
    
    // At least one should be present (not both necessarily due to replacement)
    // This validates the replacement mechanism doesn't crash
    EXPECT_TRUE(entry1 != nullptr || entry2 != nullptr);
}

// Test 18: Exact value not affected by alpha-beta
TEST_F(TranspositionTableTest, ExactValueNotAffectedByAlphaBeta) {
    TranspositionEntry entry(0xEEEEEEEEEEEEEEEEULL, 15, 0.55, NodeType::pv, 0);
    
    // Exact values can always be used
    EXPECT_TRUE(tt.can_use_entry(&entry, 15, 0.1, 0.9));
    EXPECT_TRUE(tt.can_use_entry(&entry, 15, 0.5, 0.6));
    EXPECT_TRUE(tt.can_use_entry(&entry, 15, 0.0, 1.0));
}

// Test 19: Hit rate calculation
TEST_F(TranspositionTableTest, HitRateCalculation) {
    tt.clear();
    
    uint64_t key = 0xFFFFFFFFFFFFFFFFULL;
    tt.store(key, 10, 0.5, NodeType::pv);
    
    // 2 hits, 1 miss
    tt.probe(key, 10);  // Hit
    tt.probe(key, 10);  // Hit
    tt.probe(key, 15);  // Miss (depth too shallow)
    
    EXPECT_EQ(tt.get_probes(), 3U);
    EXPECT_EQ(tt.get_hits(), 2U);
    double hit_rate = tt.get_hit_rate();
    EXPECT_DOUBLE_EQ(hit_rate, 200.0 / 3.0);  // ~66.67%
}

// Test 20: Different NodeTypes stored and retrieved correctly
TEST_F(TranspositionTableTest, AllNodeTypesStoredAndRetrieved) {
    std::vector<NodeType> types = {NodeType::pv, NodeType::all, NodeType::cut};
    std::vector<uint64_t> keys = {0x1ULL, 0x2ULL, 0x3ULL};
    
    // Store all types
    for (size_t i = 0; i < types.size(); ++i) {
        tt.store(keys[i], 10, 0.5 + 0.05 * i, types[i]);
    }
    
    // Retrieve and verify
    for (size_t i = 0; i < types.size(); ++i) {
        TranspositionEntry* entry = tt.probe(keys[i], 10);
        ASSERT_NE(entry, nullptr);
        EXPECT_EQ(entry->type, types[i]);
    }
}

// Test 21: Edge case - value = 0.0
TEST_F(TranspositionTableTest, StoreZeroValue) {
    uint64_t key = 0x1234567890ABCDEFULL;
    tt.store(key, 10, 0.0, NodeType::pv);
    
    TranspositionEntry* entry = tt.probe(key, 10);
    ASSERT_NE(entry, nullptr);
    EXPECT_DOUBLE_EQ(entry->value, 0.0);
}

// Test 22: Edge case - value = 1.0
TEST_F(TranspositionTableTest, StoreOneValue) {
    uint64_t key = 0xFEDCBA0987654321ULL;
    tt.store(key, 10, 1.0, NodeType::pv);
    
    TranspositionEntry* entry = tt.probe(key, 10);
    ASSERT_NE(entry, nullptr);
    EXPECT_DOUBLE_EQ(entry->value, 1.0);
}

// Test 23: Large depth values
TEST_F(TranspositionTableTest, LargeDepthValues) {
    uint64_t key = 0xAAAABBBBCCCCDDDDULL;
    int large_depth = 100;
    
    tt.store(key, large_depth, 0.5, NodeType::pv);
    
    TranspositionEntry* entry = tt.probe(key, large_depth);
    ASSERT_NE(entry, nullptr);
    EXPECT_EQ(entry->depth, large_depth);
}

// Test 24: Probe consistency across multiple calls
TEST_F(TranspositionTableTest, ProbeConsistency) {
    uint64_t key = 0x1111AAAA2222BBBBULL;
    double value = 0.735;
    
    tt.store(key, 12, value, NodeType::all);
    
    // Multiple probes should return same value
    for (int i = 0; i < 5; ++i) {
        TranspositionEntry* entry = tt.probe(key, 12);
        ASSERT_NE(entry, nullptr);
        EXPECT_DOUBLE_EQ(entry->value, value);
        EXPECT_EQ(entry->type, NodeType::all);
    }
}

// Test 25: Small table allocation
TEST_F(TranspositionTableTest, SmallTableAllocation) {
    TranspositionTable tiny_tt(256);  // Very small table
    uint64_t key = 0xDEADBEEFCAFEBABEULL;
    
    tiny_tt.store(key, 8, 0.5, NodeType::pv);
    
    TranspositionEntry* entry = tiny_tt.probe(key, 8);
    ASSERT_NE(entry, nullptr);
    EXPECT_EQ(entry->key, key);
}

int main(int argc, char** argv) {
    ::testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}

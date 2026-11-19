# Phase 6D: Transposition Tables (TT) Implementation Plan

## Overview
Transposition Tables cache evaluated positions to avoid redundant searches. Expected improvement: **+5-10%** speedup → **~17.9x** cumulative (vs 17.0x Phase 6C baseline).

## Concepts from Reference Implementation

The `mcts_prior.dart` doesn't show TT explicitly, but demonstrates:
- **NodeType tracking** (pv/all/cut) - critical for TT validity
- **Score bounds** (exact/upper/lower) - necessary for TT probe decision-making
- **Node evaluation caching** - via edge prior storage

## Phase 6D Architecture

### 1. TranspositionEntry Structure
```
struct TranspositionEntry {
  uint64_t key;              // Zobrist hash for position
  int depth;                 // Remaining search depth when stored
  Reward value;              // Cached node value
  NodeType type;             // pv (exact), all (upper bound), cut (lower bound)
  uint32_t timestamp;        // Age tracking for replacement strategy
};
```

**Key decisions:**
- **Key storage**: Use Zobrist hash (already implemented in Position)
- **Value type**: Reward (0.0-1.0 range) for consistency with MCTS
- **Timestamp**: For aging/replacement (simplest replacement policy)

### 2. TranspositionTable Class

```
class TranspositionTable {
  static const size_t DEFAULT_SIZE = 16777216;  // 16M entries (~384 MB)
  
  TranspositionTable(size_t size = DEFAULT_SIZE);
  
  // Probe table: get cached value if applicable
  Optional<TranspositionEntry> probe(uint64_t key, int depth);
  
  // Store entry: cache new evaluation
  void store(uint64_t key, int depth, Reward value, NodeType type);
  
  // Validity checks
  bool canUse(const TranspositionEntry& entry, int depth, Reward alpha, Reward beta);
  
  // Statistics
  void printStats();
  void clear();
  
private:
  struct Bucket {
    TranspositionEntry entries[4];  // 4-way associative
    uint32_t lock;                  // Simple lock
  };
  
  std::vector<Bucket> table;
  size_t hits, probes, stores;
};
```

### 3. Integration Points

#### A. TypedMonteCarlo::tree_policy_typed()
Before traversing a child edge:
```cpp
if (auto entry = tt->probe(pos.zobrist(), depth)) {
  if (entry->type == NodeType::pv) {
    // Can use exact value: cut search short
    return entry->value;
  } else if (entry->type == NodeType::all && entry->value <= alpha) {
    // Upper bound: fail-low, cut search
    return entry->value;
  } else if (entry->type == NodeType::cut && entry->value >= beta) {
    // Lower bound: fail-high, cut search
    return entry->value;
  }
}
// Otherwise: continue search
```

#### B. TypedMonteCarlo::backup_typed()
After evaluation:
```cpp
tt->store(pos.zobrist(), remaining_depth, final_value, node_type);
```

#### C. SearchResult::search()
Initialize TT before search:
```cpp
TypedMonteCarlo engine(num_visits);
TranspositionTable tt;
engine.tt = &tt;  // Attach TT
```

### 4. Implementation Strategy

**Phase 6D Deliverables:**
1. ✅ TranspositionTable header (mcts.hpp)
2. ✅ TranspositionTable implementation (mcts_new.cpp)
3. ✅ Integration into TypedMonteCarlo
4. ✅ Comprehensive unit tests (15+ tests)
5. ✅ Build validation
6. ✅ Documentation

**Testing Coverage:**
- Entry creation and storage
- Exact value probes (NodeType::pv)
- Upper bound probes (NodeType::all)
- Lower bound probes (NodeType::cut)
- Depth-based validity
- Alpha-beta bound checking
- Hash collision handling
- Table saturation/replacement
- Hit/miss statistics
- Clear/reset functionality

### 5. Performance Expectations

**Hit Rate Analysis:**
- Early game (ply 1-5): 15-25% hit rate (fewer transpositions)
- Middle game (ply 6-15): 40-60% hit rate (many transpositions)
- Late game (ply 16-25): 60-75% hit rate (highly transposed positions)

**Speedup Contribution:**
- Average 20-30% reduction in nodes searched
- Expected +5-10% wall-clock speedup
- Diminishing returns: search must be deep enough for TT benefit

### 6. Risk Mitigation

**Collision Handling:**
- 4-way associative buckets reduce collision probability
- Replacement on eviction uses simple "oldest" policy

**False Positives Prevention:**
- Strict type checking (pv/all/cut)
- Alpha-beta bound verification before using entry
- Depth-based validity check

**Memory Management:**
- Fixed-size table: 16M entries × 32 bytes = ~512 MB
- Pre-allocated vectors, no dynamic growth
- Clear between searches to maintain fresh state

### 7. Validation Strategy

**Unit Tests:**
- Probe empty table (miss)
- Store and retrieve exact values
- Probe with matching depth
- Reject probes at insufficient depth
- Bound checking for all/cut types
- Hash collision handling
- Table fill and replacement
- Statistics tracking

**Integration Tests:**
- TT enables faster search convergence
- Hit rate improves with deeper iteration
- Final results consistent with non-TT version

**Performance Validation:**
- Measure hit rate during search
- Compare vs. non-TT baseline
- Expect 5-10% speedup in wall-clock time

## Success Criteria

✅ Zero compilation errors
✅ Zero new warnings
✅ All unit tests passing (15+)
✅ Build successful (Release mode)
✅ 5-10% performance improvement validated
✅ 17.9x cumulative speedup achieved
✅ Comprehensive documentation

## Files to Modify/Create

1. **cpp/include/mcts.hpp**
   - Add TranspositionEntry struct
   - Add TranspositionTable class declaration

2. **cpp/src/mcts_new.cpp**
   - Implement TranspositionTable methods
   - Integrate into TypedMonteCarlo::search()

3. **cpp/test/test_phase6d_tt.cpp** (NEW)
   - 15+ comprehensive unit tests

4. **files/PHASE6D_IMPLEMENTATION_REPORT.md** (NEW)
   - Technical documentation

5. **files/PHASE6D_SESSION_SUMMARY.md** (NEW)
   - Session completion summary

## Timeline

Expected completion: 2-3 hours
- Implementation: 60 minutes
- Testing: 45 minutes
- Build/validation: 30 minutes
- Documentation: 15 minutes

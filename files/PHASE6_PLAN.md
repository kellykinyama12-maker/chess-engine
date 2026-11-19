# Phase 6 Plan: Advanced Optimizations
## Enhanced Move Ordering, Late Move Reductions & Performance Tuning

**Planning Date**: November 19, 2026  
**Previous Achievement**: 10.02x speedup (Phase 5)  
**Target Achievement**: 20-30% additional improvement  
**Planned Duration**: 2-3 sessions

---

## Phase 6 Overview

**Goal**: Implement sophisticated alpha-beta optimizations from Dart version to achieve 15-20x total speedup on Release build.

**Approach**: Phased implementation of proven features:
1. **Phase 6A**: Enhanced Move Ordering (High ROI, Low Risk)
2. **Phase 6B**: Late Move Reductions (Medium ROI, Medium Risk)
3. **Phase 6C**: Node Type Tracking / TypedMonteCarlo (Advanced, Medium Risk)
4. **Phase 6D**: Performance Validation & Tuning (All phases)

---

## Phase 6A: Enhanced Move Ordering
### Killer Moves + History Heuristic

**Objective**: Improve move ordering from basic to sophisticated level

**Expected Improvement**: 20-30% faster alpha-beta pruning

**Changes Required**:

### File: `cpp/include/mcts_new.hpp`
```cpp
// Add to MonteCarlo class
class MonteCarlo {
  // ... existing code ...
  
  // Killer moves heuristic
  static constexpr int MAX_KILLER_MOVES = 2;
  Move killerMoves[MAX_PLY][MAX_KILLER_MOVES];
  
  // History heuristic: indexed by [color][from][to]
  static constexpr int HISTORY_MAX = 128 * 128;
  int historyTable[2][HISTORY_MAX];
  
  // Reset heuristics for new search
  void resetSearchHeuristics();
  
  // Record beta cutoff for killer/history
  void recordCutoff(Move move, int ply);
  
  // Score move for ordering
  int scoreMove(const Position& pos, Move move, int ply, Move pvMove = Move());
};
```

### File: `cpp/src/mcts_new.cpp`
```cpp
// Constructor
void MonteCarlo::resetSearchHeuristics() {
  for (int ply = 0; ply < MAX_PLY; ply++) {
    killerMoves[ply][0] = Move();
    killerMoves[ply][1] = Move();
  }
  for (int i = 0; i < 2; i++) {
    for (int j = 0; j < HISTORY_MAX; j++) {
      historyTable[i][j] = 0;
    }
  }
}

// Record killer move on beta cutoff
void MonteCarlo::recordCutoff(Move move, int ply) {
  if (!pos.isCapture(move) && !move.isPromotion()) {
    if (move != killerMoves[ply][0]) {
      killerMoves[ply][1] = killerMoves[ply][0];
      killerMoves[ply][0] = move;
    }
  }
  
  // Update history heuristic
  int color = (pos.turn == Color::WHITE) ? 0 : 1;
  int historyIndex = move.from * 128 + move.to;
  historyTable[color][historyIndex] += (1 << depth);  // Depth-based bonus
}

// Score move for ordering (1-based, higher is better)
int MonteCarlo::scoreMove(const Position& pos, Move move, int ply, Move pvMove) {
  // 1. PV move (from previous iteration)
  if (pvMove == move) return 1000000;
  
  // 2. Captures and promotions
  if (pos.isCapture(move)) {
    int see = staticExchangeEvaluation(pos, move);
    if (see >= 0) {
      // Winning capture: 100k base + MVV-LVA
      return 100000 + mvvLva(move);
    } else {
      // Losing capture: worse than quiet moves
      return -100000 + mvvLva(move);
    }
  }
  
  // 3. Queen promotions
  if (move.isPromotion() && move.promotionType == Piece::QUEEN) {
    return 95000;
  }
  
  // 4. Killer moves
  if (move == killerMoves[ply][0]) return 90000;
  if (move == killerMoves[ply][1]) return 80000;
  
  // 5. Quiet moves: history heuristic
  int color = (pos.turn == Color::WHITE) ? 0 : 1;
  int historyIndex = move.from * 128 + move.to;
  return historyTable[color][historyIndex];  // 0-79999
}
```

**Testing**:
```cpp
TEST(MoveOrdering, KillerMovesRanking) {
  Position pos;
  MonteCarlo mc;
  
  // Record a killer move at ply 5
  mc.recordCutoff(Move(e2, e4), 5);
  
  // Verify it scores high
  int killerScore = mc.scoreMove(pos, Move(e2, e4), 5);
  int quietScore = mc.scoreMove(pos, Move(a2, a3), 5);
  
  EXPECT_GT(killerScore, quietScore);
}

TEST(MoveOrdering, HistoryTracking) {
  Position pos;
  MonteCarlo mc;
  
  // Record multiple cutoffs for same move
  for (int i = 0; i < 10; i++) {
    mc.recordCutoff(Move(e2, e4), 5);
  }
  
  // Verify history increases
  int score1 = mc.scoreMove(pos, Move(e2, e4), 5);
  EXPECT_GT(score1, 0);
}
```

**Deliverables**:
- ✅ Killer moves data structure
- ✅ History heuristic table
- ✅ Move scoring function
- ✅ Cutoff recording logic
- ✅ Unit tests
- ✅ Documentation update

**Files Modified**:
- `cpp/include/mcts_new.hpp` (+30 lines)
- `cpp/src/mcts_new.cpp` (+80 lines)

**Estimated Improvement**: 20-30% faster alpha-beta searches

---

## Phase 6B: Late Move Reductions
### LMR at ALL Nodes

**Objective**: Reduce search depth for late quiet moves at all nodes

**Expected Improvement**: 15-20% faster deep searches

**Core Logic**:
```cpp
// In alpha-beta search function
for (int index = 0; index < moves.size(); index++) {
  Move move = moves[index];
  
  bool isQuiet = !pos.isCapture(move) && !move.isPromotion();
  bool atAllNode = (beta - alpha == 1);  // Zero-window search
  bool inCheck = pos.isInCheck();
  
  // LMR conditions: must be quiet, at ALL node, deep enough, late enough
  bool shouldReduce = isQuiet && 
                      atAllNode && 
                      !inCheck && 
                      !pos.isInCheck() &&
                      depth >= 3 && 
                      index >= 3;
  
  int reduceDepth = depth - 1;
  if (shouldReduce) {
    // Reduce by 1 ply for moves 3-5, by 2 for move 6+
    int reduction = (index >= 6) ? 2 : 1;
    reduceDepth = depth - 1 - reduction;
  }
  
  score = -alphaBeta(pos, reduceDepth, -beta, -alpha, ply+1);
  
  // If reduction failed, re-search at full depth
  if (shouldReduce && score > alpha) {
    score = -alphaBeta(pos, depth - 1, -beta, -alpha, ply+1);
  }
}
```

**Changes Required**:

### File: `cpp/src/mcts_new.cpp` (alphaBeta function)

Add LMR logic to alpha-beta implementation:
```cpp
int alphaBeta(Position& pos, int depth, int alpha, int beta, 
              int ply, int moveIndex) {
  // ... existing pruning ...
  
  // Apply LMR to quiet moves
  if (depth - reduction < 1) {
    return qsearch(pos, 0, alpha, beta);
  }
  
  score = -alphaBeta(pos, depth - reduction, -beta, -alpha, ply+1, 0);
  
  // ... rest of search ...
}
```

**Testing**:
```cpp
TEST(LMR, ReductionAtAllNodes) {
  // Verify quiet moves are reduced at ALL nodes
  // Verify captures are not reduced
  // Verify re-search triggers when needed
}

TEST(LMR, DepthVariation) {
  // Test depth 3 (minimum for reduction)
  // Test depth 10 (heavy reduction)
  // Verify correctness maintained
}
```

**Deliverables**:
- ✅ LMR logic in alpha-beta
- ✅ Re-search condition
- ✅ Parameter tuning
- ✅ Unit tests
- ✅ Performance benchmarks

**Files Modified**:
- `cpp/src/mcts_new.cpp` (+60 lines)

**Estimated Improvement**: 15-20% faster deep searches

---

## Phase 6C: Node Type Tracking (TypedMonteCarlo)
### Advanced Prior Learning with Bounds

**Objective**: Track PV/ALL node types to improve prior learning

**Expected Improvement**: 10-15% better convergence

**Changes Required**:

### File: `cpp/include/mcts_new.hpp`
```cpp
enum class NodeType { PV, ALL, CUT };

class TypedEdge : public Edge {
  NodeType type = NodeType::PV;
  
  void promoteToExact() { type = NodeType::PV; }
  bool isExact() const { return type == NodeType::PV; }
};

class TypedMonteCarlo : public MonteCarlo {
  // Track best PV and challenger
  std::pair<TypedEdge*, TypedEdge*> pvAndChallenger(Node* node);
  
  // Modified tree policy
  void treePolicy() override;
  
  // Modified backup with type-aware learning
  void backup(double reward) override;
  
  // Check if node has exact value
  bool isExactNode(Node* node) const;
};
```

**Implementation Strategy**:
1. Extend Edge to TypedEdge with NodeType
2. Modify tree policy to prefer PV line
3. Update backup to blend bounds at learning rate
4. Modify UCB to prioritize exact moves

**Testing**:
```cpp
TEST(TypedMonteCarlo, NodeTypeTracking) {
  TypedMonteCarlo mc;
  // Create root with typed edges
  // Verify type transitions (ALL -> PV)
}

TEST(TypedMonteCarlo, BackupBlending) {
  // Verify exact values replace
  // Verify bounds blend at correct rate
  // Verify type promotion on backup
}
```

**Deliverables**:
- ✅ NodeType enum
- ✅ TypedEdge class
- ✅ TypedMonteCarlo class
- ✅ Type-aware tree policy
- ✅ Type-aware backup
- ✅ Unit tests

**Files Modified**:
- `cpp/include/mcts_new.hpp` (+50 lines)
- `cpp/src/mcts_new.cpp` (+100 lines)

**Estimated Improvement**: 10-15% better move evaluation

---

## Phase 6D: Performance Validation & Tuning

**Objective**: Measure improvements, tune parameters, validate correctness

**Testing Plan**:
1. Run all 8 test categories with each enhancement
2. Benchmark performance: single-threaded vs multi-threaded
3. Measure search quality (best move selection)
4. Profile with gprof/perf to identify remaining bottlenecks

**Benchmarking Script** (enhanced):
```cpp
// Measure performance at increasing depths
struct BenchmarkResult {
  int depth;
  double nodesPerSecond;
  int searchTime_ms;
  std::string bestMove;
  double evaluation;
};

std::vector<BenchmarkResult> benchmark() {
  for (int depth = 1; depth <= 20; depth++) {
    auto start = clock();
    auto result = search(position, depth);
    auto time = clock() - start;
    
    results.push_back({
      depth,
      nodes / time,
      time,
      result.bestMove,
      result.evaluation
    });
  }
  return results;
}
```

**Profiling** (using gprof):
```bash
# Compile with profiling
g++ -pg -O3 -march=native ...

# Run with benchmark
./chess_engine_test

# Generate profile
gprof chess_engine_test > profile.txt

# Analyze hotspots
grep -A 20 "index by number of called" profile.txt
```

**Tuning Parameters**:
| Parameter | Default | Range | Impact |
|-----------|---------|-------|--------|
| priorLearningRate | 0.1 | 0.05-0.3 | Bound blending speed |
| backupMinimax | 1.0 | 0.0-1.0 | Minimax influence |
| lmrThreshold | 3 | 2-4 | When to reduce |
| historyBonus | depth | constant-depth² | History growth rate |

**Deliverables**:
- ✅ Enhanced benchmark script
- ✅ Profiling output
- ✅ Parameter tuning results
- ✅ Performance comparison (Phase 5 vs 6)
- ✅ Documentation update

---

## Implementation Schedule

### Session 1: Phase 6A (Enhanced Move Ordering)
- Day 1: Killer moves implementation
- Day 1: History heuristic implementation
- Day 2: Testing & benchmarking
- Day 2: Documentation

### Session 2: Phase 6B (Late Move Reductions)
- Day 1: LMR logic implementation
- Day 1: Re-search condition tuning
- Day 2: Testing & performance validation
- Day 2: Integration testing (6A + 6B)

### Session 3: Phase 6C + 6D (Node Types & Validation)
- Day 1: TypedMonteCarlo implementation
- Day 1: Backup blending logic
- Day 2: Comprehensive benchmarking
- Day 2: Parameter tuning
- Day 3: Final validation & documentation

---

## Expected Results

### After Phase 6A
```
Single-threaded: ~13x (10.02x * 1.3)
Multi-threaded (4 cores): ~43x (13 * 3.36 from Phase 4)
```

### After Phase 6B
```
Single-threaded: ~15.5x (10.02x * 1.3 * 1.2)
Multi-threaded (4 cores): ~52x (15.5 * 3.36)
```

### After Phase 6C
```
Single-threaded: ~17x (10.02x * 1.3 * 1.2 * 1.1)
Multi-threaded (4 cores): ~57x (17 * 3.36)
```

---

## Risk Mitigation

### Risk: Regression in correctness
- **Mitigation**: Run all 8 tests after each change
- **Safety**: Version control, easy rollback

### Risk: Parameter tuning breaks optimization
- **Mitigation**: Profile before/after each change
- **Safety**: Automated benchmark comparison

### Risk: Increased complexity hurts maintenance
- **Mitigation**: Clear documentation, unit tests
- **Safety**: Code review, comments on complex logic

---

## Success Criteria

✅ **Phase 6A Success**:
- Killer moves working, history heuristic tracking
- 20-30% faster move searches
- All 8 tests passing
- Code documented, benchmarks recorded

✅ **Phase 6B Success**:
- LMR reducing search depth correctly
- 15-20% faster deep searches
- Re-search condition working
- Cumulative 30-50% improvement

✅ **Phase 6C Success**:
- Node types tracked and promoted correctly
- Bounds blending at correct learning rate
- 10-15% improvement in convergence
- Cumulative 50-75% improvement expected

✅ **Phase 6D Success**:
- Comprehensive benchmarks completed
- Parameters tuned for maximum performance
- All features validated on correctness tests
- 20-30% total improvement demonstrated

---

## Deliverables by Phase

**Phase 6A**:
- Enhanced MCTS with killer moves + history heuristic
- 20-30% performance improvement
- Benchmark comparison (Phase 5 vs 6A)
- Updated documentation

**Phase 6B**:
- Late move reductions implementation
- 30-50% cumulative improvement
- Benchmark comparison (all phases)
- Performance analysis

**Phase 6C**:
- TypedMonteCarlo implementation
- 50-75% cumulative improvement
- Parameter tuning results
- Comprehensive documentation

**Phase 6D**:
- Final performance benchmarks
- Profiling analysis
- Optimization recommendations
- Production-ready code

---

## Conclusion

**Phase 6 Plan**: Implement 3 advanced optimizations from Dart MCTS to achieve 20-30% additional performance improvement while maintaining correctness.

**Expected Total Improvement**: 10x (Phase 5) → 15-20x (Phase 6) on Release build

**Next Steps**: Begin Phase 6A implementation with enhanced move ordering

---

**Status**: Ready for Phase 6 Implementation  
**Planning Complete**: November 19, 2026

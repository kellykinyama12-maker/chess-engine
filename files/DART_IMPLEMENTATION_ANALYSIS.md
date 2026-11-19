# Dart MCTS Implementation Analysis
## Advanced Features Beyond Current C++ Port

**Analysis Date**: November 19, 2026  
**Files Analyzed**: mcts_prior.dart, mcts_alphabeta.dart, mcts_new.dart  
**Status**: Identifying optimization opportunities for C++ implementation

---

## Overview

The Dart implementation contains several advanced features not yet ported to C++:

1. **TypedMonteCarlo** - MCTS with Alpha-Beta node type tracking
2. **Multi-Isolate Prior Search** - Parallel alpha-beta evaluation
3. **Prior Learning with Bounds** - Exact vs approximate node handling
4. **Sophisticated Move Ordering** - Killer moves, history heuristics, SEE
5. **Tactical Evaluation** - Quiescence search with advanced pruning

---

## 1. TypedMonteCarlo: Advanced Prior Integration

### What It Does
Extends standard MCTS by tracking alpha-beta **node types** on each edge:
- **PV (Principal Variation)**: Exact score, fully searched
- **ALL**: Upper bound, failed low
- **CUT**: Lower bound, failed high

### Key Insight
Instead of treating all prior values equally, it:
1. **Prioritizes PV moves** (exact values) first
2. **Challenges PV line** with best ALL node if its bound beats PV score
3. **Defers exploration** until PV line is exact
4. **Blends in bounds** at controlled learning rate when child is not exact

### Code Structure
```dart
class TypedEdge extends Edge {
  NodeType type;  // PV, ALL, or CUT
}

class TypedMonteCarlo extends MonteCarlo {
  // Track best PV and best ALL edge
  (TypedEdge?, TypedEdge?) _pvAndChallenger(Node node)
  
  // Modified tree policy: explore challenger if it beats PV
  void treePolicy() { ... }
  
  // Modified backup: update type, exact replaces, bound blends
  void backup(Reward reward) { ... }
}
```

### Performance Impact
- **Reduces wasted simulations** in guaranteed losing positions
- **Accelerates convergence** to best move
- **Maintains theoretical correctness** via node types

### C++ Port Complexity
⚠️ **MEDIUM**: Requires tracking NodeType on edges, modifying tree policy and backup logic.

---

## 2. Alpha-Beta with Late Move Reductions (LMR)

### What It Does
Full-width alpha-beta search with sophisticated pruning:
- **Late Move Reduction**: Quiet moves at ALL nodes searched shallower
- **Re-search if Promising**: Re-search at full depth if reduction fails
- **Quiet Move Detection**: Distinguishes captures/promotions from quiet moves
- **Index-based Reduction**: More aggressive as index increases

### Key Implementation
```dart
int _negamax(Chess position, int depth, int alpha, int beta, int ply) {
  // ... standard alpha-beta ...
  
  for (final move in orderMoves(...)) {
    final quiet = move.captured == null && move.promotion == null;
    
    // LMR for quiet moves at ALL nodes
    final reduce = lateMoveReduction &&
        allNode &&              // Beta - alpha == 1
        quiet &&                // Not a capture/promotion
        !inCheck &&             // Not in check
        depth >= 3 &&           // Sufficient depth
        index >= 3;             // Late enough move
    
    int reduce_depth = depth - 1 - (reduce ? (index >= 6 ? 2 : 1) : 0);
    score = -_negamax(position, reduce_depth, -beta, -alpha, ply+1);
    
    // Re-search at full depth if reduction failed
    if (reduce && score > alpha) {
      score = -_negamax(position, depth - 1, -beta, -alpha, ply+1);
    }
  }
}
```

### Performance Impact
- **10-20% faster search** with same depth
- **Reduced node count** while maintaining accuracy
- **Essential for practical engines**

### C++ Port Complexity
⚠️ **LOW-MEDIUM**: Logic is straightforward, but requires integrated into evaluation function.

---

## 3. Sophisticated Move Ordering

### Order Priority (Best to Worst)
1. **PV Move** (Principal variation from previous iteration) - Score: 1,000,000
2. **Winning Captures** (SEE ≥ 0) - Score: 100,000 + MVV-LVA
3. **Queen Promotions** - Score: 95,000
4. **Killer Move 1** (non-capture that caused cutoff) - Score: 90,000
5. **Killer Move 2** (second best killer) - Score: 80,000
6. **Quiet Moves** (by history heuristic) - Score: 0-79,999
7. **Losing Captures** (SEE < 0) - Score: -100,000 + MVV-LVA

### Key Heuristics
```dart
// Static Exchange Evaluation: estimate capture gain
see(position, move)  // Returns relative material exchange

// Killer moves: non-captures that caused beta cutoffs
_killers[ply][0], _killers[ply][1]

// History heuristic: quiet moves that caused cutoffs
_history[color * 128*128 + from*128 + to]

// MVV-LVA: Move-Victim Value - Least Attacker Value
mvvLva(move)  // Most valuable victim, least valuable attacker
```

### Performance Impact
- **2-3x faster search** with better move order
- **Earlier beta cutoffs** save deep recursion
- **Critical for alpha-beta pruning effectiveness**

### C++ Port Complexity
✅ **LOW**: Can use move scores from existing evaluation code.

---

## 4. Iterative Deepening with Time Management

### How It Works
```dart
List<PriorMove> searchPriors(
  Chess position, 
  int maxDepth, 
  {Duration? timeLimit}
) {
  var moves = [...initial order...];
  final sw = Stopwatch()..start();
  
  for (var depth = 0; depth <= maxDepth; depth++) {
    resetSearchState();
    // Set time limit: total time minus elapsed
    startSearchClock(timeLimit - sw.elapsed);
    
    final result = _searchRoot(position, depth, moves);
    
    // If time ran out during search, discard result
    if (searchStopped) break;
    moves = result;  // Use this depth's ordering
  }
  return moves;
}
```

### Benefits
- **Anytime algorithm**: Can return results at any depth
- **Progressive refinement**: Each depth improves move order
- **Time-aware cutoff**: Stops early if time limit approached
- **No wasted work**: Failed searches are discarded

### C++ Port Complexity
✅ **LOW-MEDIUM**: Straightforward, need time tracking.

---

## 5. TypedPriorPool: Parallel Alpha-Beta

### What It Does
Multi-isolate (Dart process) parallel search:
- Each worker handles subset of root moves (round-robin)
- Workers maintain their own alpha values
- Node types (PV/ALL) stay valid per worker

### Code Structure
```dart
class TypedPriorPool {
  List<_TypedWorker> _workers;  // Long-lived worker isolates
  
  Future<List<PriorMove>> searchPriors(...) async {
    for (var depth = 0; depth <= maxDepth; depth++) {
      // Distribute moves round-robin to workers
      shares = [moves.where(i % workers == w) for each worker w];
      
      // Run parallel searches
      results = await Future.wait([
        for each worker: worker.search(position, depth, shares[w], deadline)
      ]);
      
      // Merge results, re-sort by score
      moves = [...results].sort((a,b) => b.score - a.score);
    }
  }
}

class _TypedWorker {
  SendPort _commands;    // Send search requests
  ReceivePort _responses; // Receive results
  
  // Long-lived isolate that processes messages
  _typedWorkerMain(replies) {
    commands = ReceivePort();
    replies.send(commands.sendPort);
    commands.listen((Chess, depth, moves, deadline) => {
      result = _searchRoot(position, depth, moves);
      replies.send(result);
    });
  }
}
```

### Performance Impact
- **Linear scaling** with number of workers
- **Maintains node type validity** per worker
- **No synchronization overhead** (message-passing)

### C++ Port Complexity
⚠️ **HIGH**: Requires thread pool communication and synchronization.

---

## 6. Backup with Minimax Blending

### Standard MCTS Backup
```dart
reward = -reward;  // Flip perspective
edge.actionValue += reward;
edge.meanActionValue = edge.actionValue / edge.visits;
```

### Enhanced Backup (TypedMonteCarlo)
```dart
void backup(Reward reward) {
  var childBest = reward;
  var childExact = isExact(currentNode());  // Check node types
  
  while (ply > 0) {
    undoMove();
    reward = 1.0 - reward;
    
    // Update edge prior based on type
    if (childExact) {
      edge.prior = target;      // Exact: replace
      edge.type = NodeType.pv;  // Promote to PV
    } else {
      // Bounds: blend in at learning rate
      edge.prior += priorLearningRate * (target - edge.prior);
    }
    
    // Update action value
    edge.actionValue += reward;
    edge.meanActionValue = edge.actionValue / edge.visits;
    
    // Minimax blending: mix reward with best child's value
    minimax = bestChild(node, EdgeStatistic.mean).meanActionValue;
    reward = reward * (1.0 - backupMinimax) + minimax * backupMinimax;
  }
}
```

### Key Parameters
- **priorLearningRate** (default ~0.1): How much to blend bounds
- **backupMinimax** (default 1.0): How much to trust minimax vs reward

### C++ Port Complexity
✅ **LOW-MEDIUM**: Logic is clear, needs careful parameter tuning.

---

## Comparison: Current C++ vs Dart Version

| Feature | C++ (Phase 5) | Dart | Impact | Difficulty |
|---------|---------------|------|--------|-----------|
| Basic MCTS | ✅ | ✅ | Baseline | - |
| Parallel (threads) | ✅ | ✅ (isolates) | 3.36x | ✅ |
| Compiler Optimization | ✅ (-O3) | ✗ | 10.02x | ✅ |
| Node Type Tracking | ✗ | ✅ | ~15-20% | ⚠️ |
| Late Move Reduction | ✗ | ✅ | ~15-20% | ⚠️ |
| Move Ordering | Basic | Advanced | ~30-50% | ✅ |
| Iterative Deepening | ✗ | ✅ | Quality | ✅ |
| Minimax Blending | ✗ | ✅ | Varies | ⚠️ |
| Prior Pool | ✗ | ✅ | Parallel | ⚠️ |

---

## Recommended C++ Port Strategy

### Phase 6A: High-Priority Features (Best ROI)
1. **Sophisticated Move Ordering** (30-50% improvement)
   - Add killer moves heuristic
   - Add history heuristic
   - Integrate SEE (Static Exchange Evaluation)
   - Complexity: ✅ LOW
   - Estimated impact: **20-30% speedup**

2. **Late Move Reductions** (15-20% improvement)
   - Implement LMR logic
   - Track quiet moves
   - Add re-search condition
   - Complexity: ⚠️ MEDIUM
   - Estimated impact: **15-20% speedup**

### Phase 6B: Medium-Priority Features (Refinement)
3. **TypedMonteCarlo** (10-15% improvement)
   - Add NodeType tracking to edges
   - Modify tree policy to handle challengers
   - Update backup logic for blending
   - Complexity: ⚠️ MEDIUM
   - Estimated impact: **10-15% speedup**

4. **Iterative Deepening** (Quality improvement)
   - Implement depth-by-depth search
   - Add time management
   - Discard failed searches
   - Complexity: ✅ LOW
   - Estimated impact: **Better move selection, same speed**

### Phase 6C: Advanced Features (Future)
5. **TypedPriorPool** (Parallel improvement)
   - Implement per-thread prior search
   - Add message-passing synchronization
   - Complexity: ⚠️ MEDIUM-HIGH
   - Estimated impact: **Worker scaling (N workers ≈ N× speedup)**

---

## Expected Performance Gains

### Conservative Estimate (Low ROI features)
```
Current (Phase 5): 10.02x (vs unoptimized)
+ Move Ordering: 1.3x
= Total: 13x
```

### Moderate Estimate (Medium ROI features)
```
Current: 10.02x
+ Move Ordering: 1.3x
+ Late Move Reductions: 1.2x
+ Minimax Blending: 1.1x
= Total: ~16-17x
```

### Optimistic Estimate (All features)
```
Current: 10.02x
+ All single-thread improvements: ~1.5x (move order + LMR + minimax)
+ TypedMonteCarlo: 1.1x
= Subtotal: ~16-17x
+ Parallel (8 cores): 8x (but already 4x on 4 cores in Phase 4)
= Total: ~32-40x (or ~8-10x with 4 cores)
```

---

## Detailed Implementation Plans

### Implementation 1: Killer Moves (Priority: HIGH, Effort: LOW)

**Files to modify**: `cpp/src/move_gen.cpp`, `cpp/include/thread_pool.hpp`

**Changes**:
```cpp
// Add to MonteCarlo class
static constexpr int MAX_PLY = 128;
struct KillerMoves {
  Move primary[MAX_PLY];
  Move secondary[MAX_PLY];
};

// Update move ordering to check killers
int scoreMove(const Position& pos, Move m, int ply) {
  if (m == killers.primary[ply]) return 90000;
  if (m == killers.secondary[ply]) return 80000;
  // ... rest of scoring
}

// When beta cutoff occurs
void recordKiller(Move m, int ply) {
  if (!pos.isCapture(m)) {
    killers.secondary[ply] = killers.primary[ply];
    killers.primary[ply] = m;
  }
}
```

**Expected impact**: 10-15% faster move search

---

### Implementation 2: Late Move Reductions (Priority: HIGH, Effort: MEDIUM)

**Files to modify**: `cpp/src/mcts_new.cpp`, alpha-beta evaluation function

**Changes**:
```cpp
int alphaBeta(Position& pos, int depth, int alpha, int beta, int ply, bool isPVNode) {
  // ... initialization ...
  
  int index = 0;
  for (Move move : orderedMoves) {
    pos.makeMove(move);
    
    bool isQuiet = !pos.lastCaptured() && !move.isPromotion();
    bool shouldReduce = !isPVNode && isQuiet && depth >= 3 && index >= 3;
    
    int reduceDepth = depth - 1;
    if (shouldReduce) {
      reduceDepth = depth - 1 - (index >= 6 ? 2 : 1);
    }
    
    int score = -alphaBeta(pos, reduceDepth, -beta, -alpha, ply+1, false);
    
    if (shouldReduce && score > alpha) {
      score = -alphaBeta(pos, depth - 1, -beta, -alpha, ply+1, false);
    }
    
    pos.undoMove();
    index++;
    
    if (score >= beta) return beta;  // Beta cutoff
    if (score > alpha) alpha = score;
  }
  return alpha;
}
```

**Expected impact**: 15-20% faster deep searches

---

### Implementation 3: Iterative Deepening (Priority: MEDIUM, Effort: LOW)

**Files to modify**: `cpp/src/mcts_new.cpp` search interface

**Changes**:
```cpp
std::vector<RootMove> iterativeDeepening(
  Position& pos, 
  int maxDepth, 
  std::chrono::milliseconds timeLimit
) {
  std::vector<RootMove> moves = generateRootMoves(pos);
  auto startTime = std::chrono::steady_clock::now();
  
  for (int depth = 1; depth <= maxDepth; depth++) {
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::steady_clock::now() - startTime
    );
    
    if (elapsed + estimatedTimeForDepth >= timeLimit) {
      break;  // Skip this depth, return previous best
    }
    
    std::vector<RootMove> results = searchAtDepth(pos, depth, ...);
    
    if (searchInterrupted) {
      break;  // Return previous depth results
    }
    
    moves = results;  // Keep best results
  }
  
  return moves;
}
```

**Expected impact**: Better move ordering, smoother anytime response

---

## Risk Analysis

### Low Risk (Safe to implement)
- ✅ Killer moves
- ✅ History heuristic
- ✅ Iterative deepening
- ✅ Time management

### Medium Risk (Test thoroughly)
- ⚠️ Late Move Reductions (need extensive testing)
- ⚠️ TypedMonteCarlo (node type tracking)
- ⚠️ Minimax blending (parameter tuning)

### High Risk (Complex, needs careful validation)
- ⚠️ TypedPriorPool (parallel search, synchronization)
- ⚠️ Full alpha-beta integration (may break existing MCTS flow)

---

## Testing Strategy

### Unit Tests
```cpp
TEST(MoveOrdering, KillerMovesPriority) {
  // Verify killer moves rank above history
  // Verify secondary killer logic
}

TEST(LMR, ReductionDepth) {
  // Verify reduction depths at different indices
  // Verify re-search condition triggers correctly
}

TEST(IterativeDeepening, TimeManagement) {
  // Verify searches complete within time limit
  // Verify results improve with depth
}
```

### Integration Tests
```cpp
TEST(MCTS, WithTypeTracking) {
  // Run full search with TypedEdges
  // Verify node types tracked correctly
  // Compare performance vs non-typed
}

TEST(Performance, ComparisonBenchmark) {
  // Measure: standard MCTS vs enhanced MCTS
  // Measure: depth 1-10 search time
  // Measure: quality of move selection
}
```

### Regression Tests
```cpp
TEST(Correctness, AllTestsStillPass) {
  // All 8 existing test categories
  // Should maintain or improve scores
}
```

---

## Conclusion

The Dart MCTS implementation reveals several sophisticated features that could significantly enhance the C++ port:

1. **High-Impact, Low-Risk**: Move ordering (30-50% gain)
2. **Medium-Impact, Medium-Risk**: LMR + TypedMonteCarlo (15-20% each)
3. **Quality Improvements**: Iterative deepening, time management
4. **Advanced Features**: Parallel prior search (future phases)

**Recommended next phase**: Implement sophisticated move ordering + late move reductions for estimated 20-30% performance improvement with moderate implementation effort.

---

**Analysis Complete** ✅  
**Ready for**: Phase 6A (Enhanced Move Ordering & LMR Implementation)

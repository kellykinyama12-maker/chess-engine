# C++ MinGW Porting Plan for MCTS Chess Engine

## Executive Summary
Port the Dart-based Monte Carlo Tree Search (MCTS) chess engine (`lib/src/mcts_new.dart`) to C++ with MinGW compilation. This involves rewriting the core MCTS algorithm, tree data structures, and integration with a C++ chess library.

---

## Phase 1: Environment & Dependency Setup

### 1.1 MinGW Toolchain Setup
- **Goal**: Establish C++17 compilation environment for Windows
- **Tasks**:
  - Install MinGW-w64 (latest, supporting C++17)
  - Configure CMake (3.20+) for Windows builds
  - Set up build scripts for parallel compilation
  - Verify: `g++ --version` and `cmake --version`

### 1.2 Chess Library Selection
Current: `package:chess` (Dart library from vendor/)
Options for C++:
1. **Recommended**: Use existing C++ libraries:
   - `stockfish` source (C++17, FIDE-standard board representation)
   - `libarena` or custom minimal board representation
   
2. **Custom minimal implementation** (if keeping dependencies low):
   - Implement bitboard-based board representation
   - FEN parser/generator
   - Move generation (pseudo-legal to legal)
   - Zobrist hashing for position keys

- **Decision point**: Use partial Stockfish adaptation vs. write minimal chess logic
- **Recommendation**: Adapt Stockfish's board/move infrastructure (proven, well-tested)

### 1.3 Threading Library
- **Replace**: Dart isolates → C++ threading
- **Options**:
  - Standard `<thread>` (C++11/17)
  - `std::thread` with thread pool library (like `BS::thread_pool`)
  - Or minimal custom thread pool
  
- **Task**: Evaluate and select thread pool implementation

---

## Phase 2: Core Data Structure Migration

### 2.1 Zobrist Hashing & Board Representation
**Dart → C++**:
```dart
// Dart (from chess.dart)
Chess position = Chess();
position.zobrist;  // u64

// C++ equivalent
class Position {
    uint64_t zobrist_key;
    // Bitboard-based or array-based piece placement
};
```

**Tasks**:
- [ ] Implement/adapt Zobrist hash initialization (64 random numbers per piece-square)
- [ ] Board representation (choose: bitboards vs. piece arrays)
- [ ] FEN parsing and generation
- [ ] Move generator (legal move generation)

### 2.2 MultiHashMap Replacement
**Dart**:
```dart
class MultiHashMap {
  int size = 32;
  Map<int, List<Node>> buckets = {};
}
```

**C++ equivalent**:
```cpp
class MultiHashMap {
    static constexpr size_t BUCKET_SIZE = 32;
    std::unordered_map<uint64_t, std::vector<Node*>> buckets;
};
```

**Tasks**:
- [ ] Replace Dart `Map` with `std::unordered_map`
- [ ] Use `uint64_t` for zobrist keys (64-bit hash)
- [ ] Implement collision resolution for multiple nodes in same bucket
- [ ] Consider memory pooling for Node allocations

### 2.3 Node and Edge Structures
**Migration**:
```cpp
struct Edge {
    Move move;
    double prior;
    double action_value = 0.0;
    double mean_action_value = 0.0;
    uint32_t visits = 0;
};

struct Node {
    uint64_t key;  // zobrist hash
    uint32_t node_visits = 0;
    std::vector<Edge> children;
};
```

**Tasks**:
- [ ] Convert Dart dynamic types to C++ typed structures
- [ ] Use `std::vector` for children edges
- [ ] Implement move copy/serialization (`Move` struct)
- [ ] Memory optimization: consider fixed-size arrays vs. vectors

---

## Phase 3: Core Algorithm Migration

### 3.1 MonteCarlo Class Architecture
**Structure** (keep similar structure):
```cpp
class MonteCarlo {
public:
    Position position;
    std::vector<Node> nodes;
    std::vector<Edge*> edges;
    uint32_t ply = 0;
    uint32_t num_simulations = 0;
    
    // Configuration
    double exploration = 0.7;
    double backup_minimax = 1.0;
    double prior_learning_rate = 0.5;
    
    // Methods
    Future<Node> createRoot();
    void treePolicy();
    Future<Reward> playOutPolicy();
    void backup(Reward reward);
};
```

**Tasks**:
- [ ] Convert all Dart methods to C++
- [ ] Replace Dart `Future`/`async` with C++ threading (std::async or thread pool)
- [ ] Implement UCB calculation with exact numeric precision
- [ ] Port reward-value conversions (logistic scaling)

### 3.2 Key Algorithm Methods

#### 3.2.1 treePolicy()
```cpp
void MonteCarlo::treePolicy() {
    while (current_node().node_visits > 0 &&
           !current_node().children.empty() &&
           ply < max_ply - 2 &&
           !(ply > 0 && is_drawn(position))) {
        
        Node& s = current_node();
        Edge* ucb_edge = best_child(s, EdgeStatistic::UCB);
        s.node_visits++;
        ucb_edge->visits++;
        
        edges[ply] = ucb_edge;
        do_move(*ucb_edge);
        ply++;
    }
}
```

**Tasks**:
- [ ] Port selection logic (no changes to algorithm)
- [ ] Replace Dart's null-safe `!` with explicit checks
- [ ] Use references instead of copies where possible

#### 3.2.2 UCB Calculation
```cpp
double MonteCarlo::ucb(const Node& node, const Edge& edge) {
    double result = ucb_use_prior ? edge.prior 
                                   : (edge.visits > 0 ? edge.mean_action_value 
                                                      : ucb_unexpanded_node);
    double c = ucb_use_father_visits ? exploration * sqrt(node.node_visits) 
                                     : exploration;
    double losses = edge.visits - edge.action_value;
    double divisor = losses * ucb_losses_avoidance + 
                     edge.visits * (1.0 - ucb_losses_avoidance);
    result += c * edge.prior / (1.0 + divisor);
    result += ucb_log_term_factor * sqrt(log(node.node_visits) / (1.0 + edge.visits));
    return result;
}
```

**Tasks**:
- [ ] Port exact formula (use `<cmath>` for sqrt, log, exp)
- [ ] Ensure double precision matches Dart results
- [ ] Add unit tests for UCB values

#### 3.2.3 Backup Function
```cpp
void MonteCarlo::backup(Reward reward) {
    double child_best = reward;
    while (ply > 0) {
        undo_move();
        reward = 1.0 - reward;
        Edge& edge = *edges[ply];
        edge.prior += prior_learning_rate * ((1.0 - child_best) - edge.prior);
        edge.action_value += reward;
        edge.mean_action_value = edge.action_value / edge.visits;
        Node& node = current_node();
        child_best = best_child(node, EdgeStatistic::PRIOR)->prior;
        double minimax = best_child(node, EdgeStatistic::MEAN)->mean_action_value;
        reward = reward * (1.0 - backup_minimax) + minimax * backup_minimax;
    }
}
```

**Tasks**:
- [ ] Port pointer/reference semantics correctly
- [ ] Ensure backup propagation matches Dart behavior
- [ ] Handle edge cases (ply=0, empty children)

#### 3.2.4 Reward Conversion
```cpp
double MonteCarlo::value_to_reward(int centipawns) {
    // logistic: 1 / (1 + exp(k * cp))
    // +600cp → 0.95, -600cp → 0.05
    const double k = -0.00490739829861;
    return 1.0 / (1.0 + exp(k * centipawns));
}

int MonteCarlo::reward_to_value(double r) {
    if (r > 0.99) return 10000;
    if (r < 0.01) return -10000;
    const double g = 203.77396313709564;
    return (int)(g * log(r / (1.0 - r)));
}
```

**Tasks**:
- [ ] Use `std::exp` and `std::log` with appropriate precision
- [ ] Test reward↔value round-trip conversion accuracy

### 3.3 Expansion and Playout
**Port `expandNode()` and `playOutPolicy()`**:

```cpp
Future<Reward> MonteCarlo::expandNode() {
    Node& s = current_node();
    
    // Call prior search (iterativeDeepening replacement)
    std::vector<RootMove> moves = prior_pool != nullptr 
        ? await prior_pool->iterative_deepening(position, 16, prior_time_limit)
        : iterative_deepening(position, 16, prior_time_limit);
    
    if (!s.children.empty()) throw std::runtime_error("Children should be empty");
    
    for (const auto& m : moves) {
        s.children.emplace_back(m.move, value_to_reward(m.score));
    }
    
    s.node_visits = 1;
    return s.children.empty() ? 0.0 : s.children[0].prior;
}
```

**Tasks**:
- [ ] Port iterativeDeepening or replace with Stockfish's search
- [ ] Handle prior pool async calls (thread pool replacement)
- [ ] Ensure move scoring consistency

---

## Phase 4: Threading & Async Migration

### 4.1 Replace Dart Isolates with Thread Pool
**Dart**:
```dart
priorPool = await PriorPool.spawn(Platform.numberOfProcessors);
```

**C++**:
```cpp
// Option 1: std::async + std::future
std::vector<std::future<std::vector<RootMove>>> futures;

// Option 2: Custom thread pool (e.g., BS::thread_pool)
BS::thread_pool pool(std::thread::hardware_concurrency());

// In MonteCarlo:
std::shared_ptr<ThreadPool> prior_pool;
```

**Tasks**:
- [ ] Implement or integrate thread pool library
- [ ] Port `PriorPool.spawn()` and `iterativeDeepening()` async calls
- [ ] Replace Dart `Future<T>` with C++ `std::future<T>`
- [ ] Handle thread synchronization for tree access (use `std::mutex` if needed)
- [ ] Consider lock-free structures for high-performance tree access

### 4.2 Main Simulation Loop Threading
**Port the simulate() method**:
```cpp
void MonteCarlo::simulate() {
    search_clock.reset();
    search_clock.start();
    
    // Async root creation
    auto root_future = std::async(std::launch::async, [this]() { 
        return createRoot(); 
    });
    
    while (simulation_budget()) {
        tree_policy();
        auto reward_future = std::async(std::launch::async, [this]() {
            return playout_policy();
        });
        Reward r = reward_future.get();
        backup(r);
    }
    
    emit_pv();
}
```

**Tasks**:
- [ ] Determine async/await simulation strategy (std::async vs. thread pool)
- [ ] Ensure thread safety in tree updates
- [ ] Profile performance vs. Dart version

---

## Phase 5: Build System & Compilation

### 5.1 CMake Project Structure
```cmake
cmake_minimum_required(VERSION 3.20)
project(chess_engine_cpp)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# MinGW-specific settings
if(MINGW)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -march=native")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -static-libgcc -static-libstdc++")
endif()

# Chess library
add_subdirectory(vendor/chess_cpp)

# MCTS library
add_library(mcts_cpp
    src/mcts_new.cpp
    src/position.cpp
    src/move_gen.cpp
)
target_include_directories(mcts_cpp PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_link_libraries(mcts_cpp chess_cpp)

# Executable
add_executable(chess_engine bin/main.cpp)
target_link_libraries(chess_engine mcts_cpp)
```

**Tasks**:
- [ ] Create directory structure:
  ```
  src/
    mcts_new.cpp
    position.cpp
    move_gen.cpp
    board.cpp
    zobrist.cpp
  include/
    mcts_new.hpp
    position.hpp
    types.hpp
  tests/
    test_mcts.cpp
    test_ucb.cpp
  ```
- [ ] Implement CMake find module for chess library
- [ ] Set up MinGW compiler flags
- [ ] Create build scripts for Windows

### 5.2 Header Files
Create core headers:

**include/types.hpp**:
- Move struct (from→to→promotion)
- EdgeStatistic enum
- Reward type definition
- Constants (maxPly, mateScore, etc.)

**include/position.hpp**:
- Position class with Zobrist hashing
- Board representation
- Legal move generation

**include/mcts_new.hpp**:
- Edge, Node, MultiHashMap classes
- MonteCarlo class
- Thread pool integration

---

## Phase 6: Testing & Validation

### 6.1 Unit Tests
Create test suite for:
- [ ] Zobrist hash consistency
- [ ] Move generation correctness (compare with Dart version)
- [ ] UCB calculation accuracy
- [ ] Reward↔value conversion precision
- [ ] Tree insertion and retrieval
- [ ] Backup propagation
- [ ] Board position undo/redo

**Test Framework**: Google Test (gtest) or Catch2

### 6.2 Integration Tests
- [ ] Play test games against Dart version
- [ ] Verify move selection consistency
- [ ] Compare evaluation scores
- [ ] Performance benchmarks

### 6.3 Behavioral Tests
- [ ] Reproduce same game sequences as Dart version
- [ ] Test with identical positions and random seeds
- [ ] Validate PV (principal variation) output

---

## Phase 7: Performance Optimization

### 7.1 Profiling
- Use `gprof` or Windows Performance Analyzer
- Identify bottlenecks (tree traversal, move generation, reward calculation)

### 7.2 Optimization Targets
- [ ] **Move Generation**: Cache legal moves or use pre-computed tables
- [ ] **Hash Table**: Consider transposition table optimization
- [ ] **Memory Layout**: Ensure cache-friendly Node/Edge layout
- [ ] **SIMD**: Consider vectorization for reward calculations
- [ ] **Lock Contention**: Optimize thread pool for minimal synchronization

### 7.3 Expected Performance
- C++ should be **5-10x faster** than Dart for:
  - Move generation
  - Tree traversal
  - Reward calculations

---

## Phase 8: Deliverables & Integration

### 8.1 Library Interface
Create clean C++ API matching Dart behavior:
```cpp
// Simplified public API
class MonteCarlo {
public:
    MonteCarlo();
    ~MonteCarlo();
    
    std::vector<RootMove> find_best_move(
        const std::string& fen, 
        int max_simulations,
        std::optional<std::chrono::milliseconds> time_limit
    );
    
    std::vector<std::string> principal_variation() const;
};
```

### 8.2 Compilation Verification
- [ ] Compile with MinGW (g++ C++17)
- [ ] No warnings with `-Wall -Wextra`
- [ ] Address sanitizer: `-fsanitize=address`
- [ ] Link with static libraries (no external DLL dependencies)

### 8.3 Documentation
- [ ] README with build instructions
- [ ] Porting notes (Dart → C++ changes)
- [ ] Performance comparison report
- [ ] Thread pool usage guide

---

## Risk Assessment & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Chess library incompatibility | Medium | High | Test move gen early; have backup minimal implementation |
| Threading deadlocks | Low | High | Use lock-free structures; extensive testing |
| Precision loss in numeric conversions | Low | Medium | Unit test all conversions; compare results |
| Performance regression | Medium | Medium | Profile early; optimize bottlenecks incrementally |
| MinGW compatibility issues | Low | Low | Test on multiple MinGW versions; CI setup |
| Zobrist hash collisions | Very low | Medium | Use collision handling; validate hash distribution |

---

## Timeline Estimate

| Phase | Task | Duration | Dependencies |
|-------|------|----------|--------------|
| 1 | Setup & chess library | 2-3 days | None |
| 2 | Data structures | 3-4 days | Phase 1 |
| 3 | Algorithm migration | 5-7 days | Phase 2 |
| 4 | Threading & async | 3-4 days | Phase 3 |
| 5 | Build system | 2-3 days | Phase 1, 2 |
| 6 | Testing | 5-7 days | Phase 3-5 |
| 7 | Optimization | 3-5 days | Phase 6 |
| 8 | Final integration | 2-3 days | Phase 7 |
| **Total** | | **25-36 days** | |

---

## File Structure (Final)

```
chess-engine/
├── CMakeLists.txt
├── README_CPP.md
├── PORTING_NOTES.md
├── src/
│   ├── mcts_new.cpp
│   ├── position.cpp
│   ├── move_gen.cpp
│   ├── board.cpp
│   └── zobrist.cpp
├── include/
│   ├── types.hpp
│   ├── position.hpp
│   ├── move_gen.hpp
│   ├── mcts_new.hpp
│   ├── thread_pool.hpp
│   └── zobrist.hpp
├── bin/
│   └── main.cpp
├── tests/
│   ├── CMakeLists.txt
│   ├── test_mcts.cpp
│   ├── test_ucb.cpp
│   ├── test_position.cpp
│   └── test_move_gen.cpp
├── vendor/
│   ├── chess/          (existing Dart chess lib)
│   └── chess_cpp/      (C++ chess lib - to be added)
└── lib/
    └── src/
        ├── mcts_new.dart (original)
        └── ... (other Dart files)
```

---

## Decision Points (Requires Input)

1. **Chess Library**: Use adapted Stockfish code or minimal custom implementation?
2. **Threading Model**: `std::async` + `std::future` or custom thread pool?
3. **Board Representation**: Bitboards or piece arrays?
4. **Testing Approach**: Compare output vs. Dart or focus on unit tests?
5. **Performance Baseline**: Acceptable C++ vs. Dart speedup ratio?

---

## Next Steps

1. **Immediate**: Decide on chess library approach (Phase 1.2)
2. **Week 1**: Complete Phases 1-2 (setup + data structures)
3. **Week 2-3**: Complete Phases 3-4 (algorithm + threading)
4. **Week 4-5**: Complete Phases 5-8 (build, test, optimize)

---

*Plan created: 2026-11-16*
*Target: C++17 with MinGW on Windows*

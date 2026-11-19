# Build Guide - Chess Engine C++ (CMake)

A comprehensive guide to building the chess engine with CMake and MinGW on Windows, including optimization strategies and benchmarking.

## Quick Start

### Prerequisites
- **MinGW**: GCC 11.0+
- **CMake**: 3.20+
- **Make**: MinGW makefiles
- **Git**: For version control

Install via WinGet:
```bash
winget install GnuWin32.Make
winget install Kitware.CMake
winget install BrechtSanders.WinLibs
```

### Build Release (Optimized)
```bash
cd cpp
mkdir build && cd build
cmake .. -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release
```

### Build Debug (Development)
```bash
cd cpp
mkdir build_debug && cd build_debug
cmake .. -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Debug
cmake --build . --config Debug
```

### Run Tests
```bash
cd build
./chess_engine_test.exe
```

## Build Configuration

### Project Structure
```
cpp/
├── CMakeLists.txt           # Main build configuration
├── include/                 # Header files
│   ├── position.hpp
│   ├── move_gen.hpp
│   ├── mcts_new.hpp
│   ├── thread_pool.hpp
│   └── zobrist.hpp
├── src/                     # Implementation files
│   ├── position.cpp
│   ├── move_gen.cpp
│   ├── zobrist.cpp
│   ├── mcts_new.cpp
│   ├── thread_pool.cpp
│   └── main.cpp
└── build/                   # (generated) Build output
```

### CMake Targets

| Target | Type | Purpose |
|--------|------|---------|
| `chess_core` | Library | Core chess logic (position, move generation, zobrist hashing) |
| `mcts_engine` | Library | MCTS algorithm and thread pool |
| `chess_engine` | Executable | Standalone engine application |
| `chess_engine_test` | Executable | Comprehensive test suite |

## Optimization Strategies

### Release Build Flags
The Release build applies aggressive optimizations:

```cmake
-O3                 # Maximum optimization level
-march=native       # CPU-specific optimizations
-flto               # Link-time optimization
-static-libgcc      # Static runtime linkage (portable binaries)
-static-libstdc++
```

### Debug Build Flags
The Debug build prioritizes debugging capability:

```cmake
-g                  # Debug symbols
-O0                 # No optimization
-static-libgcc      # Static runtime linkage
-static-libstdc++
```

### Performance Impact

**Benchmark Results** (CMake Release vs Debug):
- Release build: **82.3 ms** (average)
- Debug build: **825 ms** (average)
- **Speedup: 10.02x faster**
- **Improvement: 90% faster**

**Binary Size**:
- Release: 2.82 MB (stripped, optimized)
- Debug: 4.48 MB (with debug symbols)

### Optimization Techniques

#### 1. `-O3`: Aggressive Loop Unrolling & Inlining
Significantly improves performance for:
- MCTS tree traversal (UCB calculations)
- Move generation (highly optimized loops)
- Position evaluation (frequently called functions)

#### 2. `-march=native`: CPU-Specific Optimizations
Enables:
- Vectorized instructions (SSE2, AVX, etc.)
- CPU-specific performance tuning
- **Important**: Only use for binaries on same CPU architecture

#### 3. `-flto`: Link-Time Optimization
Provides:
- Cross-module function inlining
- Global constant folding
- Dead code elimination
- Expected 5-15% additional speedup

#### 4. `-static-libgcc`/`-static-libstdc++`: Portable Binaries
Ensures:
- No dependency on external runtime libraries
- Cross-system compatibility
- Faster startup (no runtime linking)

## Platform-Specific Instructions

### Windows (MinGW)
```bash
cd cpp
mkdir build && cd build
cmake .. -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release --parallel 4
```

**MinGW Notes**:
- Use `-G "MinGW Makefiles"` generator
- LTO warnings about plugins are normal (compilation succeeds)
- Static linking ensures portable binaries
- Parallel builds with `--parallel 4` speed up compilation

### Linux (GCC)
```bash
cd cpp
mkdir build && cd build
cmake .. -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release --parallel 4
```

### macOS (Clang)
```bash
cd cpp
mkdir build && cd build
cmake .. -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release --parallel 4
```

**Note**: Clang uses similar flags but with slightly different optimization behavior.

## Compilation Details

### Object Libraries
The build uses CMake `OBJECT` libraries to avoid re-linking overhead:
- `chess_core_obj`: Position, move generation, zobrist hashing
- `mcts_engine_obj`: MCTS algorithm, thread pool

This approach:
- Compiles each file once
- Links multiple executables efficiently
- Maintains clean dependency graph

### Compiler Warnings
Expected warnings (safe to ignore):
- Unused function parameters in `mcts_new.cpp` (intentional API signatures)
- LTO plugin warnings from MinGW (doesn't affect compilation)

### Build Time
Typical build times:
- Release (clean): 45-60 seconds
- Debug (clean): 30-40 seconds
- Incremental rebuild: 5-10 seconds

## Testing & Verification

### Run Test Suite
```bash
cd build
./chess_engine_test.exe
```

**Test Categories**:
1. **Edge Structure Tests** - MCTS edge creation and updates
2. **Node Structure Tests** - MCTS node management
3. **MultiHashMap Tests** - Concurrent hash table operations
4. **Reward Conversion Tests** - Value to reward scaling
5. **MCTS Root Creation** - Starting position setup
6. **UCB Formula Tests** - Upper Confidence Bound calculations
7. **MCTS Search Tests** - Sequential search execution
8. **Parallel MCTS Tests** - Multi-threaded search verification

### Benchmark Performance
```bash
cd cpp
./benchmark.ps1
```

This script:
- Builds both Release and Debug versions
- Runs each 3 times and averages results
- Calculates speedup and improvement percentages
- Provides optimization analysis

### Expected Test Output
```
✓ Root created with 20 children
✓ Search completed
  Best move: a2a3
  Best value: 0.2500
  Visits: 170
  Total simulations: 100
  Elapsed: 1ms

Running with 4 threads...
✓ Parallel search completed
  Threads: 4
  Best move: a2a3
  Best value: 0.5000
  Visits: 1001
  Total simulations: 1000
  Elapsed: 4ms
```

## Troubleshooting

### "CMake not found"
Install via WinGet:
```bash
winget install Kitware.CMake
```

### "MinGW not found"
Install via WinGet:
```bash
winget install BrechtSanders.WinLibs
```

### "LTO plugin needed to handle lto object"
This is a MinGW LTO warning and can be safely ignored. Compilation succeeds.

### Binary won't run
If using `-march=native`, the binary may require specific CPU features. Test on target machine or rebuild on that machine.

### Slow compilation with `-flto`
LTO adds compilation time but improves runtime performance significantly. Use `-DCMAKE_BUILD_TYPE=Debug` for fast development builds without LTO.

### "ninja not found" / "nmake not found"
Use `"MinGW Makefiles"` or `"Unix Makefiles"` generators instead of Ninja.

## Performance Tuning Tips

### For Maximum Performance
1. Use Release build with `-O3 -march=native -flto`
2. Enable parallel test running
3. Use multi-threaded MCTS search (4+ threads on quad-core)
4. Consider profiling with `gprof` or platform profiler

### For Faster Development
1. Use Debug build (`-O0`) for edit-compile-test cycles
2. Enable quick incremental builds
3. Run only affected tests
4. Disable LTO for faster compilation

### For Portable Binaries
1. Build with `-O3 -flto` but without `-march=native`
2. This loses some CPU-specific optimization but improves portability
3. Test on multiple CPU models if distribution is planned

## CMakeLists.txt Reference

Key CMake variables controlling the build:

```cmake
CMAKE_BUILD_TYPE                # Release or Debug
CMAKE_CXX_STANDARD             # 17 (C++17)
CMAKE_CXX_STANDARD_REQUIRED    # True (require C++17)
BUILD_TESTING                  # ON/OFF (enable tests)
```

Compiler flags by platform:
```cmake
# Windows (MinGW)
set(CMAKE_CXX_FLAGS_RELEASE "-O3 -march=native -flto -static-libgcc -static-libstdc++")
set(CMAKE_CXX_FLAGS_DEBUG "-g -O0 -static-libgcc -static-libstdc++")

# Linux/macOS (GCC/Clang)
set(CMAKE_CXX_FLAGS_RELEASE "-O3 -march=native -flto")
set(CMAKE_CXX_FLAGS_DEBUG "-g -O0")
```

## Contributing & Development

### Adding New Source Files
1. Add `.cpp` file to `src/`
2. Add `.hpp` header to `include/`
3. Update `CMakeLists.txt` source list:
```cmake
set(CHESS_CORE_SOURCES
    src/position.cpp
    src/move_gen.cpp
    src/zobrist.cpp
    src/new_file.cpp          # Add here
)
```
4. Rebuild: `cmake --build . --config Release`

### Running Clang-Format (Optional)
```bash
# Format all source files
find . -name "*.cpp" -o -name "*.hpp" | xargs clang-format -i
```

### Static Analysis (Optional)
```bash
# Run with clang-tidy (if installed)
cmake .. -DCMAKE_CXX_CLANG_TIDY="clang-tidy"
cmake --build .
```

## Related Documentation

- **[PORTING_PLAN_CPP_MINGW.md](../PORTING_PLAN_CPP_MINGW.md)** - Overall porting strategy and phases
- **[Phase_1_to_4_Progress_Report.md](../files/Phase_1_to_4_Progress_Report.md)** - Completion summary
- **[PHASE4_FINAL_DELIVERABLES.md](../files/PHASE4_FINAL_DELIVERABLES.md)** - Phase 4 results (multi-threading)

## License

This build system follows the same license as the main project.

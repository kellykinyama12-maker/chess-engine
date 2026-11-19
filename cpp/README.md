# Quick Start Guide - Chess Engine C++ Port

## Prerequisites
- Windows 10/11
- MinGW (WinLibs) installed via: `winget install BrechtSanders.WinLibs.POSIX.UCRT`

## Building

**Simple Method** (Windows CMD or PowerShell):
```batch
cd cpp
build.bat build
```

Output: `build\bin\chess_engine.exe`

**Direct Method** (MinGW installed):
```bash
cd cpp
mingw32-make build
```

## Running

**From cpp directory**:
```batch
mingw32-make build
.\build\bin\chess_engine.exe
```

**Or directly**:
```bash
# Set MinGW PATH first
SET PATH=C:\Users\%USERNAME%\AppData\Local\Microsoft\WinGet\Packages\BrechtSanders.WinLibs.POSIX.UCRT_Microsoft.Winget.Source_8wekyb3d8bbwe\mingw64\bin;%PATH%
.\build\bin\chess_engine.exe
```

**Current Output** (working!):
```
Hello from Chess Engine
Calling Zobrist::init()...
Zobrist init complete!

Creating starting position...
Position created!

  a b c d e f g h
8 r n b q k b n r 8
7 p p p p p p p p 7
6                 6
5                 5
4                 4
3                 3
2 P P P P P P P P 2
1 R N B Q K B N R 1
  a b c d e f g h

FEN: rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1
```

## Project Structure

```
cpp/
├── include/           # Header files
│   ├── types.hpp      # Chess piece types, moves, squares
│   ├── position.hpp   # Board representation
│   ├── zobrist.hpp    # 64-bit hashing
│   └── move_gen.hpp   # Move generation
├── src/               # Implementation
│   ├── main.cpp       # Entry point
│   ├── position.cpp   # Board & FEN logic
│   ├── zobrist.cpp    # Hash table init
│   └── move_gen.cpp   # Move generator
├── build/             # Compiler output
│   └── bin/
│       └── chess_engine.exe
├── Makefile           # Build rules
├── build.bat          # Windows build launcher
└── docs/
    ├── PHASE1_COMPLETE.md
    └── PORTING_PLAN_CPP_MINGW.md
```

## Key Classes

### `Position`
```cpp
Position pos("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
pos.ascii();              // Print board
pos.fen();                // Get FEN string
pos.make_move(move);      // Execute move
pos.unmake_move();        // Undo move
pos.legal_moves();        // All legal moves
pos.is_check();           // King in check?
pos.get_zobrist();        // 64-bit hash
```

### `Move`
```cpp
Move m(Square(0), Square(16));           // a1 -> a3
m = Move(Square(0), Square(16), QUEEN);  // With promotion
m.to_string();  // "a1a3" or "a1a8q"
```

### `Zobrist`
```cpp
Zobrist::init();              // Initialize once
auto hash = Zobrist::piece(piece, square);
auto side_hash = Zobrist::side();
auto castle_hash = Zobrist::castling_rights(wk, wq, bk, bq);
```

## Development

### Adding New Files
1. Create `.hpp` in `include/`
2. Create `.cpp` in `src/`
3. Update `Makefile` SOURCES variable
4. Run `mingw32-make clean && mingw32-make build`

### Debugging
- Add `#include <iostream>` and `std::cout << ...`
- Use `std::hex` for Zobrist hashes
- Check board with `pos.ascii()`

### Optimization
- Flags: `-O3 -march=native` (already set)
- For profiling: replace `-O3` with `-g -O2`

## Next Tasks

1. ✅ **Phase 1 (DONE)**: Chess types + board representation
2. 🔄 **Phase 2 (NEXT)**: Complete move generation
3. ⏳ **Phase 3**: MCTS data structures (Node, Edge, MultiHashMap)
4. ⏳ **Phase 4**: MCTS algorithm (tree policy, backup)
5. ⏳ **Phase 5**: Threading for parallel search

## Troubleshooting

**Q: Executable crashes immediately**
- A: Ensure MinGW PATH is set before running. Use `build.bat`.

**Q: "g++: command not found"**
- A: Run `build.bat` or set PATH to MinGW bin directory

**Q: Symbol errors during linking**
- A: Check all source files are in `Makefile` SOURCES

**Q: Different move counts than Dart**
- A: Move generator is incomplete - stubs only for now

## References

- [MinGW-w64](https://www.mingw-w64.org/)
- [C++17 Standard](https://en.cppreference.com/w/cpp/17)
- Original Dart: `lib/src/mcts_new.dart`
- Porting Plan: `PORTING_PLAN_CPP_MINGW.md`

---

**Last Updated**: 2026-11-16
**Status**: Phase 1 Complete, Phase 2 In Progress

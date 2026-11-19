# Phase 6E: UCI Protocol Implementation Plan

## Overview
UCI (Universal Chess Interface) is the standard protocol for chess engines to communicate with graphical user interfaces and chess platforms. Expected implementation: **~2-3 hours**.

## UCI Protocol Basics

### Standard UCI Commands

**Engine → GUI**:
- `id name <name>` - Engine identification
- `id author <author>` - Author name
- `uciok` - Acknowledgment of uci command completion
- `readyok` - Readiness acknowledgment
- `bestmove <move> [ponder <move>]` - Search result
- `info depth <d> seldepth <sd> score <score> nodes <nodes> time <ms> pv <line>` - Search progress

**GUI → Engine**:
- `uci` - Initialize engine
- `isready` - Check if engine is ready
- `setoption name <id> value <x>` - Set option
- `ucinewgame` - Reset for new game
- `position fen <fenstring> [moves <move1> ... <moveN>]` - Set position
- `position startpos [moves <move1> ... <moveN>]` - Set to starting position
- `go [wtime <ms>] [btime <ms>] [winc <ms>] [binc <ms>] [depth <d>] [movetime <ms>] [nodes <n>] [infinite]` - Start search
- `stop` - Stop search
- `quit` - Shutdown

## Implementation Plan

### 1. UCI Handler Class

**File**: `cpp/include/uci.hpp`

```cpp
class UciHandler {
public:
    UciHandler(const std::string& name = "ChessEngine", 
               const std::string& author = "AI Assistant");
    
    // Main loop for UCI communication
    void run();
    
    // Command handlers
    void handle_uci();
    void handle_isready();
    void handle_setoption(const std::string& line);
    void handle_ucinewgame();
    void handle_position(const std::string& line);
    void handle_go(const std::string& line);
    void handle_stop();
    void handle_quit();
    
    // Utility functions
    static std::vector<std::string> split_command(const std::string& line);
    
private:
    std::string engine_name;
    std::string engine_author;
    Position current_position;
    TypedMonteCarlo* search_engine;
    bool search_running;
    
    // Options
    std::unordered_map<std::string, std::string> options;
};
```

### 2. Command Processing

**Input processing loop**:
```cpp
void UciHandler::run() {
    std::string line;
    while (std::getline(std::cin, line)) {
        if (line.empty()) continue;
        
        auto tokens = split_command(line);
        if (tokens.empty()) continue;
        
        std::string cmd = tokens[0];
        
        if (cmd == "uci") {
            handle_uci();
        } else if (cmd == "isready") {
            handle_isready();
        } else if (cmd == "setoption") {
            handle_setoption(line);
        } else if (cmd == "ucinewgame") {
            handle_ucinewgame();
        } else if (cmd == "position") {
            handle_position(line);
        } else if (cmd == "go") {
            handle_go(line);
        } else if (cmd == "stop") {
            handle_stop();
        } else if (cmd == "quit") {
            handle_quit();
            break;
        }
    }
}
```

### 3. Key Command Implementations

**UCI Initialization**:
```
Input:  uci
Output: id name ChessEngine
        id author AI Assistant
        option name Threads type spin default 1 min 1 max 8
        option name Hash type spin default 512 min 32 max 2048
        uciok
```

**Position Setup**:
```
Input:  position startpos moves e2e4 c7c5
Output: (loads position, applies moves)

Input:  position fen rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1
Output: (loads from FEN)
```

**Search with Time Control**:
```
Input:  go wtime 300000 btime 300000 winc 5000 binc 5000
Output: info depth 15 seldepth 18 score cp 35 nodes 1234567 time 1234 pv e2e4 c7c5
        bestmove e2e4 ponder c7c5
```

## Files to Create/Modify

1. **cpp/include/uci.hpp** (NEW)
   - UciHandler class declaration
   - Command handling interface
   - Option management

2. **cpp/src/uci.cpp** (NEW)
   - UciHandler implementation
   - Command parsers
   - Output formatters

3. **cpp/src/main.cpp** (MODIFY)
   - Add UCI mode detection
   - Create UciHandler instance
   - Run UCI loop

4. **CMakeLists.txt** (MODIFY)
   - Add uci.cpp to source files

## Testing Strategy

1. **Manual UCI testing**:
   - Echo commands manually
   - Verify responses match UCI spec
   - Test position loading
   - Test search with time limits

2. **UCI Compliance**:
   - Verify protocol compliance
   - Test with different GUI apps
   - Validate move format
   - Check response timing

## Expected Features

✅ Full UCI protocol compliance
✅ Position loading (FEN and moves)
✅ Search with time management
✅ Multi-option support
✅ Proper UCI message formatting
✅ Clean shutdown handling

## Success Criteria

- ✅ Zero compilation errors
- ✅ All UCI commands recognized
- ✅ Proper response formatting
- ✅ Interoperable with standard chess GUIs
- ✅ Documentation complete

---

**Timeline**: 2-3 hours
**Complexity**: Medium
**Impact**: Enables GUI integration and online play

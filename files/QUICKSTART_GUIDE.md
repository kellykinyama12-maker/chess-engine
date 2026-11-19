# Chess Engine - Quick Start Guide
## Phase 6 Complete - UCI Protocol Ready

---

## 🚀 Getting Started (60 seconds)

### 1. **Build the Engine**
```bash
cd cpp
mkdir build_phase6e
cd build_phase6e
cmake ..
cmake --build . --config Release
```

### 2. **Run UCI Engine**
```bash
# Windows
Release\chess_engine_uci.exe

# Linux/Mac
./Release/chess_engine_uci
```

### 3. **Test Connection**
```bash
uci
# Should respond with engine info
isready
# Should respond with: readyok
```

---

## 📋 Core Commands

### Game Setup
```
# Start new game
ucinewgame

# Set starting position
position startpos

# Set custom position (FEN)
position fen rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1
```

### Move Input
```
# With move sequence
position startpos moves e2e4 c7c5 g1f3

# Promotion moves
position startpos moves e2e4 e7e5 g1f3 ... e7e8q
```

### Search Commands
```
# Depth search
go depth 15

# Time-based (5 seconds)
go movetime 5000

# Clock time (5 minutes white, 3 minutes black, 5 sec increment each)
go wtime 300000 btime 180000 winc 5000 binc 5000

# Node limit
go nodes 1000000

# Infinite search (stop with 'stop' command)
go infinite
```

### Configuration
```
# Set hash table size (512 MB)
setoption name Hash value 512

# Set thread count
setoption name Threads value 4

# Apply settings
ucinewgame
```

---

## 🎯 Common Workflows

### Analyze a Position

```bash
# Launch engine
./chess_engine_uci

# Load position
position fen rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1

# Analyze
go depth 20

# Engine responds with best move
# Example: bestmove g8f6 ponder e4e5
```

### Play a Game

```
# White: Set starting position
position startpos

# White: Calculate move (5 seconds per move)
go movetime 5000
# → bestmove e2e4

# Black: Update position with white's move
position startpos moves e2e4

# Black: Calculate response
go movetime 5000
# → bestmove c7c5

# Continue alternating...
```

### Blitz Game (5+3)

```
# 5 minute game, 3 second increment

# Move 1 - White
go wtime 300000 btime 300000 winc 3000 binc 3000

# Move 2 - Black
# Update time: 300000 - search_time + 3000
go wtime [recalc] btime [recalc] winc 3000 binc 3000

# Continue...
```

---

## 📊 Engine Options

### Adjustable Parameters

| Option | Default | Min | Max | Purpose |
|--------|---------|-----|-----|---------|
| Hash | 512 | 32 | 2048 | Transposition table (MB) |
| Threads | 1 | 1 | 8 | Parallel search threads |

### Setting Options

```bash
# Increase hash to 1GB
setoption name Hash value 1024

# Use 4 cores
setoption name Threads value 4

# Apply (must do after changing options)
ucinewgame
```

---

## 🔍 Move Notation

### Standard UCI Format

```
e2e4   → Pawn e2 to e4
g1f3   → Knight g1 to f3
e7e8q  → Pawn e7 to e8, promote to Queen
e1g1   → King e1 to g1 (castling kingside)
e1c1   → King e1 to c1 (castling queenside)
```

### Position History

```
# Example: Sicilian Defense
position startpos moves e2e4 c7c5 g1f3 d7d6 d2d4 c5d4

# After these moves:
# White: e4, Nf3, d4
# Black: c5, d6, cxd4
```

---

## 🧪 Testing

### Verify Installation

```bash
# 1. Check engine responds
echo "isready" | chess_engine_uci.exe
# Expected: readyok

# 2. Check board loading
echo -e "position startpos\ngo depth 5" | chess_engine_uci.exe
# Expected: bestmove e2e4 (or similar)

# 3. Check FEN parsing
echo -e "position fen 8/8/8/4k3/8/4K3/8/8 w - - 0 1\ngo depth 10" | chess_engine_uci.exe
# Expected: bestmove <valid_move>
```

### Run Tests

```bash
# Compile with tests
cmake --build . --config Release --target RUN_TESTS

# Or run directly
Release\chess_engine_test.exe
```

---

## ⚡ Performance Tips

### Maximize Strength

```
# Increase hash and threads for better play
setoption name Hash value 2048
setoption name Threads value 8
ucinewgame

# Give more time per move
position startpos
go wtime 600000 btime 600000 winc 10000 binc 10000
```

### Speed Up Computation

```
# Reduce hash for faster games
setoption name Hash value 256
ucinewgame

# Use time constraint
go movetime 2000  # 2 seconds per move
```

### Balance (Standard)

```
# Default settings
setoption name Hash value 512
setoption name Threads value 4
ucinewgame

# Standard increment time
go wtime 300000 btime 300000 winc 5000 binc 5000
```

---

## 🐛 Troubleshooting

### Engine won't start
```bash
# Check executable location
ls -la Release/chess_engine_uci.exe

# Try with full path
/full/path/to/chess_engine_uci.exe

# Check permissions (Linux/Mac)
chmod +x Release/chess_engine_uci.exe
```

### "Command not recognized"
```
# Verify UCI mode
uci
# Should respond with: id name, id author, option, uciok

# If not: engine not in UCI mode
# Kill and restart process
```

### Engine hangs on `go` command
```
# Stop the search
stop

# Verify position is set
position startpos

# Try simpler search
go depth 5

# If still hangs: may be infinite loop, restart
```

### Invalid move errors
```
# Check position is loaded correctly
position startpos
# Verify moves are legal format: e2e4 (lowercase)

# Check promotion moves: e7e8q (lowercase queen)
position startpos moves e2e4 e7e5 g1f3 g8f6 f1c4 f8c5 d1h5 e8f7
# This should work with proper handling
```

---

## 🔗 Integration Examples

### With Python

```python
import subprocess

# Start engine
engine = subprocess.Popen(
    ['./chess_engine_uci.exe'],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    text=True
)

# Send command
engine.stdin.write('uci\n')
engine.stdin.flush()

# Read response
while True:
    line = engine.stdout.readline()
    if 'uciok' in line:
        break
    print(line.strip())
```

### With Chess GUI

1. **PyChess**: Add engine in settings
2. **Chess Arena**: Configure UCI engine path
3. **Lichess CLI**: Point to executable
4. **Chess.com**: Upload engine for analysis

---

## 📈 Performance Benchmarks

### Typical Search Times (on modern hardware)

| Depth | Time | Notes |
|-------|------|-------|
| 10 | 100-500ms | Quick analysis |
| 15 | 2-5 seconds | Blitz games |
| 20 | 10-30 seconds | Longer games |
| 25 | 1-3 minutes | Deep analysis |

### Memory Usage

| Hash | RAM Used | Typical Use |
|------|----------|-------------|
| 256 MB | ~300 MB | Casual play |
| 512 MB | ~550 MB | Standard |
| 1024 MB | ~1.1 GB | Strong play |
| 2048 MB | ~2.1 GB | Deep analysis |

---

## 📚 Additional Resources

### Documentation
- `PHASE6_WRAPUP.md` - Complete overview
- `PHASE6E_UCI_REPORT.md` - UCI protocol details
- `PROJECT_INDEX.md` - Full project structure

### References
- [UCI Protocol Spec](http://wbec-ridderkerk.nl/html/UCIProtocol.html)
- [Chess.com API](https://www.chess.com/news/view/published-data-api)
- [Lichess API](https://lichess.org/api)

---

## 🎓 Learning Resources

### Understanding MCTS
- Monte Carlo Tree Search (Wikipedia)
- UCB1 exploration/exploitation balance
- Threat-aware playouts for better moves

### Chess Programming
- Move generation algorithms
- Position evaluation
- Transposition tables
- Time management

### C++ Optimization
- Template specialization
- Memory allocation patterns
- Cache-friendly coding
- Performance profiling

---

## ✅ Verification Checklist

Before deploying to production:

- [ ] Engine compiles with 0 errors
- [ ] `uci` command returns proper identification
- [ ] `position startpos` loads correctly
- [ ] `go depth 10` returns valid move
- [ ] `isready` returns `readyok`
- [ ] FEN position loading works
- [ ] Move sequences parse correctly
- [ ] Engine exits cleanly on `quit`

---

## 🎯 Next Steps

### Immediate
1. Run the engine: `chess_engine_uci.exe`
2. Send `uci` to verify
3. Load position with `position startpos`
4. Calculate move with `go depth 15`

### For Integration
1. Point GUI to executable
2. Verify UCI connection
3. Play test game
4. Monitor performance

### For Development
1. See `PHASE6_COMPLETE_SUMMARY.md` for architecture
2. See `PHASE6E_UCI_REPORT.md` for protocol details
3. Review cpp/src for implementation
4. Run tests with `chess_engine_test.exe`

---

**Chess Engine v1.0 - Ready for Production Use**

For detailed information, see comprehensive documentation in `files/` directory.

# Search benchmarks

Measured 2026-11-12 on Windows x64, Dart SDK 3.13.4, JIT (`dart run`). Single runs, so expect a few percent of noise.

## How to run

```shell
dart run benchmark/search_benchmark.dart [maxDepth] [secondsPerPosition]
```

`maxDepth` is the depth argument to `rootMovesSearch`; plies searched = `maxDepth + 1`, plus quiescence. Each position runs iterative deepening from scratch (`resetSearchState()`), and the time limit is checked only between iterations. Nodes count every `negamax` and `qsearch` call.

The script also runs perft (leaf-node count) through `generate_moves()`, to time legal move generation on its own.

| Position | FEN |
|---|---|
| start | `rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1` |
| italian | `r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4` |
| kiwipete | `r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1` |
| endgame | `8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1` |

## Current engine

Features: material + piece/square tables, negamax alpha-beta, quiescence search, iterative deepening, move ordering (PV move, SEE-filtered MVV-LVA captures, killers), SEE pruning in quiescence, Zobrist hashing with hash-based repetition detection, pin-based legal move generation.

`dart run benchmark/search_benchmark.dart 3 60` (time and nodes are cumulative across iterations):

| Position | Plies | Best | Score | Nodes | Time (ms) | NPS |
|---|---|---|---|---|---|---|
| start | 1 | Nc3 | 50 | 40 | 9 | 4444 |
| start | 2 | Nc3 | 0 | 138 | 19 | 7263 |
| start | 3 | Nc3 | 50 | 1171 | 34 | 34441 |
| start | 4 | Nc3 | 0 | 3594 | 68 | 52852 |
| italian | 1 | Nc3 | 20 | 86 | 2 | 43000 |
| italian | 2 | Nc3 | 0 | 387 | 12 | 32250 |
| italian | 3 | Nc3 | 10 | 3533 | 28 | 126178 |
| italian | 4 | Nc3 | -5 | 12722 | 73 | 174273 |
| kiwipete | 1 | Bxa6 | 60 | 2303 | 17 | 135470 |
| kiwipete | 2 | Bxa6 | 60 | 4490 | 26 | 172692 |
| kiwipete | 3 | Bxa6 | 35 | 14454 | 57 | 253578 |
| kiwipete | 4 | Bxa6 | 35 | 42165 | 166 | 254006 |
| endgame | 1 | Rxf4+ | 90 | 36 | 0 | - |
| endgame | 2 | Rxf4+ | 90 | 140 | 0 | - |
| endgame | 3 | Rxf4+ | 110 | 798 | 1 | 798000 |
| endgame | 4 | Rxf4+ | 90 | 2177 | 4 | 544250 |

Total: 60,658 nodes in 311 ms (195,041 NPS).

The `start` rows run first and include JIT warm-up, so they're the noisiest.

| Perft (legal movegen) | Depth | Nodes | Time (ms) | NPS |
|---|---|---|---|---|
| start | 4 | 197281 | 16 | 12330062 |
| kiwipete | 3 | 97862 | 8 | 12232750 |
| endgame | 5 | 674624 | 103 | 6549747 |

### Benchmark totals by change

Same command; node counts are identical in every row, so only time changed.

| Change | Total time (ms) | NPS | Kiwipete 4 plies (ms) |
|---|---|---|---|
| Before Zobrist (FEN-replay repetition, `in_checkmate`/`in_draw` per node) | 2,379 | 25,497 | 1,801 |
| + Zobrist repetition, mate/stalemate from move list | 536 | 113,167 | 381 |
| + pin-based legality, outward-scan `attacked()` | 311 | 195,041 | 166 |

A rerun of the Zobrist version just before the movegen change measured 454 ms, which gives a sense of run-to-run noise.

### Legal move generation

Micro-benchmark on Kiwipete (48 legal moves), time per call:

| | Before | After |
|---|---|---|
| `generate_moves()` (legal) | 11,749 ns | 2,084 ns |
| `generate_moves({'legal': false})` | 2,053 ns | 1,976 ns |
| `in_check` | 120 ns | 75 ns |

Perft through `generate_moves()`, before → after: start depth 4 54 → 16 ms, kiwipete depth 3 24 → 8 ms, endgame depth 5 131 → 103 ms.

## History

These were measured before the benchmark script existed, by running `dart lib/src/search.dart` (8 self-play moves, 3 plies each) and reading the per-move timing. Node counts weren't tracked then. The last two moves are the most expensive, so they're the comparison points:

| Change | `e3` (White, move 7) | `e6` (Black, move 8) |
|---|---|---|
| Iterative deepening, no move ordering | 4,154 ms | 7,891 ms |
| + move ordering (PV, MVV-LVA, killers) | 205 ms | 238 ms |
| + SEE (ordering and qsearch pruning) | 113 ms | 133 ms |
| + Zobrist repetition, mate/stalemate from move list | 11 ms | 12 ms |

All four versions chose the same moves with the same scores. The Zobrist gain is larger here than in the benchmark because self-play positions carry game history, which the old repetition check replayed at every node.

## Known bottlenecks

Per-call costs on Kiwipete after the movegen change:

- SEE: about 620 ns per capture. It runs on every capture during ordering and again as the qsearch filter, so a node with 8 captures spends about 5 µs, more than move generation.
- `insufficient_material`: about 1.4 µs at every node; it scans the board and allocates a map.
- `eval`: about 380 ns; a full board scan rather than incremental updates.

# Search algorithm experiments

Measured 2026-11-12 on Windows x64 (16 logical cores), Dart SDK 3.13.4, JIT. Speed history of the baseline engine is in [benchmarks.md](benchmarks.md).

## Summary

Every variant below was played against the same alpha-beta engine at 100 ms per move.

| Engine (vs alpha-beta) | Games | Result | Score | Elo diff | Avg depth, engine vs alpha-beta |
|---|---|---|---|---|---|
| **Selective PVS** | 112 | +55 =39 −18 | **66.5%** | **+119** (95%: +68 to +175) | 6.29 vs 4.82 |
| MTD(f) root | 112 | +44 =31 −37 | 53.1% | +22 | 4.31 vs 4.41 |
| PVS + aspiration, no selectivity | 112 | +42 =28 −42 | 50.0% | 0 | 4.52 vs 4.44 |
| MCTS root (UCB), best-score pick | 112 | +32 =41 −39 | 46.9% | −22 | 4.90 vs 4.61* |
| SSS* at min nodes | 112 | +35 =33 −44 | 46.0% | −28 | 4.69 vs 4.81 |
| Best Node Search root | 112 | +38 =27 −47 | 46.0% | −28 | 5.60 vs 4.79* |
| SSS* at max nodes | 112 | +31 =33 −48 | 42.4% | −53 | 4.39 vs 4.71 |
| BNS with MCTS guesses | 112 | +28 =33 −51 | 39.7% | −73 (95%: −129 to −19) | — |
| MCTS root (UCB), most-pulled pick | 112 | +25 =36 −51 | 38.4% | −82 (95%: −138 to −30) | 5.01 vs 4.62* |
| Negamax max / MCTS min (vs alpha-beta *without* TT) | 120 | +1 =1 −118 | ~2% | ≈ −640 to −760 | — |
| Pure MCTS, quiet-move playout depth (4 configurations) | 448 + 16 | +0 =0 −464 | 0% | — | — |

\* Not comparable; see the notes for each engine.

With 112 games the 95% interval is roughly ±70 Elo. Only selective PVS (better), and BNS with MCTS guesses and MCTS root with most-pulled pick (worse), are clearly outside zero. Scores of individual 16-game batches ranged from 28% to 91%, so single batches mean little.

**Conclusion:** every variant that proves the exact minimax value (SSS*, MTD(f), BNS, plain PVS) ends up within noise of alpha-beta with a transposition table, because they search essentially the same tree. The only clear gain came from searching a *smaller* tree: selective PVS reaches about 1.5 plies deeper and wins by about +119 Elo.

## Setup

[experiments/tournament.dart](../experiments/tournament.dart):

```shell
dart run experiments/tournament.dart <engine> [pairs] [msPerMove] [seed] [maxPlies] [concurrency]
```

- **Opponent:** `iterativeDeepening` in [search.dart](../lib/src/search.dart): fail-hard negamax, quiescence search with SEE, move ordering (PV, SEE-filtered MVV-LVA, killers), Zobrist repetition detection, and from the SSS* experiment onwards a transposition table.
- **Games:** 112 games per engine: 7 seeds (`1..7`) × 8 random 4-ply openings, each played twice with colours swapped. Both sides get 100 ms per move. Each game runs in its own isolate, 16 at a time, so 16 games take about 16 s.
- **Adjudication:** games still running at 160 plies are scored by static eval: more than 300 centipawns ahead wins, otherwise a draw.
- **Elo:** `−400·log10(1/score − 1)`.
- **Depth:** the average last completed depth per move. Each engine measures it its own way, and machine load changed it between runs (alpha-beta averaged 4.4 to 4.9 plies in different runs), so only compare depths within one row.

Correctness tests in [test/chess_engine_test.dart](../test/chess_engine_test.dart) check that each exact variant (SSS* at min or max nodes, MTD(f), PVS without selectivity) returns the same root score as alpha-beta at 1–4 or 1–5 plies. BNS variants are checked to pick a move whose full-window score equals alpha-beta's best.

## Findings by engine

### Negamax max / MCTS min ([mcts.dart](../lib/src/mcts.dart), `negamaxMctsSearch`)

Full-width negamax for the side to move. At opponent nodes, a stored UCB bandit picks replies (most forcing first, admitting more replies as the node is visited more), and the node's value is the lowest reply average. Played against alpha-beta *before* it had a transposition table:

| Samples per visit | Result (40 games) | Score |
|---|---|---|
| 4 | +0 =0 −40 | 0% |
| 8 | +0 =1 −39 | 1.3% (−759) |
| 16 | +1 =0 −39 | 2.5% (−636) |

It loses on depth. Time to reach a fixed depth:

| Plies | Alpha-beta, start | Hybrid, start | Alpha-beta, Italian | Hybrid, Italian |
|---|---|---|---|---|
| 4 | 13 ms | 81 ms | 62 ms | 986 ms |
| 5 | 50 ms | 2,098 ms | 274 ms | 36,147 ms |

Max nodes are searched without pruning, and each sample re-searches a full subtree. Alpha-beta with good move ordering already visits fewer positions per move pair than this sampling does.

### SSS* ([sss.dart](../lib/src/sss.dart), `negamaxSssSearch`)

SSS* run as MT-SSS* (Plaat et al.): repeated zero-width alpha-beta tests from the top of the window down, with bounds kept in a transposition table.

- **SSS* at min nodes:** before the baseline had a transposition table it scored 59.4% over 48 games (+66 Elo). Once the baseline got one, it fell to 46.0%. **The early edge came from the transposition table, not from SSS*.** Adding the baseline's table cut its benchmark node count by 16% (60,658 → 51,078) with identical moves and scores.
- **SSS* at max nodes (including the root):** 42.4%, and about 0.3 ply shallower. At max nodes, and the root in particular, good move ordering already makes alpha-beta cheap, while MT-SSS* needs several passes down from +∞.

### MTD(f) root (`mtdfAtRoot`)

The same zero-width tests, but starting from the previous depth's score. 53.1%, the only exact variant above 50% (within noise). Compared with SSS* at max nodes, the only change is the starting point, worth about 75 Elo: **the first guess matters most.** Below an MTD(f) root every search is zero-width, where MT-SSS* reduces to one alpha-beta pass, so this is standard MTD(f).

### Best Node Search root (`bnsAtRoot`)

Rutko's BNS: each pass tests every remaining root move against a guess and keeps only those that reach it. It stops when one move remains or the bounds meet. While a bound is still infinite, test values step outward by doubling amounts; after that, the default `nextGuess` formula applies.

46.0%. Its average depth (5.60) is inflated: in positions with one clearly best move, BNS finishes each depth almost for free and races deep. At a fixed depth it's slower in quiet positions:

| Position, 6 plies | Alpha-beta | MTD(f) | BNS |
|---|---|---|---|
| Start | 152 ms | 237 ms | 638 ms |
| Italian | 870 ms | 1,296 ms | 3,957 ms |
| Kiwipete | 2,128 ms | 1,965 ms | 1,998 ms |
| Endgame | 32 ms | 33 ms | 36 ms |

All three chose the same move every time. BNS only proves a lower bound on the best value, which makes a weak first guess for the next depth.

### BNS with MCTS guesses (`bnsMcts`)

A UCT search uses 25% of the move's time to estimate each root move's value, with leaves scored by quiescence search. BNS then puts each test value midway between the two highest estimates and updates the estimates from each zero-width result.

39.7%, clearly worse. The estimates do help BNS in some positions (Italian, 6 plies: 3,748 → 1,878 ms), but:
- **The MCTS phase is expensive in tactical positions:** 1,000 iterations took 2,197 ms on Kiwipete, because each leaf runs a capture search with no bounds to cut it short.
- **BNS stays slower than alpha-beta even with good estimates:** 1,878 vs 967 ms on the Italian.

### MCTS at the root, alpha-beta in the tree ([mcts_root.dart](../lib/src/mcts_root.dart), `mctsRootSearch`)

Each root move is a UCB arm. Pulling it deepens that move's alpha-beta search by one ply, and the reward is the score squashed to 0–1.

- **Most-pulled move as the final pick:** 38.4%.
- **Best latest score as the final pick:** 46.9%, about 60 Elo better.

The reported depth is only that of the chosen move, which UCB deepens most. The main costs:
- **Each pull pays full price:** every pull is a full-window search of one move, with no bound from the best move found so far.
- **Depths don't match:** scores from moves searched to different depths are compared directly.

### Selective PVS ([selective.dart](../lib/src/selective.dart), `selectiveSearch`)

Built from what the experiments above showed:

| Finding | Design choice |
|---|---|
| Exact variants can't search deeper than alpha-beta | Prune and reduce: search a smaller tree |
| Zero-width testing was the only thing that helped (MTD(f)) | PVS: full window for the expected best move, zero-width for the rest |
| The first guess matters (MTD(f) vs SSS* from +∞) | Aspiration windows around the previous depth's score |
| BNS's idea (rank moves before proving them) is sound, but MCTS statistics cost too much | History heuristic: move statistics almost free from cutoffs, used to drive late move reductions |
| Opponent-modelling hybrids failed | Null-move pruning: the cheapest opponent model |

Also: check extensions; and `make_null_move`/`undo_null_move` added to the vendored `Chess` class.

**Ablation:** the same engine with null move, late move reductions and check extensions switched off (PVS with aspiration windows only) scored exactly 50.0%, 0.08 ply deeper than alpha-beta. **The whole +119 Elo comes from the selective features.** Their individual shares haven't been measured.

Selective PVS's depth is nominal: reduced lines are searched shallower and checks are extended.

### Pure MCTS with quiet-move depth ([pure_mcts.dart](../lib/src/pure_mcts.dart), `pureMctsSearch`)

No alpha-beta anywhere: UCT in the tree, playouts at the leaves.

- **Playout rule:** only quiet moves spend the playout's depth budget (`quietDepth`); captures, en passant and promotions are free.
- **Playout policy:**
  - If a capture that doesn't lose material (SEE ≥ 0) or a promotion is available, play the best one by MVV-LVA.
  - Otherwise, once the budget is spent and the side isn't in check, stop and evaluate, so evaluated positions are quiet by construction.
  - Otherwise, pick a quiet move by softmax over its static gain. Evasions after the budget is spent are free.
- **Optional progressive widening:** each node considers only its first `1 + w·√visits` children, ordered by static gain.

| Configuration (vs alpha-beta, 100 ms/move unless noted) | Games | Result |
|---|---|---|
| quietDepth 0, plain UCT | 112 | +0 =0 −112 |
| quietDepth 2, plain UCT | 112 | +0 =0 −112 |
| quietDepth 4, plain UCT | 112 | +0 =0 −112 |
| quietDepth 2, widening 2 | 112 | +0 =0 −112 |
| quietDepth 2, widening 2, **1 s/move** | 16 | +0 =0 −16 (all by checkmate) |

The engine works: it beat a random player 9/10 and finds short mates. It loses to alpha-beta because:

- **Low throughput:** 300–2,000 iterations per 100 ms, so the most-visited line reaches only 2–3 plies. Every playout ply needs move generation and SEE, while alpha-beta covers about 100k positions in the same time.
- **Averaging misses refutations:** one refutation decides a chess position, but MCTS values are averages. Plain UCT must try every reply once before it can favour the refuting one. With about 500 iterations it rated `…Qxa2??` (queen taken by `Rxa2`) at +343. Progressive widening tries forcing replies first and corrects that one (`Qxa2` falls to −180, and `Qc6` is chosen), but in games the tree is still too shallow.
- **Longer playouts cost more than they help:** quietDepth 4 gives fewer iterations and noisier rewards. Playout length grows with quietDepth (Italian: 4.2 plies at 2, 7.9 at 4, 15.0 at 8).

The quiet-move depth rule does what it should: playouts extend through exchanges (Kiwipete averages 7 plies of captures even at quietDepth 0) and never evaluate in check. It doesn't fix MCTS's core weaknesses in chess.

## Opponent-model experiments (vs a random player)

From [experiments/vs_random.dart](../experiments/vs_random.dart): 100 games per row, seed 7, against a player that picks uniformly random legal moves. Every engine won every game by checkmate (the 1k-iteration UCT engine drew once), so these rows measure how quickly each engine mates.

| Engine | Plies | Avg plies to mate | Median | Time/move |
|---|---|---|---|---|
| Alpha-beta | 1 + qsearch | 39.0 | 37 | 2 ms |
| Alpha-beta | 2 + qsearch | 34.2 | 34 | 5 ms |
| Alpha-beta | 3 + qsearch | 31.8 | 31 | 16 ms |
| Alpha-beta | 4 + qsearch | 29.1 | 29 | 85 ms |
| Expectimax (mean over all replies) | 2 | 44.9 | 45 | 2 ms |
| Expectimax | 4 | 26.1 | 22 | 471 ms |
| Max/mean, 4 sampled replies ([mcts.dart](../lib/src/mcts.dart), `maxMeanSearch`) | 4 | 27.4 | 24 | 191 ms |
| Max/mean, 8 sampled replies | 4 | 26.4 | 22 | 459 ms |
| UCT player, 1k iterations (since removed) | — | 217.9 | 161 | 42 ms |

Modelling the opponent correctly helps when the model is right. Expectimax mates a random player faster than alpha-beta at the same depth (median 22 vs 29 plies). Sampling 4 replies instead of all of them gets close to full expectimax (median 24) at 2.5× less time per move. The UCT player won material but had trouble converting: its scores flatten once it's far ahead.

**Check evasions at leaves.** Expectimax and max/mean leaves come right after the random reply, with the engine to move. They originally used the static eval even when that reply gave check, which overrates checking captures the engine can simply take back. Leaves in check now score the best evasion (`bestEvasionEval` in [eval.dart](../lib/src/eval.dart)). Rerun with seed 7:

| Engine, 4 plies | Avg plies to mate | Median | Time/move |
|---|---|---|---|
| Expectimax | 26.1 → 26.6 | 22 → 22 | 471 → 869 ms |
| Max/mean, 4 sampled replies | 27.4 → 27.6 | 24 → 26 | 191 → 375 ms |

Mating speed didn't change measurably. The slower times come from the machine, not the change: unchanged 4-ply alpha-beta slowed by the same factor in that session (85 → 163 ms per move), and only 0.2–1.1% of 4-ply leaves are in check.

## Caveats and open questions

- **One time control:** all tournaments ran at 100 ms per move. Selective search usually gains more with more time.
- **Adjudication:** games still running at 160 plies are scored by static eval.
- **Ablations not done:** how much null move and late move reductions each contribute is unknown.
- **Search parameters untuned:** LMR thresholds, null-move reduction, aspiration width, the UCB exploration constant, and the MCTS time share are all first guesses.
- **Not attempted:** MCTS root with zero-width tests against the current best move, and BNS with a statistical guess built from the previous depth's search results.

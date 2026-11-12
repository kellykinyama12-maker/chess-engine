import 'dart:math';

import 'package:chess/chess.dart';

import 'eval.dart';
import 'search.dart'
    show
        Deadline,
        RootMove,
        SearchTimeout,
        isDrawn,
        mateScore,
        maxPly,
        mvvLva,
        orderMoves,
        resetSearchState,
        scoreFromTT,
        scoreToTT;
import 'see.dart';

const int _inf = 360000;

/// Bounds on a position's value at a given depth, from the side to move's view.
class _Entry {
  _Entry(this.depth);

  final int depth;
  int lower = -_inf;
  int upper = _inf;
  Move? best;
}

/// Depth of the last iteration [negamaxSssSearch] completed.
int sssDepthReached = 0;

/// UCT tree node; [total] sums rewards in [0, 1] for the player who moved into it.
class _UctNode {
  _UctNode(this.moves) : children = List.filled(moves.length, null);

  final List<Move> moves;
  final List<_UctNode?> children;
  double? terminal;
  int visits = 0;
  double total = 0;
}

int _moveKey(Move m) => (m.from * 128 + m.to) * 8 + (m.promotion?.shift ?? 7);

double _toReward(num centipawns) => 1 / (1 + exp(-centipawns / 400));

double _toCentipawns(double reward) {
  final p = reward.clamp(0.001, 0.999);
  return 400 * log(p / (1 - p));
}

/// Hybrid search: alpha-beta negamax for one player, SSS* for the other.
///
/// The side to move at the root is the max player. By default its nodes use fail-soft
/// alpha-beta and the opponent's (min) nodes use SSS*; [sssAtMaxNodes] swaps the two,
/// including at the root. SSS* is run as MT-SSS* (Plaat et al.): start from the window's
/// upper bound and repeat zero-width alpha-beta tests, each lowering the upper bound, until
/// the value is pinned or falls below the window. A transposition table holds the bounds
/// between tests, which is what makes this equivalent to SSS*'s best-first expansion.
/// Leaves use a fail-soft quiescence search. Scores are centipawns from the root side's
/// view. Deepens one ply at a time; a depth cut off by [timeLimit] is discarded.
///
/// With SSS* at the root only the best move's value is proven, so the result then holds
/// just that move; otherwise it holds every root move, best first.
///
/// [mtdfAtRoot] replaces the root search with MTD(f): the same zero-width tests, but
/// starting from the previous depth's score instead of the top of the window. Below such a
/// root every search is zero-width, where MT-SSS* is a single alpha-beta pass, so
/// [sssAtMaxNodes] then has no effect. The result holds just the best move.
///
/// [bnsAtRoot] replaces the root search with Best Node Search (Rutko, 2011): each pass
/// tests every remaining root move against a guess with a zero-width search, keeps only
/// the moves that reach it, and stops when one move is left or the bounds meet. The
/// result holds just the best move, scored with a proven lower bound on its value.
///
/// [bnsMcts] runs BNS with a statistical guess function fed by MCTS. First a UCT search
/// from the root (leaves scored by quiescence search) spends [mctsFraction] of
/// [timeLimit], or [mctsIterations] iterations without one, estimating each root move's
/// value. BNS then places each test between the two best-estimated candidates, aiming to
/// leave one move above it, and replaces each candidate's estimate with the bound its
/// zero-width search returned. Estimates carry over between depths.
List<RootMove> negamaxSssSearch(
  Chess position,
  int maxDepth, {
  Duration? timeLimit,
  bool sssAtMaxNodes = false,
  bool mtdfAtRoot = false,
  bool bnsAtRoot = false,
  bool bnsMcts = false,
  double mctsFraction = 0.25,
  int mctsIterations = 1000,
}) {
  final me = position.turn;
  final deadline = Deadline(timeLimit);
  final historyLength = position.history.length;
  final tt = <int, _Entry>{};
  resetSearchState();

  late int Function(int depth, int alpha, int beta, int ply) search;

  int quiesce(int alpha, int beta, int ply) {
    deadline.check();
    if (position.in_check) return search(1, alpha, beta, ply);
    if (isDrawn(position)) return 0;

    var best = eval(position, position.turn);
    if (best >= beta) return best;
    if (best > alpha) alpha = best;

    final captures =
        position
            .generate_moves()
            .where((m) => m.captured != null && see(position, m) >= 0)
            .toList()
          ..sort((a, b) => mvvLva(b).compareTo(mvvLva(a)));
    for (final move in captures) {
      position.make_move(move);
      final score = -quiesce(-beta, -alpha, ply + 1);
      position.undo_move();
      if (score > best) {
        best = score;
        if (score >= beta) return score;
        if (score > alpha) alpha = score;
      }
    }
    return best;
  }

  void store(int depth, int value, int alpha, int beta, Move? best, int ply) {
    var e = tt[position.zobrist];
    if (e == null || e.depth < depth) {
      e = tt[position.zobrist] = _Entry(depth);
    } else if (e.depth > depth) {
      return;
    }
    final v = scoreToTT(value, ply);
    if (value <= alpha) {
      if (v < e.upper) e.upper = v;
    } else if (value >= beta) {
      if (v > e.lower) e.lower = v;
    } else {
      e.lower = e.upper = v;
    }
    if (best != null) e.best = best;
  }

  /// Fail-soft alpha-beta over [moves], with the TT move first.
  int alphaBeta(List<Move> moves, int depth, int alpha, int beta, int ply) {
    final alphaOrig = alpha;
    var best = -_inf;
    Move? bestMove;
    for (final move in orderMoves(
      position,
      moves,
      ply,
      tt[position.zobrist]?.best,
    )) {
      position.make_move(move);
      final score = -search(depth - 1, -beta, -alpha, ply + 1);
      position.undo_move();
      if (score > best) {
        best = score;
        bestMove = move;
        if (score >= beta) break;
        if (score > alpha) alpha = score;
      }
    }
    store(depth, best, alphaOrig, beta, bestMove, ply);
    return best;
  }

  /// MT-SSS* bounded by the window. Each zero-width test either proves the value is at
  /// least gamma (so it equals gamma) or returns a lower upper bound.
  int mtSss(List<Move> moves, int depth, int alpha, int beta, int ply) {
    var g = beta;
    while (true) {
      final gamma = g;
      g = alphaBeta(moves, depth, gamma - 1, gamma, ply);
      if (g >= gamma || g <= alpha) return g;
    }
  }

  /// MTD(f) at the root from [guess]; returns the value and the move that proved it.
  (int, Move) mtdf(List<Move> moves, int depth, int guess) {
    var g = guess, lower = -_inf, upper = _inf;
    Move? best;
    while (lower < upper) {
      final beta = g == lower ? g + 1 : g;
      g = alphaBeta(moves, depth, beta - 1, beta, 0);
      if (g < beta) {
        upper = g;
      } else {
        lower = g;
        best = tt[position.zobrist]!.best;
      }
    }
    return (g, best!);
  }

  /// Best Node Search at the root, first testing [guess]. With [estimates], tests are
  /// chosen from them instead (see [bnsMcts]) and they're updated in place. Returns a
  /// lower bound on the best value and the best move.
  (int, Move) bns(
    List<Move> moves,
    int depth,
    int guess,
    Move? previousBest, [
    Map<int, double>? estimates,
  ]) {
    double est(Move m) => estimates?[_moveKey(m)] ?? -_inf.toDouble();

    // The value is known to lie in [lo, hi).
    var lo = -_inf, hi = _inf;
    var candidates = orderMoves(position, moves, 0, previousBest);
    var step = 50;
    var first = true;
    if (estimates != null) {
      candidates.sort((a, b) => est(b).compareTo(est(a)));
    }
    var best = candidates.first;

    while (candidates.length > 1 && hi - lo >= 2) {
      // Midway between the top two estimates, so ideally only one move passes.
      final split = estimates == null
          ? null
          : ((est(candidates[0]) + est(candidates[1])) / 2).ceil();
      int test;
      if (split != null && split > lo && split < hi) {
        test = split;
      } else if (first && estimates == null) {
        test = guess;
      } else if (hi == _inf) {
        // Unbounded above: step up from the lower bound by doubling amounts.
        test = lo + step;
        step *= 2;
      } else if (lo == -_inf) {
        test = hi - step;
        step *= 2;
      } else {
        final n = candidates.length;
        test = lo + (hi - lo) * (n - 1) ~/ n;
      }
      first = false;
      test = test.clamp(lo + 1, hi - 1);

      final better = <Move>[];
      for (final move in candidates) {
        position.make_move(move);
        final score = -search(depth - 1, -test, -(test - 1), 1);
        position.undo_move();
        estimates?[_moveKey(move)] = score.toDouble();
        if (score >= test) better.add(move);
      }
      if (better.isEmpty) {
        hi = test;
      } else {
        lo = test;
        candidates = better;
      }
      if (estimates != null) {
        candidates.sort((a, b) => est(b).compareTo(est(a)));
      }
      if (better.isNotEmpty) best = candidates.first;
    }
    return (lo, best);
  }

  /// UCT from the root; returns centipawn estimates of the root moves, keyed by [_moveKey].
  Map<int, double> mctsEstimates() {
    final clock = Stopwatch()..start();
    final budget = timeLimit == null ? null : timeLimit * mctsFraction;
    final root = _UctNode(orderMoves(position, position.generate_moves(), 0));

    for (
      var i = 0;
      budget == null ? i < mctsIterations : clock.elapsed < budget;
      i++
    ) {
      final path = <_UctNode>[root];
      var node = root;
      double value; // For the side to move at the last node on the path.

      while (true) {
        if (node.terminal != null) {
          value = node.terminal!;
          break;
        }
        var pick = node.children.indexOf(null);
        if (pick < 0) {
          final logN = log(node.visits);
          var bestUcb = double.negativeInfinity;
          for (var c = 0; c < node.children.length; c++) {
            final child = node.children[c]!;
            final ucb =
                child.total / child.visits + 0.7 * sqrt(logN / child.visits);
            if (ucb > bestUcb) {
              bestUcb = ucb;
              pick = c;
            }
          }
        }
        position.make_move(node.moves[pick]);
        final ply = path.length;
        var child = node.children[pick];
        if (child == null) {
          final moves = position.generate_moves();
          child = node.children[pick] = _UctNode(
            moves.isEmpty || ply >= maxPly - 1
                ? const []
                : orderMoves(position, moves, ply),
          );
          path.add(child);
          if (isDrawn(position)) {
            value = child.terminal = 0.5;
          } else if (moves.isEmpty) {
            value = child.terminal = position.in_check ? 0.0 : 0.5;
          } else if (ply >= maxPly - 1) {
            value = child.terminal = _toReward(eval(position, position.turn));
          } else {
            value = _toReward(quiesce(-_inf, _inf, ply));
          }
          break;
        }
        node = child;
        path.add(node);
      }

      for (var k = 1; k < path.length; k++) {
        position.undo_move();
      }
      var reward = 1 - value;
      for (var k = path.length - 1; k >= 0; k--) {
        path[k].visits++;
        path[k].total += reward;
        reward = 1 - reward;
      }
    }

    return {
      for (var i = 0; i < root.moves.length; i++)
        if (root.children[i] case final c? when c.visits > 0)
          _moveKey(root.moves[i]): _toCentipawns(c.total / c.visits),
    };
  }

  search = (int depth, int alpha, int beta, int ply) {
    deadline.check();
    if (ply > 0 && isDrawn(position)) return 0;
    if (ply >= maxPly) return eval(position, position.turn);
    if (depth <= 0) return quiesce(alpha, beta, ply);

    final e = tt[position.zobrist];
    if (e != null && e.depth >= depth) {
      final lower = scoreFromTT(e.lower, ply);
      final upper = scoreFromTT(e.upper, ply);
      if (lower >= beta) return lower;
      if (upper <= alpha) return upper;
      if (lower == upper) return lower;
    }

    final moves = position.generate_moves();
    if (moves.isEmpty) return position.in_check ? -mateScore + ply : 0;

    final maxNode = position.turn == me;
    return maxNode == sssAtMaxNodes
        ? mtSss(moves, depth, alpha, beta, ply)
        : alphaBeta(moves, depth, alpha, beta, ply);
  };

  var result = <RootMove>[];
  final estimates = bnsMcts ? mctsEstimates() : null;
  for (var depth = 1; depth <= maxDepth; depth++) {
    deadline.armed = depth > 1;
    try {
      final moves = position.generate_moves();
      if (bnsAtRoot || bnsMcts) {
        final (value, best) = bns(
          moves,
          depth,
          result.isEmpty ? 0 : result[0].score,
          result.isEmpty ? null : result[0].move,
          estimates,
        );
        result = [RootMove(best, position.move_to_san(best), value)];
        sssDepthReached = depth;
        continue;
      }
      if (mtdfAtRoot) {
        final (value, best) = mtdf(
          moves,
          depth,
          result.isEmpty ? 0 : result[0].score,
        );
        result = [RootMove(best, position.move_to_san(best), value)];
        sssDepthReached = depth;
        continue;
      }
      if (sssAtMaxNodes) {
        final value = mtSss(moves, depth, -_inf, _inf, 0);
        final best = tt[position.zobrist]!.best!;
        result = [RootMove(best, position.move_to_san(best), value)];
        sssDepthReached = depth;
        continue;
      }
      final previousBest = result.isEmpty ? null : result[0].move;
      final ordered = orderMoves(position, moves, 0, previousBest);
      final scored = <(RootMove, int)>[];
      var alpha = -_inf;
      for (var i = 0; i < ordered.length; i++) {
        final move = ordered[i];
        final san = position.move_to_san(move);
        position.make_move(move);
        final score = -search(depth - 1, -_inf, -alpha, 1);
        position.undo_move();
        scored.add((RootMove(move, san, score), i));
        if (score > alpha) alpha = score;
      }
      // Ties keep search order: once alpha is raised, later moves are only upper bounds.
      scored.sort((a, b) {
        final c = b.$1.score.compareTo(a.$1.score);
        return c != 0 ? c : a.$2.compareTo(b.$2);
      });
      result = [for (final s in scored) s.$1];
      sssDepthReached = depth;
    } on SearchTimeout {
      while (position.history.length > historyLength) {
        position.undo_move();
      }
      break;
    }
  }
  return result;
}

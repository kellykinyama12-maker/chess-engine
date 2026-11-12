import 'dart:math';

import 'package:chess/chess.dart';

import 'eval.dart';
import 'qsearch.dart';
import 'search.dart'
    show
        Deadline,
        RootMove,
        SearchTimeout,
        isDrawn,
        mateScore,
        resetSearchState;

/// Running mean over the replies sampled so far at one opponent node.
class _MeanNode {
  _MeanNode(this.replies);

  /// Shuffled once, then consumed in order: sampling without replacement.
  final List<Move> replies;
  int sampled = 0;
  double sum = 0;
}

/// Max/mean search against an opponent that plays uniformly random moves.
///
/// The engine's (max) nodes search every move, as in negamax. The opponent's (mean)
/// nodes are sampled MCTS-style: each visit adds [samples] more random replies to a
/// stored running mean, so the tree grows by `b * samples` per move pair instead of `b * b`.
/// Each of the [iterations] passes over the root refines every stored mean further.
/// [depth] counts engine-move/random-reply pairs; leaves always come after a reply.
/// With [samples] at least the branching factor this equals `expectimaxSearch`.
List<RootMove> maxMeanSearch(
  Chess position,
  int depth, {
  int samples = 4,
  int iterations = 1,
  Random? rng,
}) {
  final me = position.turn;
  final random = rng ?? Random();
  // One table per remaining depth, so estimates at different horizons don't mix.
  final tables = List.generate(depth + 1, (_) => <int, _MeanNode>{});

  double search(int depth, int ply) {
    if (ply > 0 && isDrawn(position)) return 0;

    if (position.turn == me) {
      final moves = position.generate_moves();
      if (moves.isEmpty)
        return position.in_check ? -(mateScore - ply).toDouble() : 0;
      var best = double.negativeInfinity;
      for (final move in moves) {
        position.make_move(move);
        final value = search(depth, ply + 1);
        position.undo_move();
        if (value > best) best = value;
      }
      return best;
    }

    final node = tables[depth].putIfAbsent(
      position.zobrist,
      () => _MeanNode(position.generate_moves()..shuffle(random)),
    );
    if (node.replies.isEmpty)
      return position.in_check ? (mateScore - ply).toDouble() : 0;

    final base = depth <= 1 ? eval(position, Color.WHITE) : 0;
    final sign = me == Color.WHITE ? 1 : -1;
    final end = min(node.sampled + samples, node.replies.length);
    for (; node.sampled < end; node.sampled++) {
      final reply = node.replies[node.sampled];
      position.make_move(reply);
      final double value;
      if (depth <= 1) {
        // In check, the static eval is unreliable; score the best evasion instead.
        final evasion = position.in_check
            ? bestEvasionEval(position)
            : base + evalDelta(reply);
        value = evasion == null
            ? -(mateScore - ply - 1).toDouble()
            : sign * evasion.toDouble();
      } else {
        value = search(depth - 1, ply + 1);
      }
      position.undo_move();
      node.sum += value;
    }
    return node.sum / node.sampled;
  }

  final moves = position.generate_moves();
  final values = List<double>.filled(moves.length, 0);
  for (var pass = 0; pass < iterations; pass++) {
    for (var i = 0; i < moves.length; i++) {
      position.make_move(moves[i]);
      values[i] = search(depth, 1);
      position.undo_move();
    }
  }

  final scored = [
    for (var i = 0; i < moves.length; i++)
      (
        RootMove(moves[i], position.move_to_san(moves[i]), values[i].round()),
        values[i],
      ),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final s in scored) s.$1];
}

/// Per-reply statistics at one stored min-player node.
class _MinNode {
  _MinNode(this.replies)
    : visits = List.filled(replies.length, 0),
      sums = List.filled(replies.length, 0.0);

  /// Ordered by the opponent's static gain, so widening admits forcing replies first.
  final List<Move> replies;
  final List<int> visits;
  final List<double> sums;
  int total = 0;
}

/// Hybrid search: full-width negamax for the max player, MCTS for the min player.
///
/// The side to move at the root is the max player; at its nodes every move is searched.
/// At the opponent's (min) nodes, stored per position and depth, each visit runs
/// [samples] MCTS descents: a reply is chosen by a lower confidence bound (the reply
/// most likely to be worst for us), among the first `1 + widening * sqrt(visits)` replies
/// in static order (progressive widening). A min node's value is the lowest mean among
/// its visited replies. Leaves use quiescence search. Scores are centipawns from the root
/// side's view. Deepens one ply at a time; a depth cut off by [timeLimit] is discarded.
/// With [samples] at least the branching factor and [widening] large, min nodes see every
/// reply and the result equals plain minimax.
List<RootMove> negamaxMctsSearch(
  Chess position,
  int maxDepth, {
  Duration? timeLimit,
  int samples = 4,
  double widening = 2,
  double exploration = 100,
}) {
  final me = position.turn;
  final them = me == Color.WHITE ? Color.BLACK : Color.WHITE;
  final themSign = them == Color.WHITE ? 1 : -1;
  final deadline = Deadline(timeLimit);
  final historyLength = position.history.length;
  resetSearchState();

  late List<Map<int, _MinNode>> tables;

  double search(int depth, int ply) {
    deadline.check();
    if (ply > 0 && isDrawn(position)) return 0;
    final maxPlayer = position.turn == me;

    if (depth <= 0) {
      final q = qsearch(position, 0, -360000, 360000, ply: ply).toDouble();
      return maxPlayer ? q : -q;
    }

    if (maxPlayer) {
      final moves = position.generate_moves();
      if (moves.isEmpty)
        return position.in_check ? -(mateScore - ply).toDouble() : 0;
      var best = double.negativeInfinity;
      for (final move in moves) {
        position.make_move(move);
        final value = search(depth - 1, ply + 1);
        position.undo_move();
        if (value > best) best = value;
      }
      return best;
    }

    // Min player: MCTS over stored reply statistics, one table per remaining depth.
    final node = tables[depth].putIfAbsent(position.zobrist, () {
      final replies = position.generate_moves()
        ..sort((a, b) => themSign * (evalDelta(b) - evalDelta(a)));
      return _MinNode(replies);
    });
    if (node.replies.isEmpty)
      return position.in_check ? (mateScore - ply).toDouble() : 0;

    for (var s = 0; s < samples; s++) {
      final allowed = min(
        node.replies.length,
        1 + (widening * sqrt(node.total)).floor(),
      );
      var pick = node.visits.indexOf(0);
      if (pick < 0 || pick >= allowed) {
        final logTotal = log(node.total);
        var bestBound = double.infinity;
        for (var i = 0; i < allowed; i++) {
          final bound =
              node.sums[i] / node.visits[i] -
              exploration * sqrt(logTotal / node.visits[i]);
          if (bound < bestBound) {
            bestBound = bound;
            pick = i;
          }
        }
      }
      position.make_move(node.replies[pick]);
      final value = search(depth - 1, ply + 1);
      position.undo_move();
      node.visits[pick]++;
      node.sums[pick] += value;
      node.total++;
    }

    var value = double.infinity;
    for (var i = 0; i < node.replies.length; i++) {
      if (node.visits[i] > 0) value = min(value, node.sums[i] / node.visits[i]);
    }
    return value;
  }

  var result = <RootMove>[];
  for (var depth = 1; depth <= maxDepth; depth++) {
    deadline.armed = depth > 1;
    tables = List.generate(depth, (_) => <int, _MinNode>{});
    try {
      final scored = <(RootMove, double)>[];
      for (final move in position.generate_moves()) {
        final san = position.move_to_san(move);
        position.make_move(move);
        final value = search(depth - 1, 1);
        position.undo_move();
        scored.add((RootMove(move, san, value.round()), value));
      }
      scored.sort((a, b) => b.$2.compareTo(a.$2));
      result = [for (final s in scored) s.$1];
    } on SearchTimeout {
      while (position.history.length > historyLength) {
        position.undo_move();
      }
      break;
    }
  }
  return result;
}

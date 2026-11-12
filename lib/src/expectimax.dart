import 'package:chess/chess.dart';

import 'eval.dart';
import 'search.dart' show Deadline, RootMove, SearchTimeout, isDrawn, mateScore;

/// Expectimax against an opponent that plays uniformly random legal moves.
///
/// [depth] counts move pairs: each engine move is followed by the average over all
/// random replies, so the tree is `2 * depth` plies and every leaf comes after a reply.
/// Scores are from the side to move at the root. There are no alpha-beta cutoffs:
/// averaged replies can't be refuted by a single one.
/// Deepens one pair at a time; a depth cut off by [timeLimit] is discarded.
List<RootMove> expectimaxSearch(
  Chess position,
  int depth, {
  Duration? timeLimit,
}) {
  final me = position.turn;
  final deadline = Deadline(timeLimit);
  final historyLength = position.history.length;
  var result = <RootMove>[];

  for (var d = 1; d <= depth; d++) {
    deadline.armed = d > 1;
    try {
      final scored = <(RootMove, double)>[];
      for (final move in position.generate_moves()) {
        final san = position.move_to_san(move);
        position.make_move(move);
        final value = _chance(position, me, d, 1, deadline);
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

double _max(Chess position, Color me, int depth, int ply, Deadline deadline) {
  deadline.check();
  if (isDrawn(position)) return 0;
  final moves = position.generate_moves();
  if (moves.isEmpty)
    return position.in_check ? -(mateScore - ply).toDouble() : 0;

  var best = double.negativeInfinity;
  for (final move in moves) {
    position.make_move(move);
    final value = _chance(position, me, depth, ply + 1, deadline);
    position.undo_move();
    if (value > best) best = value;
  }
  return best;
}

double _chance(
  Chess position,
  Color me,
  int depth,
  int ply,
  Deadline deadline,
) {
  deadline.check();
  if (isDrawn(position)) return 0;
  final moves = position.generate_moves();
  if (moves.isEmpty)
    return position.in_check ? (mateScore - ply).toDouble() : 0;

  var sum = 0.0;
  if (depth <= 1) {
    // Leaves: one board scan here, then each reply's eval is this plus its delta.
    final base = eval(position, Color.WHITE);
    final sign = me == Color.WHITE ? 1 : -1;
    for (final move in moves) {
      position.make_move(move);
      // In check, the static eval is unreliable; score the best evasion instead.
      final evasion = position.in_check
          ? bestEvasionEval(position)
          : base + evalDelta(move);
      position.undo_move();
      sum += evasion == null ? -(mateScore - ply - 1) : sign * evasion;
    }
    return sum / moves.length;
  }

  for (final move in moves) {
    position.make_move(move);
    sum += _max(position, me, depth - 1, ply + 1, deadline);
    position.undo_move();
  }
  return sum / moves.length;
}

import 'dart:math';

import 'package:chess/chess.dart';

import 'eval.dart';
import 'search.dart' show RootMove, isDrawn, mvvLva;
import 'see.dart';

/// Stats from the last [pureMctsSearch].
({int iterations, int treeDepth}) pureMctsStats = (iterations: 0, treeDepth: 0);

class _Node {
  _Node(this.moves) : children = List.filled(moves.length, null);

  final List<Move> moves;
  final List<_Node?> children;

  /// Fixed reward for finished games, for the side to move at this node.
  double? terminal;
  int visits = 0;

  /// Sum of rewards for the player who moved into this node.
  double total = 0;
}

bool _noisy(Move m) => m.captured != null || m.promotion != null;

double _reward(int centipawns) => 1 / (1 + exp(-centipawns / 400));

/// One playout from [position], restoring it afterwards. Returns the reward in [0, 1]
/// for the side to move at the start, plus how many plies and quiet moves it used.
///
/// Only quiet moves spend [quietDepth]: captures (including en passant) and promotions
/// are free. A capture that doesn't lose material by SEE, or a promotion, is always
/// played (best by MVV-LVA) if available. Otherwise, once the budget is spent and the
/// side to move isn't in check, the playout stops and the position is evaluated, so it
/// is quiet by construction. Otherwise a quiet move is drawn by softmax over its static
/// gain at [temperature] centipawns; evasions after the budget is spent are free.
({double reward, int plies, int quietMoves}) quietRollout(
  Chess position,
  int quietDepth,
  Random rng, {
  double temperature = 50,
  int maxPlies = 200,
}) {
  final start = position.turn;
  var budget = quietDepth;
  var plies = 0;
  var quietMoves = 0;
  double? result; // For the side to move when the playout stopped.

  while (plies < maxPlies) {
    if (plies > 0 && isDrawn(position)) {
      result = 0.5;
      break;
    }
    final moves = position.generate_moves();
    final inCheck = position.in_check;
    if (moves.isEmpty) {
      result = inCheck ? 0 : 0.5;
      break;
    }

    Move? best;
    var bestScore = -1;
    for (final m in moves) {
      if (!_noisy(m)) continue;
      if (m.captured != null && see(position, m) < 0) continue;
      final score = m.captured != null ? mvvLva(m) : 50;
      if (score > bestScore) {
        bestScore = score;
        best = m;
      }
    }

    if (best == null) {
      if (budget <= 0 && !inCheck) break;
      final quiet = moves.where((m) => !_noisy(m)).toList();
      final pool = quiet.isEmpty ? moves : quiet;
      final sign = position.turn == Color.WHITE ? 1 : -1;
      final weights = [
        for (final m in pool) exp(sign * evalDelta(m) / temperature),
      ];
      var r = rng.nextDouble() * weights.reduce((a, b) => a + b);
      var i = 0;
      while (i < pool.length - 1 && (r -= weights[i]) > 0) {
        i++;
      }
      best = pool[i];
      if (!_noisy(best) && budget > 0) {
        budget--;
        quietMoves++;
      }
    }

    position.make_move(best);
    plies++;
  }

  result ??= _reward(eval(position, position.turn));
  final flip = position.turn != start;
  for (var k = 0; k < plies; k++) {
    position.undo_move();
  }
  return (
    reward: flip ? 1 - result : result,
    plies: plies,
    quietMoves: quietMoves,
  );
}

/// Pure Monte Carlo tree search: UCT in the tree, [quietRollout] playouts at the leaves,
/// no alpha-beta anywhere.
///
/// Each iteration expands one node (children tried best-first by static gain) and runs one
/// playout with a budget of [quietDepth] quiet moves. Runs until [timeLimit], or for
/// [iterations] without one. Returns the root moves, most visited first, each scored in
/// centipawns from its mean reward.
///
/// With [widening] set, each node only considers its first `1 + widening * sqrt(visits)`
/// children in static order (progressive widening), so forcing replies such as recaptures
/// are tried first and revisited instead of being averaged away among every legal reply.
/// Null considers every child, as in plain UCT.
List<RootMove> pureMctsSearch(
  Chess position, {
  Duration? timeLimit,
  int iterations = 10000,
  int quietDepth = 4,
  double exploration = 0.7,
  double? widening = 2,
  Random? rng,
}) {
  final random = rng ?? Random();
  final clock = Stopwatch()..start();

  List<Move> ordered(List<Move> moves) {
    final sign = position.turn == Color.WHITE ? 1 : -1;
    return moves..sort((a, b) => sign * (evalDelta(b) - evalDelta(a)));
  }

  final root = _Node(ordered(position.generate_moves()));
  var done = 0;
  while (timeLimit == null ? done < iterations : clock.elapsed < timeLimit) {
    final path = <_Node>[root];
    var node = root;
    double value; // For the side to move at the last node on the path.

    while (true) {
      if (node.terminal != null) {
        value = node.terminal!;
        break;
      }
      final allowed = widening == null
          ? node.children.length
          : min(
              node.children.length,
              1 + (widening * sqrt(node.visits)).floor(),
            );
      var pick = node.children.indexOf(null);
      if (pick < 0 || pick >= allowed) {
        final logN = log(node.visits);
        var bestUcb = double.negativeInfinity;
        for (var c = 0; c < allowed; c++) {
          final child = node.children[c]!;
          final ucb =
              child.total / child.visits +
              exploration * sqrt(logN / child.visits);
          if (ucb > bestUcb) {
            bestUcb = ucb;
            pick = c;
          }
        }
      }
      position.make_move(node.moves[pick]);
      var child = node.children[pick];
      if (child == null) {
        final moves = position.generate_moves();
        child = node.children[pick] = _Node(ordered(moves));
        path.add(child);
        if (isDrawn(position)) {
          value = child.terminal = 0.5;
        } else if (moves.isEmpty) {
          value = child.terminal = position.in_check ? 0.0 : 0.5;
        } else {
          value = quietRollout(position, quietDepth, random).reward;
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
    done++;
  }

  var treeDepth = 0;
  for (var n = root; ; treeDepth++) {
    _Node? next;
    for (final c in n.children) {
      if (c != null && (next == null || c.visits > next.visits)) next = c;
    }
    if (next == null) break;
    n = next;
  }
  pureMctsStats = (iterations: done, treeDepth: treeDepth);

  final scored = [
    for (var i = 0; i < root.moves.length; i++)
      if (root.children[i] case final c? when c.visits > 0)
        (root.moves[i], c.visits, c.total / c.visits),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  return [
    for (final (move, _, mean) in scored)
      RootMove(
        move,
        position.move_to_san(move),
        (400 * log(mean.clamp(0.001, 0.999) / (1 - mean.clamp(0.001, 0.999))))
            .round(),
      ),
  ];
}

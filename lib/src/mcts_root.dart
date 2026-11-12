import 'dart:math';

import 'package:chess/chess.dart';

import 'search.dart';

/// Search depth (plies) of the move [mctsRootSearch] last chose.
int mctsRootDepthReached = 0;

class _Arm {
  _Arm(this.root);

  final RootMove root;
  int depth = 0;
  int visits = 0;
  double total = 0;
  int last = 0;

  double get mean => total / visits;
}

/// MCTS at the root, alpha-beta in the tree.
///
/// Each root move is a bandit arm. Pulling an arm deepens that move's alpha-beta search
/// ([rootMovesSearch] on just that move, sharing one transposition table) by one ply; the
/// reward is the new score squashed to [0, 1]. UCB1 with [exploration] picks the arm, so
/// promising moves are searched deeper than the rest. Every move is first searched to one
/// ply. Pulls stop at [timeLimit], or after [maxPulls] without one; an interrupted pull is
/// discarded. At the end the move with the best latest alpha-beta score is played (ties go
/// to the deeper search).
List<RootMove> mctsRootSearch(
  Chess position, {
  Duration? timeLimit,
  int maxPulls = 200,
  double exploration = 0.1,
  int maxDepth = 64,
}) {
  resetSearchState();
  startSearchClock(null);
  final arms = [
    for (final m in position.generate_moves())
      _Arm(RootMove(m, position.move_to_san(m), 0)),
  ];

  bool pull(_Arm arm) {
    final scored = rootMovesSearch(position, arm.depth, [arm.root]);
    if (searchStopped) return false;
    arm
      ..depth += 1
      ..visits += 1
      ..last = scored[0].score
      ..total += 1 / (1 + exp(-scored[0].score / 400));
    return true;
  }

  bool won(_Arm a) => isMateScore(a.last) && a.last > 0;
  bool lost(_Arm a) => isMateScore(a.last) && a.last < 0;

  for (final arm in arms) {
    pull(arm);
  }

  startSearchClock(timeLimit);
  var pulls = 0;
  while (!arms.any(won) &&
      (timeLimit == null ? pulls < maxPulls : searchElapsed < timeLimit)) {
    final open = arms.where((a) => a.depth < maxDepth && !lost(a)).toList();
    if (open.isEmpty) break;
    final logN = log(arms.fold(0, (s, a) => s + a.visits));
    final arm = open.reduce(
      (a, b) =>
          a.mean + exploration * sqrt(logN / a.visits) >=
              b.mean + exploration * sqrt(logN / b.visits)
          ? a
          : b,
    );
    if (!pull(arm)) break;
    pulls++;
  }
  startSearchClock(null);

  final chosen = arms.reduce(
    (a, b) =>
        a.last > b.last || (a.last == b.last && a.depth >= b.depth) ? a : b,
  );
  mctsRootDepthReached = chosen.depth;
  return [RootMove(chosen.root.move, chosen.root.san, chosen.last)];
}

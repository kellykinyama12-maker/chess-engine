import 'package:chess/chess.dart';

import 'mcts_alphabeta.dart';
import 'mcts_new.dart';

/// Alpha-beta node type of the child a root move leads to, which fixes what its score means:
/// [pv] exact (searched inside the window), [cut] upper bound (the move failed low: the child
/// found a refutation), [all] lower bound (the move failed high).
enum NodeType { pv, cut, all }

class PriorMove {
  PriorMove(this.move, this.san, this.score, this.type);

  final Move move;
  final String san;
  int score;
  NodeType type;
}

const int _inf = 360000;

/// PVS over the root moves in the given order with fail-soft [negamaxTactical]: the first
/// move and any move that beats alpha get exact ([NodeType.pv]) scores; the rest fail low
/// and keep their upper bound ([NodeType.cut]).
List<PriorMove> _searchRoot(Chess position, int depth, List<PriorMove> moves) {
  final result = <PriorMove>[];
  var alpha = -_inf;
  for (var i = 0; i < moves.length; i++) {
    final m = moves[i];
    position.move(m.move);
    int score;
    if (i == 0) {
      score = -negamaxTactical(position, depth, -_inf, _inf, ply: 1);
    } else {
      score = -negamaxTactical(position, depth, -alpha - 1, -alpha, ply: 1);
      if (score > alpha) {
        score = -negamaxTactical(position, depth, -_inf, -alpha, ply: 1);
      }
    }
    position.undo_move();
    if (searchStopped) break;
    final exact = i == 0 || score > alpha;
    result.add(PriorMove(m.move, m.san, score, exact ? NodeType.pv : NodeType.cut));
    if (score > alpha) alpha = score;
  }
  final order = {for (var i = 0; i < result.length; i++) result[i]: i};
  return result
    ..sort((a, b) {
      final c = b.score.compareTo(a.score);
      return c != 0 ? c : order[a]!.compareTo(order[b]!);
    });
}

/// Iterative deepening over [_searchRoot]; depth 0 always completes and a depth cut short
/// by [timeLimit] is discarded.
List<PriorMove> searchPriors(Chess position, int maxDepth, {Duration? timeLimit}) {
  var moves = [
    for (final m in orderMoves(position, position.moves({'asObjects': true}) as List<Move>, 0))
      PriorMove(m, position.move_to_san(m), 0, NodeType.pv),
  ];
  if (moves.isEmpty) return moves;
  final sw = Stopwatch()..start();
  for (var depth = 0; depth <= maxDepth; depth++) {
    resetSearchState();
    startSearchClock(depth == 0 || timeLimit == null ? null : timeLimit - sw.elapsed);
    final result = _searchRoot(position, depth, moves);
    if (searchStopped) break;
    moves = result;
  }
  startSearchClock(null);
  return moves;
}

class TypedEdge extends Edge {
  TypedEdge(super.move, super.prior, this.type);

  NodeType type;
}

/// [MonteCarlo] whose edge priors carry their alpha-beta node type. Exact values found deeper
/// in the tree replace their parents' priors outright (and make them exact); bounds are only
/// blended in at [priorLearningRate]. Runs the prior search in this isolate ([priorPool] is
/// not used).
class TypedMonteCarlo extends MonteCarlo {
  @override
  Future<Reward> expandNode() async {
    final s = currentNode();
    for (final p in searchPriors(position, 16, timeLimit: priorTimeLimit)) {
      s.children.add(TypedEdge(p.move, valueToReward(p.score), p.type));
    }
    s.nodeVisits = 1;
    return s.children.isEmpty ? 0.0 : s.children[0].prior;
  }

  /// A node's value is exact if its best prior is exact: every bound below it is an upper
  /// bound, so no other child can be better.
  bool _exactValue(Node node) {
    final best = bestChild(node, EdgeStatistic.prior);
    return best == null || (best as TypedEdge).type == NodeType.pv;
  }

  @override
  void backup(Reward reward) {
    var childBest = reward;
    var childExact = (ply > 0 && isDrawn(position)) || _exactValue(currentNode());
    while (ply > 0) {
      undoMove();
      reward = 1.0 - reward;
      final edge = edges[ply]! as TypedEdge;
      final target = 1.0 - childBest;
      if (childExact) {
        edge.prior = target;
        edge.type = NodeType.pv;
      } else {
        edge.prior += priorLearningRate * (target - edge.prior);
      }
      edge.actionValue += reward;
      edge.meanActionValue = edge.actionValue / edge.visits;

      final node = currentNode();
      childBest = bestChild(node, EdgeStatistic.prior)!.prior;
      childExact = _exactValue(node);
      final minimax = bestChild(node, EdgeStatistic.mean)!.meanActionValue;
      reward = reward * (1.0 - backupMinimax) + minimax * backupMinimax;
    }
  }
}

import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:chess/chess.dart';

import 'mcts_alphabeta.dart';
import 'mcts_new.dart';

/// Alpha-beta node type of a move's score: [pv] exact (searched inside the window), [all] upper
/// bound (the move failed low), [cut] lower bound (the move failed high).
enum NodeType { pv, all, cut }

class PriorMove {
  PriorMove(this.move, this.san, this.score, this.type);

  final Move move;
  final String san;
  int score;
  NodeType type;
}

const int _inf = 360000;

/// Full-width fail-soft alpha-beta: every move is searched, then quiescence. Unlike the
/// selective [negamaxTactical], quiet moves are not cut to quiescence; at expected ALL nodes
/// (zero window) late quiet moves are instead searched [lateMoveReduction] plies shallower,
/// and re-searched at full depth if they beat alpha.
int _negamax(Chess position, int depth, int alpha, int beta, int ply) {
  if (searchStopped) return 0;
  if (ply > 0 && isDrawn(position)) return 0;
  if (depth <= 0 || ply >= maxPly - 1) {
    return qsearch(position, 0, alpha, beta, ply: ply);
  }
  final moves = position.moves({'asObjects': true}) as List<Move>;
  final inCheck = position.in_check;
  if (moves.isEmpty) return inCheck ? -mateScore + ply : 0;

  final allNode = beta - alpha == 1;
  var best = -_inf;
  var index = 0;
  for (final move in orderMoves(position, moves, ply)) {
    final quiet = move.captured == null && move.promotion == null;
    position.move(move);
    final reduce = lateMoveReduction &&
        allNode &&
        quiet &&
        !inCheck &&
        !position.in_check &&
        depth >= 3 &&
        index >= 3;
    var score = -_negamax(
      position,
      depth - 1 - (reduce ? (index >= 6 ? 2 : 1) : 0),
      -beta,
      -alpha,
      ply + 1,
    );
    if (reduce && score > alpha) {
      score = -_negamax(position, depth - 1, -beta, -alpha, ply + 1);
    }
    position.undo_move();
    index++;
    if (searchStopped) return 0;
    if (score > best) best = score;
    if (score >= beta) return score;
    if (score > alpha) alpha = score;
  }
  return best;
}

/// Late move reductions in [_negamax] at zero-window (expected ALL) nodes.
bool lateMoveReduction = true;

/// PVS over the root moves in the given order with fail-soft [_negamax]: the first
/// move and any move that beats alpha get exact ([NodeType.pv]) scores; the rest fail low
/// and keep their upper bound ([NodeType.all]).
List<PriorMove> _searchRoot(Chess position, int depth, List<PriorMove> moves) {
  final result = <PriorMove>[];
  var alpha = -_inf;
  for (var i = 0; i < moves.length; i++) {
    final m = moves[i];
    position.move(m.move);
    int score;
    if (i == 0) {
      score = -_negamax(position, depth, -_inf, _inf, 1);
    } else {
      score = -_negamax(position, depth, -alpha - 1, -alpha, 1);
      if (score > alpha) {
        score = -_negamax(position, depth, -_inf, -alpha, 1);
      }
    }
    position.undo_move();
    if (searchStopped) break;
    final exact = i == 0 || score > alpha;
    result.add(PriorMove(m.move, m.san, score, exact ? NodeType.pv : NodeType.all));
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

/// Multi-isolate [searchPriors]: each depth deals the root moves round-robin to long-lived
/// workers. Node types stay valid per share: a move that beats its share's alpha is exact,
/// one that fails low is an upper bound.
class TypedPriorPool {
  TypedPriorPool._(this._workers);

  final List<_TypedWorker> _workers;

  static Future<TypedPriorPool> spawn(int workers) async => TypedPriorPool._(
    await Future.wait([for (var i = 0; i < workers; i++) _TypedWorker.spawn()]),
  );

  Future<List<PriorMove>> searchPriors(
    Chess position,
    int maxDepth, {
    Duration? timeLimit,
  }) async {
    final end = timeLimit == null
        ? null
        : DateTime.now().microsecondsSinceEpoch + timeLimit.inMicroseconds;
    var moves = [
      for (final m in orderMoves(position, position.moves({'asObjects': true}) as List<Move>, 0))
        PriorMove(m, position.move_to_san(m), 0, NodeType.pv),
    ];
    if (moves.isEmpty) return moves;

    for (var depth = 0; depth <= maxDepth; depth++) {
      final shares = List.generate(_workers.length, (_) => <PriorMove>[]);
      for (var i = 0; i < moves.length; i++) {
        shares[i % shares.length].add(moves[i]);
      }
      final results = await Future.wait([
        for (var w = 0; w < _workers.length; w++)
          if (shares[w].isNotEmpty)
            _workers[w].search(position, depth, shares[w], depth == 0 ? null : end),
      ]);
      if (results.any((r) => r == null)) break;

      final order = {for (var i = 0; i < moves.length; i++) moves[i].san: i};
      moves = [for (final r in results) ...r!]
        ..sort((a, b) {
          final c = b.score.compareTo(a.score);
          return c != 0 ? c : order[a.san]!.compareTo(order[b.san]!);
        });
    }
    return moves;
  }

  void close() {
    for (final w in _workers) {
      w.close();
    }
  }
}

class _TypedWorker {
  _TypedWorker._(this._commands, this._responses);

  final SendPort _commands;
  final ReceivePort _responses;
  final List<Completer<List<PriorMove>?>> _pending = [];

  static Future<_TypedWorker> spawn() async {
    final responses = ReceivePort();
    final ready = Completer<SendPort>();
    _TypedWorker? worker;
    responses.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
      } else {
        worker!._pending.removeAt(0).complete(message as List<PriorMove>?);
      }
    });
    await Isolate.spawn(_typedWorkerMain, responses.sendPort);
    return worker = _TypedWorker._(await ready.future, responses);
  }

  /// Null if the deadline (microseconds since epoch) cut the search short.
  Future<List<PriorMove>?> search(
    Chess position,
    int depth,
    List<PriorMove> moves,
    int? deadline,
  ) {
    final completer = Completer<List<PriorMove>?>();
    _pending.add(completer);
    _commands.send((position, depth, moves, deadline));
    return completer.future;
  }

  void close() {
    _commands.send(null);
    _responses.close();
  }
}

void _typedWorkerMain(SendPort replies) {
  final commands = ReceivePort();
  replies.send(commands.sendPort);
  commands.listen((message) {
    if (message == null) {
      commands.close();
      return;
    }
    final (Chess position, int depth, List<PriorMove> moves, int? deadline) =
        message as (Chess, int, List<PriorMove>, int?);
    resetSearchState();
    startSearchClock(
      deadline == null
          ? null
          : Duration(
              microseconds: max(0, deadline - DateTime.now().microsecondsSinceEpoch),
            ),
    );
    final result = _searchRoot(position, depth, moves);
    final stopped = searchStopped;
    startSearchClock(null);
    replies.send(stopped ? null : result);
  });
}

class TypedEdge extends Edge {
  TypedEdge(super.move, super.prior, this.type);

  NodeType type;
}

/// [MonteCarlo] whose edge priors carry their alpha-beta node type. Simulations only go where
/// the decision can change: an ALL node whose upper bound beats the best PV prior is searched
/// until it is exact (promoted to PV), and when none is left the PV line is deepened. Exact
/// values replace their parents' priors outright (and make them exact); bounds are only
/// blended in at [priorLearningRate]. Prior searches use [typedPool] if set, otherwise run
/// in this isolate ([priorPool] is not used).
class TypedMonteCarlo extends MonteCarlo {
  TypedPriorPool? typedPool;

  /// Best PV edge, and the best ALL edge if its bound beats it (null otherwise).
  (TypedEdge?, TypedEdge?) _pvAndChallenger(Node node) {
    TypedEdge? pv;
    TypedEdge? all;
    for (final e in node.children.cast<TypedEdge>()) {
      if (e.type == NodeType.pv) {
        if (pv == null || e.prior > pv.prior) pv = e;
      } else if (all == null || e.prior > all.prior) {
        all = e;
      }
    }
    return (pv, all != null && (pv == null || all.prior > pv.prior) ? all : null);
  }

  @override
  void treePolicy() {
    while (currentNode().nodeVisits > 0 &&
        currentNode().children.isNotEmpty &&
        ply < maxPly - 2 &&
        !(ply > 0 && isDrawn(position))) {
      final s = currentNode();
      final (pv, challenger) = _pvAndChallenger(s);
      final edge = challenger ?? pv!;
      s.nodeVisits++;
      edge.visits++;
      edges[ply] = edge;
      doMove(edge);
      ply++;
    }
  }

  /// Exact moves first (best prior first), then unresolved ALL nodes, whose bounds may be
  /// above their true values.
  @override
  List<RootMove> emitPv() {
    final moves = super.emitPv();
    final root = currentNode().children.cast<TypedEdge>();
    bool exact(RootMove r) =>
        root.firstWhere((e) => sameMove(r.move, e.move)).type == NodeType.pv;
    return [...moves.where(exact), ...moves.where((r) => !exact(r))];
  }

  @override
  Future<Reward> expandNode() async {
    final s = currentNode();
    final priors = typedPool == null
        ? searchPriors(position, 16, timeLimit: priorTimeLimit)
        : await typedPool!.searchPriors(position, 16, timeLimit: priorTimeLimit);
    for (final p in priors) {
      s.children.add(TypedEdge(p.move, valueToReward(p.score), p.type));
    }
    s.nodeVisits = 1;
    return s.children.isEmpty ? 0.0 : s.children[0].prior;
  }

  /// A node's value is exact if no ALL node's upper bound beats its best PV prior.
  bool _exactValue(Node node) {
    if (node.children.isEmpty) return true;
    final (pv, challenger) = _pvAndChallenger(node);
    return pv != null && challenger == null;
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

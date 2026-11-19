import 'dart:io';
import 'dart:math';

import 'package:chess/chess.dart';

import 'mcts_alphabeta.dart';

typedef Reward = double;

enum EdgeStatistic { ucb, visits, mean, prior }

class MultiHashMap {
  int size = 32;

  Map<int, List<Node>> buckets = {};
  // List<Map<int, Node>> buckets = [];

  Node insert(Node node) {
    final position = node.key % size;
    if (buckets[position] == null) {
      buckets[position] = [];
      buckets[position]!.add(node);
      final partBucket = buckets[position]!;
      return partBucket[0];
    } else {
      buckets[position]!.add(node);
      final partBucket = buckets[position]!;
      return partBucket[partBucket.length - 1];
    }
  }

  List<Node>? getNodesList(int zobrist) {
    final position = zobrist % size;
    return buckets[position];
  }

  void clear() {
    buckets = {};
  }
}
// typedef MultiHashMap=List<Map<int,Node>>;

class Edge {
  Move move;
  Reward prior;
  Reward actionValue = 0;
  Reward meanActionValue = 0;
  int visits = 0;

  Edge(this.move, this.prior);
  @override
  String toString() {
    // TODO: implement toString
    return "Edge( move: $move)";
  }
}

class Node {
  int key;
  int nodeVisits = 0;
  List<Edge> children = [];
  Node(this.key);
}

Node getNode(Chess position) {
  // throw UnimplementedError("tree policy not implemented");
  final it = mctsTree.getNodesList(position.zobrist);

  if (it != null) {
    for (Node itr in it) {
      if (itr.key == position.zobrist) return itr;
    }
  }

  return mctsTree.insert(Node(position.zobrist));
}

MultiHashMap mctsTree = MultiHashMap();

class MonteCarlo {
  Chess position = Chess();

  /// Multi-isolate prior search; null runs [iterativeDeepening] in this isolate.
  PriorPool? priorPool;

  Future<Node> createRoot() async {
    // print("Creating root");
    ply = 0;
    nodes = List.filled(128, Node(0));
    mctsTree.clear();
    numOfSimulations = 0;
    Node s = nodes[ply] = getNode(position);
    // Node s = nodes[ply];
    await expandNode();
    return s;
  }

  void doMove(Edge edge) {
    // print("Move: ${edge.move} at ply: $ply, turn: ${position.turn}");
    // edges[ply] = Edge(edge.move,edge.prior);
    // edges[ply] =  edge;
    if (position.move(edge.move) == false) throw Exception("Wrong move");

    // print("Edges: ${currentNode().children}");
    // ply++;
  }

  void undoMove() {
    ply--;
    // print("Move: ${edges[ply]!.move} at ply: $ply, turn: ${position.turn}");

    if (position.undo_move() == null) throw Exception("Move cannot be null");
  }

  void treePolicy() {
    // print("Entering tree policy");
    while (currentNode().nodeVisits > 0 &&
        currentNode().children.isNotEmpty &&
        ply < maxPly - 2 &&
        !(ply > 0 && isDrawn(position))) {
      Node s = currentNode();
      if (s.key == 0) throw Exception("key cannot be ${s.key}");
      Edge ucbEdge = bestChild(s, EdgeStatistic.ucb)!;
      s.nodeVisits++;
      ucbEdge.visits++;

      edges[ply] = ucbEdge;

      // if(m==null) throw Exception("Move is null");
      // print("Move: $m");
      doMove(ucbEdge);
      ply++;
    }
  }

  // Defaults from MonteCarlo::default_parameters() in snicolet/Stockfish (montecarlo branch).
  double backupMinimax = 1.0;
  double ucbUnexpandedNode = 0.5;
  double exploration = 0.7;
  double ucbLossesAvoidance = 1.0;
  double ucbLogTermFactor = 0.0;
  bool ucbUseFatherVisits = true;

  /// Use the backed-up prior instead of the mean reward as the UCB value term.
  bool ucbUsePrior = true;

  /// MonteCarlo::UCB(): mean value (or [ucbUnexpandedNode]) plus a prior-weighted exploration term.
  double ucb(Node node, Edge edge) {
    final fatherVisits = node.nodeVisits;
    var result = ucbUsePrior
        ? edge.prior
        : edge.visits > 0
        ? edge.meanActionValue
        : ucbUnexpandedNode;
    final c = ucbUseFatherVisits ? exploration * sqrt(fatherVisits) : exploration;
    final losses = edge.visits - edge.actionValue;
    final divisor =
        losses * ucbLossesAvoidance + edge.visits * (1.0 - ucbLossesAvoidance);
    result += c * edge.prior / (1 + divisor);
    result += ucbLogTermFactor * sqrt(log(fatherVisits) / (1 + edge.visits));
    return result;
  }

  /// MonteCarlo::best_child(): first child with the highest [statistic]; null without children.
  Edge? bestChild(Node node, EdgeStatistic statistic) {
    Edge? best;
    var bestValue = double.negativeInfinity;
    for (final edge in node.children) {
      final r = switch (statistic) {
        EdgeStatistic.visits => edge.visits.toDouble(),
        EdgeStatistic.mean => edge.meanActionValue,
        EdgeStatistic.prior => edge.prior,
        EdgeStatistic.ucb => ucb(node, edge),
      };
      if (r > bestValue) {
        bestValue = r;
        best = edge;
      }
    }
    return best;
  }

  Future<Reward> playOutPolicy() async {
    if (ply > 0 && isDrawn(position)) return 0.5;
    if (ply >= maxPly - 2) return 0.5;
    // Already expanded but reached again: only terminal nodes stop the tree policy there.
    if (currentNode().nodeVisits > 0) return position.in_checkmate ? 0.0 : 0.5;
    final out = await expandNode();
    if (currentNode().children.isEmpty) return position.in_checkmate ? 0.0 : 0.5;
    return out;
  }

  /// MonteCarlo::backup(): [reward] is from the leaf's side to move. Each edge gets the
  /// reward from its mover's view; with [backupMinimax] = 1 the parent's best mean is
  /// propagated instead of the playout value.
  ///
  /// Priors are updated Q-learning style: P += [priorLearningRate] * (1 - max P' - P), where
  /// max P' is the best prior at the child node (the leaf's value for the leaf edge).
  void backup(Reward reward) {
    var childBest = reward;
    while (ply > 0) {
      undoMove();
      reward = 1.0 - reward;
      Edge edge = edges[ply]!;
      edge.prior += priorLearningRate * ((1.0 - childBest) - edge.prior);
      edge.actionValue += reward;
      edge.meanActionValue = edge.actionValue / edge.visits;
      final node = currentNode();
      childBest = bestChild(node, EdgeStatistic.prior)!.prior;
      final minimax = bestChild(node, EdgeStatistic.mean)!.meanActionValue;
      reward = reward * (1.0 - backupMinimax) + minimax * backupMinimax;
    }
  }

  /// Step size of the prior update in [backup]; 1.0 makes priors plain minimax values.
  double priorLearningRate = 0.5;

  List<Node> nodes = List.filled(128, Node(0));

  List<Edge?> edges = List.filled(128, null);
  int ply = 0;
  int numOfSimulations = 0;

  Node currentNode() {
    Node s = getNode(position);
    nodes[ply] = s;
    if (nodes[ply].key == 0) throw Exception("key cannot be ${nodes[ply].key}");
    return nodes[ply];
  }

  bool rootNode() {
    return ply == 0;
  }

  bool simulationBudget() {
    numOfSimulations++;
    if (timeLimit != null && _searchClock.elapsed >= timeLimit!) return false;
    return numOfSimulations < maxSimulations;
  }

  int maxSimulations = 200;

  /// Optional limit on the whole search; simulations stop at whichever of this and
  /// [maxSimulations] comes first.
  Duration? timeLimit;
  final Stopwatch _searchClock = Stopwatch();

  /// Per-expansion budget for the prior search (in addition to its depth limit of 4).
  Duration priorTimeLimit = const Duration(milliseconds: 150);

  Future<Reward> expandNode() async {
    Node s = currentNode();
    List<RootMove> moves = priorPool == null
        ? iterativeDeepening(position, 16, timeLimit: priorTimeLimit)
        : await priorPool!.iterativeDeepening(
            position,
            16,
            timeLimit: priorTimeLimit,
          );

    // List<RootMove> moves = alphabeta(position);
    // s.children = [];
    if (s.children.isNotEmpty) throw Exception("Children should be empty");
    for (RootMove m in moves) {
      s.children.add(Edge(m.move, valueToReward(m.score)));
    }
    if (s.nodeVisits > 0) {
      throw Exception("node visits should be 0. Got: ${s.nodeVisits}");
    }
    s.nodeVisits = 1;
    // print(moves);
    if (s.children.isNotEmpty) {
      return s.children[0].prior;
    } else {
      return 0.0;
    }
  }

  Future<void> simulate() async {
    _searchClock
      ..reset()
      ..start();
    await createRoot();

    while (simulationBudget()) {
      // print(position.fen);
      treePolicy();
      Reward r = await playOutPolicy();
      backup(r);
    }
    emitPv();
  }

  /// Principal variation of the last [emitPv], in SAN.
  List<String> pv = [];

  /// Rank root moves by their backed-up prior instead of Stockfish's robust choice.
  bool rankByPrior = true;

  /// MonteCarlo::emit_principal_variation(): root moves sorted by robust choice
  /// (10 * visits + prior), scored by their mean value; the PV follows the most visited
  /// child from the best root move.
  List<RootMove> emitPv() {
    final root = currentNode();
    final list = [...root.children]
      ..sort(
        (a, b) => rankByPrior
            ? b.prior.compareTo(a.prior)
            : (10 * b.visits + b.prior).compareTo(10 * a.visits + a.prior),
      );
    final rootMoves = [
      for (final edge in list)
        RootMove(
          edge.move,
          position.move_to_san(edge.move),
          rewardToValue(edge.meanActionValue),
        ),
    ];

    pv = [];
    if (rootMoves.isEmpty) return rootMoves;
    var move = rootMoves[0].move;
    var count = 0;
    while (true) {
      pv.add(position.move_to_san(move));
      position.move(move);
      count++;
      final node = getNode(position);
      if (node.children.isEmpty ||
          node.nodeVisits <= 0 ||
          isDrawn(position) ||
          count >= maxPly - 2) {
        break;
      }
      move = bestChild(node, EdgeStatistic.visits)!.move;
    }
    for (var i = 0; i < count; i++) {
      position.undo_move();
    }
    return rootMoves;
  }

  /// MonteCarlo::value_to_reward(): logistic scaled so that +600 cp gives 0.95.
  Reward valueToReward(int centipawns) {
    const k = -0.00490739829861;
    return 1.0 / (1 + exp(k * centipawns));
  }

  /// MonteCarlo::reward_to_value(): inverse of [valueToReward], ±10000 beyond 0.99 / 0.01.
  int rewardToValue(Reward r) {
    if (r > 0.99) return 10000;
    if (r < 0.01) return -10000;
    const g = 203.77396313709564;
    return (g * log(r / (1.0 - r))).toInt();
  }

  // int alphabeta() {
  //   throw UnimplementedError("tree policy not implemented");
  // }
}

Future<void> main() async {
  MonteCarlo monteCarlo = MonteCarlo()
    ..priorPool = await PriorPool.spawn(Platform.numberOfProcessors);

  // Chess chess = Chess();
  for (int x = 0; x < 250; x++) {
    if (monteCarlo.position.game_over) break;
    print('position:  ${monteCarlo.position.fen}');
    // print("Evaluation: ${eval(chess,chess.turn)}");
    // print('Zobrist: ${chess.}');
    print(monteCarlo.position.ascii);
    await monteCarlo.simulate();
    var moves = monteCarlo.emitPv();
    // var moves = iterativeDeepening(
    //   monteCarlo.position,
    //   20,
    //   timeLimit: const Duration(seconds: 10),
    // );
    // print("Moves: ${moves}");
    // moves.shuffle();
    final move = moves[0].move;
    monteCarlo.position.move(move);
    print('move: ${moves[0]} pv ${monteCarlo.pv.join(' ')}');
    //  print('move: ${chess.move_to_san(move)}');
  }
  monteCarlo.priorPool?.close();
}

// void main() {
//   MonteCarlo monteCarlo = MonteCarlo();

//   for (int ply = 0; ply < 10; ply++) {
//     monteCarlo.simulate();
//     // monteCarlo.expandNode();
//     final moves=monteCarlo.emitPv();
//     // print(monteCarlo.emitPv());
//         print('move: ${moves[0]}');
//     monteCarlo.position.move(moves[0].move);
//   }
// }

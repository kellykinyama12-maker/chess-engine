import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:chess/chess.dart';

import 'eval.dart';
import 'see.dart';

const int maxPly = 128;
const int mateScore = 40000;

final List<List<Move?>> _killers = List.generate(maxPly, (_) => [null, null]);
final List<int> _history = List.filled(2 * 128 * 128, 0);

bool sameMove(Move? a, Move b) =>
    a != null && a.from == b.from && a.to == b.to && a.promotion == b.promotion;

int _historyIndex(Move m) =>
    (m.color == Color.WHITE ? 0 : 128 * 128) + m.from * 128 + m.to;

int _moveScore(Chess position, Move move, int ply, Move? pvMove) {
  if (sameMove(pvMove, move)) return 1000000;
  int score = 0;
  if (move.captured != null) {
    // Losing captures go after quiet moves.
    score += see(position, move) >= 0
        ? 100000 + mvvLva(move)
        : -100000 + mvvLva(move);
  }
  if (move.promotion == PieceType.QUEEN) score += 95000;
  if (score != 0) return score;
  if (sameMove(_killers[ply][0], move)) return 90000;
  if (sameMove(_killers[ply][1], move)) return 80000;
  return _history[_historyIndex(move)].clamp(0, 79999);
}

void _storeKiller(Move move, int ply) {
  if (move.captured != null || sameMove(_killers[ply][0], move)) return;
  _killers[ply][1] = _killers[ply][0];
  _killers[ply][0] = move;
}

/// Order: PV move, winning/equal captures (MVV-LVA) and queen promotions, killers, quiet moves, losing captures.
List<Move> orderMoves(
  Chess position,
  List<Move> moves,
  int ply, [
  Move? pvMove,
]) {
  final scored = [
    for (final m in moves) (m, _moveScore(position, m, ply, pvMove)),
  ];
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final s in scored) s.$1];
}

final List<int> _truncatedAt = List.filled(maxPly + 1, _never);
const int _never = 1 << 30;

// Triangular PV table: _pv[ply] is the best line found from that ply.
// final List<List<Move>> _pv = List.generate(maxPly + 1, (_) => <Move>[]);

int negamaxTactical(
  Chess position,
  int depth,
  int alpha,
  int beta, {
  required int ply,
}) {
  if (_timeUp()) return 0;
  //  _pv[ply] = [];
  _truncatedAt[ply] = _never;

  if (ply > 0 && isDrawn(position)) {
    return 0;
  }
  if (ply >= maxPly) return eval(position, position.turn);
  if (depth <= 0) {
    return qsearch(position, depth, alpha, beta, ply: ply);
  }

  Move? bestMove;
  var best = -360000;
  final isEvasion = position.in_check;
  final moves = position.moves({'asObjects': true}) as List<Move>;
  if (moves.isEmpty) {
    return position.in_check ? -mateScore + ply : 0;
  }
  for (var move in orderMoves(
    position,
    moves,
    ply, // pvMove ?? entry?.move
  )) {
    bool isCaptureMove = position.is_capture(move);

    position.move(move);

    bool givesCheck = position.in_check;
    int score;
    final quiet = !givesCheck && !isCaptureMove && !isEvasion;
    if (quiet) {
      score = -qsearch(position, depth - 1, -beta, -alpha, ply: ply + 1);
    } else {
      score = -negamaxTactical(
        position,
        depth - 1,
        -beta,
        -alpha,
        ply: ply + 1,
      );
    }
    position.undo_move();
    if (_stopped) return 0;
    // A quiet move cut off before the horizon truncates the line; at the horizon it doesn't.
    // final line = quiet ? [move] : [move, ..._pv[ply + 1]];
    final truncatedAt = quiet
        ? (depth > 1 ? 0 : _never)
        : (_truncatedAt[ply + 1] == _never
              ? _never
              : _truncatedAt[ply + 1] + 1);
    if (score > best) best = score;
    if (score >= beta) {
      _storeKiller(move, ply);
      // _pv[ply] = line;
      _truncatedAt[ply] = truncatedAt;
      // _storeTacticalTT(
      //   position,
      //   depth,
      //   beta,
      //   _lowerBound,
      //   move,
      //   ply,
      //   truncatedAt,
      // );
      return score;
    }
    if (score > alpha) {
      alpha = score;
      bestMove = move;
      // _pv[ply] = line;
      _truncatedAt[ply] = truncatedAt;
    }
  }

  // Fail-soft: a fail-low returns the best score found, an upper bound tighter than alpha.
  return best;
}

final Map<PieceType, int> _orderValue = {
  PieceType.PAWN: 1,
  PieceType.KNIGHT: 2,
  PieceType.BISHOP: 3,
  PieceType.ROOK: 4,
  PieceType.QUEEN: 5,
  PieceType.KING: 6,
};

int mvvLva(Move move) =>
    _orderValue[move.captured]! * 10 - _orderValue[move.piece]!;

int qsearch(Chess position, int depth, int alpha, int beta, {int ply = 0}) {
  if (_timeUp()) return 0;
  if (position.in_check) {
    return negamaxTactical(position, 1, alpha, beta, ply: ply);
  }

  if (isDrawn(position)) {
    return 0;
  }

  int score = eval(position, position.turn);
  if (score >= beta) return score;
  var best = score;
  if (score > alpha) alpha = score;

  final captures =
      (position.moves({'asObjects': true}) as List<Move>)
          .where((m) => position.is_capture(m) && see(position, m) >= 0)
          .toList()
        ..sort((a, b) => mvvLva(b).compareTo(mvvLva(a)));
  for (var move in captures) {
    position.move(move);
    int score = -qsearch(position, depth - 1, -beta, -alpha, ply: ply + 1);
    position.undo_move();
    if (_stopped) return 0;

    if (score > best) best = score;
    if (score >= beta) return score;
    if (score > alpha) alpha = score;
  }

  return best;
}

/// Cheap draw test for search: any repetition, 50-move rule, or insufficient material.
/// Stalemate is detected from the generated move list in [negamax].
bool isDrawn(Chess position) =>
    position.half_moves >= 100 ||
    position.repetitions > 0 ||
    position.insufficient_material;

class RootMove {
  Move move;
  String san;
  int score;
  RootMove(this.move, this.san, this.score);

  @override
  String toString() {
    return "Rootmove(move: $move, score: $score)";
  }
}

/// Searches root moves in the order of [previous] (if given), best first.
List<RootMove> rootMovesSearch(
  Chess position,
  int depth, [
  List<RootMove>? previous,
]) {
  List<RootMove> rootMoves = [];
  int alpha = -360000;
  int beta = 360000;
  // _pv[0] = [];

  final moves =
      previous?.map((m) => m.move).toList() ??
      orderMoves(
        position,
        position.moves({'asObjects': true}) as List<Move>,
        0,
      );
  for (var i = 0; i < moves.length; i++) {
    final move = moves[i];
    final san = position.move_to_san(move);
    // The previous best is searched first, so only it follows the old PV.
    // _followPv = i == 0 && _prevPv.isNotEmpty && sameMove(_prevPv[0], move);
    // position.move(move);
    // Only the first root move needs a full window; the rest are tested against it.
    // int score = i == 0
    //     ? -negamaxTactical(position, depth, -360000, -alpha, ply: 1)
    //     : -negamaxTactical(position, depth, -(alpha + 1), -alpha, ply: 1);
    // if (i > 0 && score > alpha) {
    //   score = -negamaxTactical(position, depth, -360000, -alpha, ply: 1);
    // }

    // int score = -negamaxTactical(position, depth, -360000, -alpha, ply: 1);
    // Alpha-beta bounds at the root: moves after the best get fail-soft upper bounds as priors.
    position.move(move);
    int score = -negamaxTactical(position, depth, -beta, -alpha, ply: 1);
    position.undo_move();
    if (_stopped) break;

    // position.undo_move();
    // if (_stopped) break;
    final rm = RootMove(move, san, score);
    // print("Root move: $rm");
    rootMoves.add(rm);
    if (score > alpha) {
      alpha = score;
      // _pv[0] = [move, ..._pv[1]];
    }
  }
  // if (!_stopped) _prevPv = List.of(_pv[0]);

  // Ties keep search order: later moves are only upper bounds once alpha is raised.
  final order = {for (var i = 0; i < rootMoves.length; i++) rootMoves[i]: i};
  rootMoves.sort((a, b) {
    final c = b.score.compareTo(a.score);
    return c != 0 ? c : order[a]!.compareTo(order[b]!);
  });

  return rootMoves;
}

List<Move> _prevPv = [];
bool _followPv = false;

void resetSearchState() {
  // nodes = 0;
  // _stopped = false;
  // _timeLimit = null;
  _prevPv = [];
  _followPv = false;
  // _tt.clear();
  // _tacticalTT.clear();
  _history.fillRange(0, _history.length, 0);
  for (final k in _killers) {
    k[0] = null;
    k[1] = null;
  }
  // for (final line in _pv) {
  //   line.clear();
  // }
}

int depthReached = 0;
String _pvToSan(Chess position, List<Move> pv) {
  final copy = position.copy();
  return pv
      .map((m) {
        final san = copy.move_to_san(m);
        copy.move(m);
        return san;
      })
      .join(' ');
}

final Stopwatch _clock = Stopwatch();
Duration? _timeLimit;
bool _stopped = false;
int _nodes = 0;

/// Starts the clock polled by [negamaxTactical] and [qsearch]; a null [limit] means none.
void startSearchClock(Duration? limit) {
  _stopped = false;
  _nodes = 0;
  _timeLimit = limit;
  _clock
    ..reset()
    ..start();
}

/// True once the clock started by [startSearchClock] ran out.
bool get searchStopped => _stopped;

/// Polls the clock every 256 nodes; once over [_timeLimit] the search unwinds.
bool _timeUp() {
  if (!_stopped &&
      _timeLimit != null &&
      (++_nodes & 255) == 0 &&
      _clock.elapsed >= _timeLimit!) {
    _stopped = true;
  }
  return _stopped;
}

/// Deepens until [maxDepth] or [timeLimit]; depth 0 always completes, and a depth cut
/// short by the clock is discarded in favour of the last completed one.
List<RootMove> iterativeDeepening(
  Chess position,
  int maxDepth, {
  Duration? timeLimit,
  bool verbose = true,
}) {
  List<RootMove>? rootMoves;
  resetSearchState();
  _stopped = false;
  _nodes = 0;
  _clock
    ..reset()
    ..start();

  for (int depth = 0; depth <= maxDepth; depth++) {
    _timeLimit = depth == 0 ? null : timeLimit;
    final result = rootMovesSearch(position, depth, rootMoves);
    if (_stopped) break;
    // if (_stopped) {
    //   if (verbose) {
    //     print(
    //       'depth ${depth + 1}: stopped after ${_clock.elapsedMilliseconds} ms, using depth $depth',
    //     );
    //   }
    //   break;
    // }
    rootMoves = result;
    depthReached = depth + 1;
    // if (verbose) {
    // print(
    //   'depth ${depth + 1}: best ${rootMoves[0]} pv ${_pvToSan(position, _prevPv)} (${_clock.elapsedMilliseconds} ms)',
    // );
    // }
    // if (timeLimit != null && _clock.elapsed >= timeLimit) break;
    resetSearchState();
  }
  _timeLimit = null;

  return rootMoves!;
}

/// Multi-isolate [iterativeDeepening]: each depth splits the root moves round-robin over
/// long-lived worker isolates, each searching its share with its own alpha-beta window.
class PriorPool {
  PriorPool._(this._workers);

  final List<_Worker> _workers;

  static Future<PriorPool> spawn(int workers) async => PriorPool._(
    await Future.wait([for (var i = 0; i < workers; i++) _Worker.spawn()]),
  );

  /// Same contract as [iterativeDeepening]: depth 0 always completes, and a depth cut short
  /// by [timeLimit] in any worker is discarded.
  Future<List<RootMove>> iterativeDeepening(
    Chess position,
    int maxDepth, {
    Duration? timeLimit,
  }) async {
    final end = timeLimit == null
        ? null
        : DateTime.now().microsecondsSinceEpoch + timeLimit.inMicroseconds;
    var rootMoves = [
      for (final m in orderMoves(
        position,
        position.moves({'asObjects': true}) as List<Move>,
        0,
      ))
        RootMove(m, position.move_to_san(m), 0),
    ];
    if (rootMoves.isEmpty) return rootMoves;

    for (var depth = 0; depth <= maxDepth; depth++) {
      final shares = List.generate(_workers.length, (_) => <RootMove>[]);
      for (var i = 0; i < rootMoves.length; i++) {
        shares[i % shares.length].add(rootMoves[i]);
      }
      final results = await Future.wait([
        for (var w = 0; w < _workers.length; w++)
          if (shares[w].isNotEmpty)
            _workers[w].search(position, depth, shares[w], depth == 0 ? null : end),
      ]);
      if (results.any((r) => r == null)) break;

      final order = {for (var i = 0; i < rootMoves.length; i++) rootMoves[i].san: i};
      rootMoves = [for (final r in results) ...r!]
        ..sort((a, b) {
          final c = b.score.compareTo(a.score);
          return c != 0 ? c : order[a.san]!.compareTo(order[b.san]!);
        });
      depthReached = depth + 1;
    }
    return rootMoves;
  }

  void close() {
    for (final w in _workers) {
      w.close();
    }
  }
}

class _Worker {
  _Worker._(this._commands, this._responses);

  final SendPort _commands;
  final ReceivePort _responses;
  final List<Completer<List<RootMove>?>> _pending = [];

  static Future<_Worker> spawn() async {
    final responses = ReceivePort();
    final ready = Completer<SendPort>();
    _Worker? worker;
    responses.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
      } else {
        worker!._pending.removeAt(0).complete(message as List<RootMove>?);
      }
    });
    await Isolate.spawn(_workerMain, responses.sendPort);
    return worker = _Worker._(await ready.future, responses);
  }

  /// Null if the deadline (microseconds since epoch) cut the search short.
  Future<List<RootMove>?> search(
    Chess position,
    int depth,
    List<RootMove> moves,
    int? deadline,
  ) {
    final completer = Completer<List<RootMove>?>();
    _pending.add(completer);
    _commands.send((position, depth, moves, deadline));
    return completer.future;
  }

  void close() {
    _commands.send(null);
    _responses.close();
  }
}

void _workerMain(SendPort replies) {
  final commands = ReceivePort();
  replies.send(commands.sendPort);
  commands.listen((message) {
    if (message == null) {
      commands.close();
      return;
    }
    final (Chess position, int depth, List<RootMove> moves, int? deadline) =
        message as (Chess, int, List<RootMove>, int?);
    resetSearchState();
    _stopped = false;
    _nodes = 0;
    _clock
      ..reset()
      ..start();
    _timeLimit = deadline == null
        ? null
        : Duration(
            microseconds: max(0, deadline - DateTime.now().microsecondsSinceEpoch),
          );
    final result = rootMovesSearch(position, depth, moves);
    _timeLimit = null;
    replies.send(_stopped ? null : result);
  });
}

List<RootMove> alphabeta(Chess position) {
  List<RootMove> rootMoves = [];
  int alpha = -360000;
    int beta = 360000;
  final moves = position.moves({'asObjects': true}) as List<Move>;
  for (Move m in moves) {
    late int score;
    for (int it = 1; it < 16; it++) {
      position.move(m);
      score = -negamaxTactical(position, it, -beta, -alpha, ply: 0);
      position.undo_move();
    }
    rootMoves.add(RootMove(m, position.move_to_san(m), score));
    
  }
  return rootMoves;
}

void main() {
  Chess chess = Chess();
  for (int x = 0; x < 250; x++) {
    if (chess.game_over) break;
    print('position:  ${chess.fen}');
    // print("Evaluation: ${eval(chess,chess.turn)}");
    // print('Zobrist: ${chess.}');
    print(chess.ascii);
    var moves = iterativeDeepening(
      chess,
      64,
      timeLimit: const Duration(seconds: 10),
    );
    // print("Moves: ${moves}");
    // moves.shuffle();
    final move = moves[0].move;
    chess.move(move);
    print('move: ${moves[0]}');
    //  print('move: ${chess.move_to_san(move)}');
  }
}

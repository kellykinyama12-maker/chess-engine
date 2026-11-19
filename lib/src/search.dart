import 'package:chess/chess.dart';

import 'eval.dart';
import 'qsearch.dart';
import 'see.dart';

class RootMove {
  Move move;
  String san;
  int score;
  RootMove(this.move, this.san, this.score);

  @override
  String toString() {
    return "Rootmove(move: $san, score: $score)";
  }
}

const int maxPly = 128;

/// Score for delivering mate at the root; mate found at ply p scores `mateScore - p`.
const int mateScore = 40000;

/// Whether [score] is a forced mate (for either side) rather than an evaluation.
bool isMateScore(int score) => score.abs() >= mateScore - maxPly;

final Stopwatch _clock = Stopwatch();
Duration? _timeLimit;
bool _stopped = false;

/// True once the time limit was hit; results from the search in progress are incomplete.
bool get searchStopped => _stopped;

/// Restarts the clock for [rootMovesSearch] calls made outside [iterativeDeepening].
/// A null [limit] means no time limit.
void startSearchClock(Duration? limit) {
  _clock
    ..reset()
    ..start();
  _timeLimit = limit;
  _stopped = false;
}

/// Time since the last [startSearchClock] or [iterativeDeepening] call.
Duration get searchElapsed => _clock.elapsed;

/// Thrown by [Deadline.check] to unwind a search that ran out of time.
class SearchTimeout implements Exception {
  const SearchTimeout();
}

/// Time limit for recursive searches; [check] polls the clock every 1024 calls.
class Deadline {
  Deadline(this.limit) : _clock = Stopwatch()..start();

  final Duration? limit;
  final Stopwatch _clock;
  int _calls = 0;

  /// Off while the first depth runs, so there's always a complete result.
  bool armed = false;

  void check() {
    if (armed &&
        limit != null &&
        (++_calls & 1023) == 0 &&
        _clock.elapsed >= limit!) {
      throw const SearchTimeout();
    }
  }
}

/// Counts a node and checks the clock every 1024 nodes. Returns true if the search must stop.
bool visitNode() {
  nodes++;
  if ((nodes & 1023) == 0 &&
      _timeLimit != null &&
      _clock.elapsed >= _timeLimit!) {
    _stopped = true;
  }
  return _stopped;
}

// Triangular PV table: _pv[ply] is the best line found from that ply.
final List<List<Move>> _pv = List.generate(maxPly + 1, (_) => <Move>[]);
List<Move> _prevPv = [];
bool _followPv = false;

/// Nodes visited by negamax and qsearch since the last [resetSearchState].
int nodes = 0;
final List<List<Move?>> _killers = List.generate(maxPly, (_) => [null, null]);

final Map<PieceType, int> _orderValue = {
  PieceType.PAWN: 1,
  PieceType.KNIGHT: 2,
  PieceType.BISHOP: 3,
  PieceType.ROOK: 4,
  PieceType.QUEEN: 5,
  PieceType.KING: 6,
};

bool sameMove(Move? a, Move b) =>
    a != null && a.from == b.from && a.to == b.to && a.promotion == b.promotion;

int mvvLva(Move move) =>
    _orderValue[move.captured]! * 10 - _orderValue[move.piece]!;

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
  return 0;
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

void _storeKiller(Move move, int ply) {
  if (move.captured != null || sameMove(_killers[ply][0], move)) return;
  _killers[ply][1] = _killers[ply][0];
  _killers[ply][0] = move;
}

const int _exact = 0, _lowerBound = 1, _upperBound = 2;

class _TTEntry {
  const _TTEntry(this.depth, this.score, this.flag, this.move);

  final int depth;
  final int score;
  final int flag;
  final Move? move;
}

/// Transposition table for [negamax], keyed by Zobrist hash; cleared by [resetSearchState].
final Map<int, _TTEntry> _tt = {};

/// Converts a mate score at [ply] to be relative to the node, for storing in a TT.
int scoreToTT(int score, int ply) {
  if (!isMateScore(score) || score.abs() > mateScore) return score;
  return score > 0 ? score + ply : score - ply;
}

/// Inverse of [scoreToTT].
int scoreFromTT(int score, int ply) {
  if (!isMateScore(score) || score.abs() > mateScore) return score;
  return score > 0 ? score - ply : score + ply;
}

void resetSearchState() {
  nodes = 0;
  _stopped = false;
  _timeLimit = null;
  _prevPv = [];
  _followPv = false;
  _tt.clear();
  for (final k in _killers) {
    k[0] = null;
    k[1] = null;
  }
  for (final line in _pv) {
    line.clear();
  }
}

/// Cheap draw test for search: any repetition, 50-move rule, or insufficient material.
/// Stalemate is detected from the generated move list in [negamax].
bool isDrawn(Chess position) =>
    position.half_moves >= 100 ||
    position.repetitions > 0 ||
    position.insufficient_material;

int negamax(Chess position, int depth, int alpha, int beta, {int ply = 0}) {
  if (visitNode()) return 0;
  _pv[ply] = [];

  if (ply > 0 && isDrawn(position)) {
    return 0;
  }
  if (ply >= maxPly) return eval(position, position.turn);
  if (depth <= 0) {
    return qsearch(position, depth, alpha, beta, ply: ply);
  }

  final entry = _tt[position.zobrist];
  // No cutoffs along the previous PV, so the best line is rebuilt in full.
  if (entry != null && entry.depth >= depth && !_followPv) {
    final s = scoreFromTT(entry.score, ply);
    if (entry.flag == _exact)
      return s >= beta
          ? beta
          : s <= alpha
          ? alpha
          : s;
    if (entry.flag == _lowerBound && s >= beta) return beta;
    if (entry.flag == _upperBound && s <= alpha) return alpha;
  }

  final moves = position.moves({'asObjects': true}) as List<Move>;
  if (moves.isEmpty) {
    return position.in_check ? -mateScore + ply : 0;
  }

  Move? pvMove;
  if (_followPv) {
    _followPv = false;
    if (ply < _prevPv.length && moves.any((m) => sameMove(_prevPv[ply], m))) {
      pvMove = _prevPv[ply];
      _followPv = true;
    }
  }

  final alphaOrig = alpha;
  Move? bestMove;
  for (var move in orderMoves(position, moves, ply, pvMove ?? entry?.move)) {
    position.move(move);
    int score = -negamax(position, depth - 1, -beta, -alpha, ply: ply + 1);
    position.undo_move();
    if (_stopped) return 0;
    if (score >= beta) {
      _storeKiller(move, ply);
      _storeTT(position, depth, beta, _lowerBound, move, ply);
      return beta;
    }
    if (score > alpha) {
      alpha = score;
      bestMove = move;
      _pv[ply] = [move, ..._pv[ply + 1]];
    }
  }

  _storeTT(
    position,
    depth,
    alpha,
    alpha > alphaOrig ? _exact : _upperBound,
    bestMove,
    ply,
  );
  return alpha;
}

void _storeTT(
  Chess position,
  int depth,
  int score,
  int flag,
  Move? move,
  int ply,
) {
  final old = _tt[position.zobrist];
  if (old != null && old.depth > depth) return;
  _tt[position.zobrist] = _TTEntry(
    depth,
    scoreToTT(score, ply),
    flag,
    move ?? old?.move,
  );
}

// int randomMax(Chess position, int depth){

//     if(position.in_checkmate){
//     return -40000;
//   }
//   if(position.in_draw){
//     return 0;
//   }
//   if(depth<=0)return eval(position,position.turn);
//   int val=-360000;

//   var moves = position.moves();
//   for(var move in moves){
//     position.move(move);
//     int score =negamax(position, depth-1, -beta,-alpha);
//     position.undo_move();
//     if(score>val)val=score;
//     break;
//   }

//   return val;
// }

/// Searches root moves in the order of [previous] (if given), best first.
List<RootMove> rootMovesSearch(
  Chess position,
  int depth, [
  List<RootMove>? previous,
]) {
  List<RootMove> rootMoves = [];
  int alpha = -360000;
  _pv[0] = [];

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
    _followPv = i == 0 && _prevPv.isNotEmpty && sameMove(_prevPv[0], move);
    position.move(move);
    int score = -negamax(position, depth, -360000, -alpha, ply: 1);
    position.undo_move();
    if (_stopped) break;
    rootMoves.add(RootMove(move, san, score));
    if (score > alpha) {
      alpha = score;
      _pv[0] = [move, ..._pv[1]];
    }
  }
  if (!_stopped) _prevPv = List.of(_pv[0]);

  // Ties keep search order: later moves are only upper bounds once alpha is raised.
  final order = {for (var i = 0; i < rootMoves.length; i++) rootMoves[i]: i};
  rootMoves.sort((a, b) {
    final c = b.score.compareTo(a.score);
    return c != 0 ? c : order[a]!.compareTo(order[b]!);
  });

  return rootMoves;
}

/// Plies searched by the last iteration [iterativeDeepening] completed.
int depthReached = 0;

/// Runs [rootMovesSearch] at depths 0..[maxDepth], reusing each result to order the next.
/// The first iteration always completes; after that, an iteration cut off by [timeLimit] is discarded.
List<RootMove> iterativeDeepening(
  Chess position,
  int maxDepth, {
  Duration? timeLimit,
  bool verbose = true,
}) {
  List<RootMove>? rootMoves;
  resetSearchState();
  _clock
    ..reset()
    ..start();

  for (int depth = 0; depth <= maxDepth; depth++) {
    _timeLimit = depth == 0 ? null : timeLimit;
    final result = rootMovesSearch(position, depth, rootMoves);
    if (_stopped) {
      if (verbose)
        print(
          'depth ${depth + 1}: stopped after ${_clock.elapsedMilliseconds} ms, using depth $depth',
        );
      break;
    }
    rootMoves = result;
    depthReached = depth + 1;
    if (verbose)
      print(
        'depth ${depth + 1}: best ${rootMoves[0]} pv ${_pvToSan(position, _prevPv)} (${_clock.elapsedMilliseconds} ms)',
      );
    if (timeLimit != null && _clock.elapsed >= timeLimit) break;
  }
  _timeLimit = null;

  return rootMoves!;
}

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
      10,
      timeLimit: const Duration(seconds: 5),
    );
    // print("Moves: ${moves}");
    // moves.shuffle();
    final move = moves[0].move;
    chess.move(move);
    print('move: ${moves[0]}');
    //  print('move: ${chess.move_to_san(move)}');
  }
}

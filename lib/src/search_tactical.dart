import 'package:chess/chess.dart';

import 'eval.dart';
import 'see.dart';


enum NodeType{
  PV_NODE(0),
  ALL_NODE(-1),
  CUT_NODE(1);

  const NodeType(this.value);
  final int value;
}

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

/// Index of the first quiet move that cut negamaxTactical's line short before the horizon,
/// counted from each ply, or [_never] if the line is complete.
final List<int> _truncatedAt = List.filled(maxPly + 1, _never);
const int _never = 1 << 30;

/// A failed probe is re-searched if its refutation hit a quiet move within this many plies
/// (0 = always prune, [_never] = only prune complete forcing refutations).
int probeTruncationWindow = 0;

/// A move is only pruned if its probe fails by at least this many centipawns.
int probeMargin = 0;

/// Moves that give check don't use up depth in [negamax].
bool checkExtension = true;

/// Per node: a position whose tactical line isn't truncated is forcing and takes
/// negamaxTactical's score; otherwise it's quiet and gets a full search with no probe pruning.
bool adaptiveSearch = true;

/// What a failed probe does: 0 prunes the move, n > 0 searches it n plies shallower
/// (re-searched at full depth if it then beats alpha).
int probeReduction = 0;

/// Only probe quiet moves; captures, checks and promotions always get the full search.
bool probeQuietOnly = false;

/// Probe non-first moves with [negamaxTactical] (non-adaptive mode only).
bool probeEnabled = true;

/// If passing the turn still fails high at reduced depth, cut the node.
bool nullMovePruning = false;

/// Late quiet moves (ordered by killers and history) are searched shallower and re-searched if they beat alpha.
bool lateMoveReductions = false;

final List<int> _history = List.filled(2 * 128 * 128, 0);

int _historyIndex(Move m) =>
    (m.color == Color.WHITE ? 0 : 128 * 128) + m.from * 128 + m.to;
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
  return _history[_historyIndex(move)].clamp(0, 79999);
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

/// Separate table for [negamaxTactical]: its scores are tactical estimates, not exact values.
final Map<int, (_TTEntry, int)> _tacticalTT = {};

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
  _tacticalTT.clear();
  _history.fillRange(0, _history.length, 0);
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

int negamaxTactical(Chess position, int depth, int alpha, int beta, {int ply = 0}) {
  if (visitNode()) return 0;
  _pv[ply] = [];
  _truncatedAt[ply] = _never;

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
    if (entry.flag == _exact) {
      return s >= beta
          ? beta
          : s <= alpha
          ? alpha
          : s;
    }
    if (entry.flag == _lowerBound && s >= beta) return beta;
    if (entry.flag == _upperBound && s <= alpha) return alpha;
  }

  final tactical = _tacticalTT[position.zobrist];
  if (tactical != null && tactical.$1.depth >= depth && !_followPv) {
    final (e, truncatedAt) = tactical;
    final s = scoreFromTT(e.score, ply);
    final cutoff = e.flag == _exact
        ? (s >= beta ? beta : s <= alpha ? alpha : s)
        : (e.flag == _lowerBound && s >= beta)
        ? beta
        : (e.flag == _upperBound && s <= alpha)
        ? alpha
        : null;
    if (cutoff != null) {
      _truncatedAt[ply] = truncatedAt;
      return cutoff;
    }
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
  // Evasions are forcing: stopping at a quiet one would hide the attacker's next check or mate.
  final isEvasion = position.in_check;
  for (var move in orderMoves(position, moves, ply, pvMove ?? entry?.move)) {
   bool isCaptureMove= position.is_capture(move);
    
    position.move(move);

    bool givesCheck =position.in_check;
int score;
    final quiet = !givesCheck && !isCaptureMove && !isEvasion;
    if(quiet) {
      score =-qsearch(position, depth-1, -beta, -alpha, ply: ply + 1);
    } else {
      score = -negamaxTactical(position, depth - 1, -beta, -alpha, ply: ply + 1);
    }
    position.undo_move();
    if (_stopped) return 0;
    // A quiet move cut off before the horizon truncates the line; at the horizon it doesn't.
    final line = quiet ? [move] : [move, ..._pv[ply + 1]];
    final truncatedAt = quiet
        ? (depth > 1 ? 0 : _never)
        : (_truncatedAt[ply + 1] == _never ? _never : _truncatedAt[ply + 1] + 1);
    if (score >= beta) {
      _storeKiller(move, ply);
      _pv[ply] = line;
      _truncatedAt[ply] = truncatedAt;
      _storeTacticalTT(position, depth, beta, _lowerBound, move, ply, truncatedAt);
      return beta;
    }
    if (score > alpha) {
      alpha = score;
      bestMove = move;
      _pv[ply] = line;
      _truncatedAt[ply] = truncatedAt;
    }
  }
  // Failed low: no line backs the score.
  if (bestMove == null) _truncatedAt[ply] = 0;
  _storeTacticalTT(
    position,
    depth,
    alpha,
    alpha > alphaOrig ? _exact : _upperBound,
    bestMove,
    ply,
    _truncatedAt[ply],
  );

  // _storeTT(
  //   position,
  //   depth,
  //   alpha,
  //   alpha > alphaOrig ? _exact : _upperBound,
  //   bestMove,
  //   ply,
  // );
  return alpha;
}

bool _hasPieces(Chess position, Color side) {
  for (var sq = 0; sq < 128; sq++) {
    if ((sq & 0x88) != 0) continue;
    final p = position.board[sq];
    if (p != null &&
        p.color == side &&
        p.type != PieceType.PAWN &&
        p.type != PieceType.KING) {
      return true;
    }
  }
  return false;
}

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

  if (adaptiveSearch && ply > 1) {
    final followPv = _followPv;
    final tactical = negamaxTactical(position, depth, alpha, beta, ply: ply);
    if (_stopped) return 0;
    if (_truncatedAt[ply] == _never) return tactical;
    _followPv = followPv;
    _pv[ply] = [];
  }

  final entry = _tt[position.zobrist];
  // No cutoffs along the previous PV, so the best line is rebuilt in full.
  if (entry != null && entry.depth >= depth && !_followPv) {
    final s = scoreFromTT(entry.score, ply);
    if (entry.flag == _exact) {
      return s >= beta
          ? beta
          : s <= alpha
          ? alpha
          : s;
    }
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

  final inCheck = position.in_check;
  if (nullMovePruning &&
      ply > 0 &&
      beta - alpha == 1 &&
      !_followPv &&
      !inCheck &&
      depth >= 3 &&
      !isMateScore(beta) &&
      _hasPieces(position, position.turn) &&
      eval(position, position.turn) >= beta) {
    final r = depth > 6 ? 3 : 2;
    position.make_null_move();
    final score = -negamax(position, depth - 1 - r, -beta, -beta + 1, ply: ply + 1);
    position.undo_null_move();
    if (_stopped) return 0;
    if (score >= beta) return beta;
  }

  final alphaOrig = alpha;
  Move? bestMove;
  int moveCount=0;
  for (var move in orderMoves(position, moves, ply, pvMove ?? entry?.move)) {

   bool isCaptureMove= position.is_capture(move);
    
    bool givesCheck =position.in_check;


    position.move(move);
    final newDepth = depth - 1 + (checkExtension && position.in_check ? 1 : 0);
    final quietMove =
        !isCaptureMove && move.promotion == null && !position.in_check;

    // int tactical=negamaxTactical(position, depth, alpha, beta);
    int score ;
    // Research only when the probe's line was truncated by a quiet move before the horizon.
    var research = true;
    var reducedBy = 0;
    if (lateMoveReductions &&
        depth >= 3 &&
        moveCount >= 3 &&
        quietMove &&
        !inCheck &&
        !sameMove(_killers[ply][0], move) &&
        !sameMove(_killers[ply][1], move)) {
      reducedBy = moveCount >= 6 ? 2 : 1;
    }
    if(probeEnabled && !adaptiveSearch && moveCount>0&&ply>1 && (!probeQuietOnly || quietMove) //&&!isCaptureMove //!givesCheck //&& !isCaptureMove
    ) {
      // Probe at alpha - probeMargin; a pass is only a bound, so it's always re-searched.
      final threshold = alpha - probeMargin;
      score = -negamaxTactical(position, newDepth, -(threshold+1), -threshold, ply: ply + 1, );
      research = score > threshold || _truncatedAt[ply + 1] < probeTruncationWindow;
      if (!research && probeReduction > 0) {
        research = true;
        reducedBy = reducedBy > probeReduction ? reducedBy : probeReduction;
      }
    } else {
      score=alpha+1;
    }
    if(research && moveCount == 0) {
      score = -negamax(position, newDepth, -beta, -alpha, ply: ply + 1, );
    } else if(research)
    {
      score = -negamax(position, newDepth - reducedBy, -(alpha+1), -alpha, ply: ply + 1, );
      if(reducedBy > 0 && score > alpha) {
        score = -negamax(position, newDepth, -(alpha+1), -alpha, ply: ply + 1, );
      }
      if(score > alpha && score < beta) {
        score = -negamax(position, newDepth, -beta, -alpha, ply: ply + 1, );
      }
    }
    position.undo_move();
    moveCount++;
    if (_stopped) return 0;
    if (score >= beta) {
      _storeKiller(move, ply);
      if (quietMove) _history[_historyIndex(move)] += depth * depth;
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

void _storeTacticalTT(
  Chess position,
  int depth,
  int score,
  int flag,
  Move? move,
  int ply,
  int truncatedAt,
) {
  final old = _tacticalTT[position.zobrist];
  if (old != null && old.$1.depth > depth) return;
  _tacticalTT[position.zobrist] = (
    _TTEntry(depth, scoreToTT(score, ply), flag, move ?? old?.$1.move),
    truncatedAt,
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
    // Only the first root move needs a full window; the rest are tested against it.
    int score = i == 0
        ? -negamax(position, depth, -360000, -alpha, ply: 1)
        : -negamax(position, depth, -(alpha + 1), -alpha, ply: 1);
    if (i > 0 && score > alpha && !_stopped) {
      score = -negamax(position, depth, -360000, -alpha, ply: 1);
    }
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
      if (verbose) {
        print(
          'depth ${depth + 1}: stopped after ${_clock.elapsedMilliseconds} ms, using depth $depth',
        );
      }
      break;
    }
    rootMoves = result;
    depthReached = depth + 1;
    if (verbose) {
      print(
        'depth ${depth + 1}: best ${rootMoves[0]} pv ${_pvToSan(position, _prevPv)} (${_clock.elapsedMilliseconds} ms)',
      );
    }
    if (timeLimit != null && _clock.elapsed >= timeLimit) break;
  }
  _timeLimit = null;

  return rootMoves!;
}


int qsearch(Chess position, int depth,int alpha, int beta, {int ply = 0}){
  if(visitNode()) return 0;

    if(position.in_check){
    return negamax(position, 1,alpha,beta, ply: ply);
  }
  if(isDrawn(position)){
    return 0;
  }

  int score=eval(position,position.turn);
  if(score>=beta)return beta;
  if(score>alpha)alpha=score;

  final captures = (position.moves({'asObjects': true}) as List<Move>)
      .where((m) => position.is_capture(m) && see(position, m) >= 0)
      .toList()
    ..sort((a, b) => mvvLva(b).compareTo(mvvLva(a)));
  for(var move in captures){
    position.move(move);
    int score =-qsearch(position, depth-1,-beta,-alpha, ply: ply + 1);
    position.undo_move();
    if(searchStopped) return 0;
    
    if(score>=beta)return beta;
    if(score>alpha)alpha=score;
  }
 

  return alpha;
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

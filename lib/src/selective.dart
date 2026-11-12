import 'package:chess/chess.dart';

import 'eval.dart';
import 'search.dart'
    show
        Deadline,
        RootMove,
        SearchTimeout,
        isDrawn,
        isMateScore,
        mateScore,
        maxPly,
        mvvLva,
        sameMove,
        scoreFromTT,
        scoreToTT;
import 'see.dart';

const int _inf = 360000;
const int _exact = 0, _lower = 1, _upper = 2;

class _Entry {
  _Entry(this.depth, this.score, this.flag, this.move);

  final int depth;
  final int score;
  final int flag;
  final Move? move;
}

/// Depth (plies) of the last iteration [selectiveSearch] completed.
int selectiveDepthReached = 0;

/// Nodes visited by the last [selectiveSearch].
int selectiveNodes = 0;

/// Selective principal variation search.
///
/// Fail-soft PVS with a transposition table: the expected best move gets a full window,
/// every other move a zero-width test, re-searched only if it beats alpha. On top:
/// - [aspiration]: each depth starts with a narrow window around the previous score.
/// - [nullMove]: if passing the turn still fails high at reduced depth, prune the node.
/// - [lateMoveReductions]: quiet moves late in the ordering are searched shallower, and
///   re-searched at full depth only if they beat alpha. Ordering uses killers and a
///   history table built from cutoffs, so "late" means statistically unlikely to matter.
/// - [checkExtension]: moves that give check are searched one ply deeper.
/// With all four off this returns the exact minimax value, like alpha-beta.
/// Deepens one ply at a time; a depth cut off by [timeLimit] is discarded.
/// The result holds just the best move and its score.
List<RootMove> selectiveSearch(
  Chess position,
  int maxDepth, {
  Duration? timeLimit,
  bool aspiration = true,
  bool nullMove = true,
  bool lateMoveReductions = true,
  bool checkExtension = true,
}) {
  final deadline = Deadline(timeLimit);
  final tt = <int, _Entry>{};
  final killers = List.generate(maxPly + 1, (_) => <Move?>[null, null]);
  final history = List.filled(2 * 128 * 128, 0);
  selectiveNodes = 0;

  // true = null move. Lets a timeout unwind moves and null moves in reverse order.
  final made = <bool>[];
  void doMove(Move m) {
    position.make_move(m);
    made.add(false);
  }

  void undoMove() {
    position.undo_move();
    made.removeLast();
  }

  void doNull() {
    position.make_null_move();
    made.add(true);
  }

  void undoNull() {
    position.undo_null_move();
    made.removeLast();
  }

  int historyIndex(Move m) =>
      (m.color == Color.WHITE ? 0 : 128 * 128) + m.from * 128 + m.to;

  bool hasPieces(Color side) {
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

  /// TT move, good captures (MVV-LVA), queen promotions, killers, history, bad captures.
  List<Move> order(List<Move> moves, int ply, Move? ttMove) {
    int score(Move m) {
      if (sameMove(ttMove, m)) return 1 << 30;
      if (m.captured != null) {
        return (see(position, m) >= 0 ? 1 << 26 : -(1 << 26)) + mvvLva(m);
      }
      if (m.promotion == PieceType.QUEEN) return 1 << 25;
      if (sameMove(killers[ply][0], m)) return 1 << 24;
      if (sameMove(killers[ply][1], m)) return (1 << 24) - 1;
      return history[historyIndex(m)].clamp(0, (1 << 24) - 2);
    }

    final scored = [for (final m in moves) (m, score(m))]
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final s in scored) s.$1];
  }

  late int Function(int depth, int alpha, int beta, int ply, bool allowNull)
  pvs;

  int quiesce(int alpha, int beta, int ply) {
    deadline.check();
    selectiveNodes++;
    if (position.in_check) return pvs(1, alpha, beta, ply, false);
    if (isDrawn(position)) return 0;

    var best = eval(position, position.turn);
    if (best >= beta) return best;
    if (best > alpha) alpha = best;

    final captures =
        position
            .generate_moves()
            .where((m) => m.captured != null && see(position, m) >= 0)
            .toList()
          ..sort((a, b) => mvvLva(b).compareTo(mvvLva(a)));
    for (final move in captures) {
      doMove(move);
      final score = -quiesce(-beta, -alpha, ply + 1);
      undoMove();
      if (score > best) {
        best = score;
        if (score >= beta) return score;
        if (score > alpha) alpha = score;
      }
    }
    return best;
  }

  pvs = (int depth, int alpha, int beta, int ply, bool allowNull) {
    deadline.check();
    if (ply > 0 && isDrawn(position)) return 0;
    if (ply >= maxPly) return eval(position, position.turn);
    if (depth <= 0) return quiesce(alpha, beta, ply);
    selectiveNodes++;

    final pvNode = beta - alpha > 1;
    final entry = tt[position.zobrist];
    if (entry != null && entry.depth >= depth && !pvNode) {
      final s = scoreFromTT(entry.score, ply);
      if (entry.flag == _exact ||
          (entry.flag == _lower && s >= beta) ||
          (entry.flag == _upper && s <= alpha)) {
        return s;
      }
    }

    final moves = position.generate_moves();
    final inCheck = position.in_check;
    if (moves.isEmpty) return inCheck ? -mateScore + ply : 0;

    if (nullMove &&
        allowNull &&
        !pvNode &&
        !inCheck &&
        depth >= 3 &&
        !isMateScore(beta) &&
        hasPieces(position.turn) &&
        eval(position, position.turn) >= beta) {
      final r = depth > 6 ? 3 : 2;
      doNull();
      final score = -pvs(depth - 1 - r, -beta, -beta + 1, ply + 1, false);
      undoNull();
      if (score >= beta) return isMateScore(score) ? beta : score;
    }

    final alphaOrig = alpha;
    var best = -_inf;
    Move? bestMove;
    var index = 0;
    for (final move in order(moves, ply, entry?.move)) {
      final quiet = move.captured == null && move.promotion == null;
      doMove(move);
      final givesCheck = position.in_check;
      final newDepth = depth - 1 + (checkExtension && givesCheck ? 1 : 0);

      int score;
      if (index == 0) {
        score = -pvs(newDepth, -beta, -alpha, ply + 1, true);
      } else {
        var reduction = 0;
        if (lateMoveReductions &&
            depth >= 3 &&
            index >= 3 &&
            quiet &&
            !inCheck &&
            !givesCheck &&
            !sameMove(killers[ply][0], move) &&
            !sameMove(killers[ply][1], move)) {
          reduction = index >= 6 ? 2 : 1;
        }
        score = -pvs(newDepth - reduction, -alpha - 1, -alpha, ply + 1, true);
        if (score > alpha && reduction > 0) {
          score = -pvs(newDepth, -alpha - 1, -alpha, ply + 1, true);
        }
        if (score > alpha && score < beta) {
          score = -pvs(newDepth, -beta, -alpha, ply + 1, true);
        }
      }
      undoMove();
      index++;

      if (score > best) {
        best = score;
        bestMove = move;
        if (score > alpha) alpha = score;
        if (score >= beta) {
          if (quiet) {
            if (!sameMove(killers[ply][0], move)) {
              killers[ply][1] = killers[ply][0];
              killers[ply][0] = move;
            }
            history[historyIndex(move)] += depth * depth;
          }
          break;
        }
      }
    }

    final old = tt[position.zobrist];
    if (old == null || old.depth <= depth) {
      final flag = best >= beta
          ? _lower
          : best > alphaOrig
          ? _exact
          : _upper;
      tt[position.zobrist] = _Entry(
        depth,
        scoreToTT(best, ply),
        flag,
        bestMove ?? old?.move,
      );
    }
    return best;
  };

  var result = <RootMove>[];
  for (var depth = 1; depth <= maxDepth; depth++) {
    deadline.armed = depth > 1;
    try {
      var delta = 50;
      var alpha = -_inf, beta = _inf;
      if (aspiration && depth >= 4 && result.isNotEmpty) {
        alpha = result[0].score - delta;
        beta = result[0].score + delta;
      }
      int score;
      while (true) {
        score = pvs(depth, alpha, beta, 0, false);
        if (score <= alpha) {
          alpha = delta >= 400 ? -_inf : score - delta;
        } else if (score >= beta) {
          beta = delta >= 400 ? _inf : score + delta;
        } else {
          break;
        }
        delta *= 2;
      }
      final best = tt[position.zobrist]!.move!;
      result = [RootMove(best, position.move_to_san(best), score)];
      selectiveDepthReached = depth;
    } on SearchTimeout {
      while (made.isNotEmpty) {
        made.last ? undoNull() : undoMove();
      }
      break;
    }
  }
  return result;
}

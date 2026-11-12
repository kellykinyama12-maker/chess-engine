import 'package:chess/chess.dart';

import 'eval.dart';

const List<int> _diagonals = [-17, -15, 15, 17];
const List<int> _orthogonals = [-16, -1, 1, 16];
const List<int> _knightOffsets = [-33, -31, -18, -14, 14, 18, 31, 33];
const List<int> _kingOffsets = [-17, -16, -15, -1, 1, 15, 16, 17];

bool _onBoard(int sq) => (sq & 0x88) == 0;

/// Square of [side]'s least valuable piece attacking [target] on [board], or null.
int? _leastValuableAttacker(List<Piece?> board, int target, Color side) {
  int? best;
  int bestValue = 1 << 30;

  void consider(int sq, bool Function(PieceType) matches) {
    if (!_onBoard(sq)) return;
    final piece = board[sq];
    if (piece == null || piece.color != side || !matches(piece.type)) return;
    final value = PIECE_VALUE[piece.type]!;
    if (value < bestValue) {
      best = sq;
      bestValue = value;
    }
  }

  // A white pawn attacks up the board (towards lower 0x88 indices).
  final pawnFrom = side == Color.WHITE ? [target + 15, target + 17] : [target - 15, target - 17];
  for (final sq in pawnFrom) {
    consider(sq, (t) => t == PieceType.PAWN);
  }
  for (final o in _knightOffsets) {
    consider(target + o, (t) => t == PieceType.KNIGHT);
  }
  for (final o in _kingOffsets) {
    consider(target + o, (t) => t == PieceType.KING);
  }

  void slide(List<int> dirs, PieceType slider) {
    for (final d in dirs) {
      var sq = target + d;
      while (_onBoard(sq) && board[sq] == null) {
        sq += d;
      }
      consider(sq, (t) => t == slider || t == PieceType.QUEEN);
    }
  }

  slide(_diagonals, PieceType.BISHOP);
  slide(_orthogonals, PieceType.ROOK);
  return best;
}

/// Static exchange evaluation of [move] from the mover's view, in centipawns.
/// Pins and promotions during the exchange are ignored.
int see(Chess position, Move move) {
  if (move.captured == null) return 0;

  final board = List<Piece?>.of(position.board);
  final target = move.to;
  final gain = <int>[PIECE_VALUE[move.captured]!];

  if (move.flags & Chess.BITS_EP_CAPTURE != 0) {
    board[move.color == Color.WHITE ? target + 16 : target - 16] = null;
  }
  board[target] = board[move.from];
  board[move.from] = null;

  var side = move.color == Color.WHITE ? Color.BLACK : Color.WHITE;
  while (true) {
    final from = _leastValuableAttacker(board, target, side);
    if (from == null) break;

    final other = side == Color.WHITE ? Color.BLACK : Color.WHITE;
    final attacker = board[from]!;
    if (attacker.type == PieceType.KING) {
      // The king may only recapture if the square is no longer defended.
      final tmp = List<Piece?>.of(board)
        ..[target] = attacker
        ..[from] = null;
      if (_leastValuableAttacker(tmp, target, other) != null) break;
    }

    gain.add(PIECE_VALUE[board[target]!.type]! - gain.last);
    board[target] = attacker;
    board[from] = null;
    side = other;
  }

  for (var d = gain.length - 1; d > 0; d--) {
    gain[d - 1] = -((-gain[d - 1]) > gain[d] ? -gain[d - 1] : gain[d]);
  }
  return gain[0];
}

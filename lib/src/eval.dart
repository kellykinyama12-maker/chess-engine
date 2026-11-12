import "package:chess/chess.dart";

final Map<PieceType, int> PIECE_VALUE = {
     PieceType.PAWN:100,
     PieceType.KNIGHT:300,
     PieceType.BISHOP:300,
     PieceType.ROOK:500,
     PieceType.QUEEN:900,
     PieceType.KING:37600
  };

// Simplified Evaluation Function tables (Michniewski), white's view, index 0 = a8.
const List<int> PAWN_PST = [
   0,  0,  0,  0,  0,  0,  0,  0,
  50, 50, 50, 50, 50, 50, 50, 50,
  10, 10, 20, 30, 30, 20, 10, 10,
   5,  5, 10, 25, 25, 10,  5,  5,
   0,  0,  0, 20, 20,  0,  0,  0,
   5, -5,-10,  0,  0,-10, -5,  5,
   5, 10, 10,-20,-20, 10, 10,  5,
   0,  0,  0,  0,  0,  0,  0,  0,
];

const List<int> KNIGHT_PST = [
  -50,-40,-30,-30,-30,-30,-40,-50,
  -40,-20,  0,  0,  0,  0,-20,-40,
  -30,  0, 10, 15, 15, 10,  0,-30,
  -30,  5, 15, 20, 20, 15,  5,-30,
  -30,  0, 15, 20, 20, 15,  0,-30,
  -30,  5, 10, 15, 15, 10,  5,-30,
  -40,-20,  0,  5,  5,  0,-20,-40,
  -50,-40,-30,-30,-30,-30,-40,-50,
];

const List<int> BISHOP_PST = [
  -20,-10,-10,-10,-10,-10,-10,-20,
  -10,  0,  0,  0,  0,  0,  0,-10,
  -10,  0,  5, 10, 10,  5,  0,-10,
  -10,  5,  5, 10, 10,  5,  5,-10,
  -10,  0, 10, 10, 10, 10,  0,-10,
  -10, 10, 10, 10, 10, 10, 10,-10,
  -10,  5,  0,  0,  0,  0,  5,-10,
  -20,-10,-10,-10,-10,-10,-10,-20,
];

const List<int> ROOK_PST = [
   0,  0,  0,  0,  0,  0,  0,  0,
   5, 10, 10, 10, 10, 10, 10,  5,
  -5,  0,  0,  0,  0,  0,  0, -5,
  -5,  0,  0,  0,  0,  0,  0, -5,
  -5,  0,  0,  0,  0,  0,  0, -5,
  -5,  0,  0,  0,  0,  0,  0, -5,
  -5,  0,  0,  0,  0,  0,  0, -5,
   0,  0,  0,  5,  5,  0,  0,  0,
];

const List<int> QUEEN_PST = [
  -20,-10,-10, -5, -5,-10,-10,-20,
  -10,  0,  0,  0,  0,  0,  0,-10,
  -10,  0,  5,  5,  5,  5,  0,-10,
   -5,  0,  5,  5,  5,  5,  0, -5,
    0,  0,  5,  5,  5,  5,  0, -5,
  -10,  5,  5,  5,  5,  5,  0,-10,
  -10,  0,  5,  0,  0,  0,  0,-10,
  -20,-10,-10, -5, -5,-10,-10,-20,
];

// Middlegame king table.
const List<int> KING_PST = [
  -30,-40,-40,-50,-50,-40,-40,-30,
  -30,-40,-40,-50,-50,-40,-40,-30,
  -30,-40,-40,-50,-50,-40,-40,-30,
  -30,-40,-40,-50,-50,-40,-40,-30,
  -20,-30,-30,-40,-40,-30,-30,-20,
  -10,-20,-20,-20,-20,-20,-20,-10,
   20, 20,  0,  0,  0,  0, 20, 20,
   20, 30, 10,  0,  0, 10, 30, 20,
];

final Map<PieceType, List<int>> PST = {
  PieceType.PAWN: PAWN_PST,
  PieceType.KNIGHT: KNIGHT_PST,
  PieceType.BISHOP: BISHOP_PST,
  PieceType.ROOK: ROOK_PST,
  PieceType.QUEEN: QUEEN_PST,
  PieceType.KING: KING_PST,
};

/// Returns a String representation of the current position
  /// complete with ascii art
  int eval(Chess position, Color sideToMove) {
    // var s = '   +------------------------+\n';\
    int s=0;
    for (var i = Chess.SQUARES_A8; i <= Chess.SQUARES_H1; i++) {
      /* display the rank */
      if (Chess.file(i) == 0) {
        // s += ' ' + '87654321'[Chess.rank(i)] + ' |';
      }

      /* empty piece */
      if (position.board[i] == null) {
        // s += ' . ';
      } else {
        var type = position.board[i]!.type;
        var color = position.board[i]!.color;
        // var symbol = (color == Chess.WHITE) ? type.toUpperCase() : type.toLowerCase();
        // s += ' ' + symbol + ' ';
        var file = Chess.file(i);
        var rank = Chess.rank(i);
        if(color == Chess.WHITE) {
          s+=PIECE_VALUE[type]! + PST[type]![rank * 8 + file];
        } else {
          s-=PIECE_VALUE[type]! + PST[type]![(7 - rank) * 8 + file];
        }
      }

      if (((i + 1) & 0x88) != 0) {
        // s += '|\n';
        i += 8;
      }
    }
    // s += '   +------------------------+\n';
    // s += '     a  b  c  d  e  f  g  h\n';
    if(sideToMove == Chess.WHITE) {
      return s;
    } else {
      return -s;
    }

    // return s;
  }
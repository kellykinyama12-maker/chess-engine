import 'package:chess_engine/chess_engine.dart' as chess_engine;

import "package:chess/chess.dart";
import 'package:chess_engine/src/eval.dart';


void main() {
  Chess chess = Chess();
  while (!chess.game_over) {
    print('position: ' + chess.fen);
    print("Evaluation: ${eval(chess,chess.turn)}");
    // print('Zobrist: ${chess.}');
    print(chess.ascii);
    var moves = chess.moves();
    moves.shuffle();
    final move = moves[0];
    chess.move(move);
    print('move: $move');
    //  print('move: ${chess.move_to_san(move)}');
  }
}
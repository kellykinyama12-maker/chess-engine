import 'package:chess/chess.dart';
import 'package:chess_engine/src/search.dart';

import 'eval.dart';
import 'see.dart';

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
import 'package:chess/chess.dart';
import 'package:chess_engine/src/search.dart';

const positions = {
  'start': Chess.DEFAULT_POSITION,
  'italian': 'r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4',
  'kiwipete': 'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
  'endgame': '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1',
};

/// Usage: dart run benchmark/search_benchmark.dart [maxDepth] [secondsPerPosition]
void main(List<String> args) {
  final maxDepth = args.isNotEmpty ? int.parse(args[0]) : 2;
  final limit = Duration(seconds: args.length > 1 ? int.parse(args[1]) : 60);

  print('| Position | Plies | Best | Score | Nodes | Time (ms) | NPS |');
  print('|---|---|---|---|---|---|---|');
  var totalNodes = 0;
  var totalMs = 0;

  for (final entry in positions.entries) {
    final chess = Chess.fromFEN(entry.value);
    resetSearchState();
    final stopwatch = Stopwatch()..start();
    List<RootMove>? rootMoves;

    for (var depth = 0; depth <= maxDepth; depth++) {
      rootMoves = rootMovesSearch(chess, depth, rootMoves);
      final ms = stopwatch.elapsedMilliseconds;
      final nps = ms == 0 ? '-' : (nodes * 1000 ~/ ms).toString();
      print('| ${entry.key} | ${depth + 1} | ${rootMoves[0].san} | ${rootMoves[0].score} | $nodes | $ms | $nps |');
      if (stopwatch.elapsed >= limit) break;
    }
    totalNodes += nodes;
    totalMs += stopwatch.elapsedMilliseconds;
  }

  print('');
  print('Total: $totalNodes nodes in $totalMs ms '
      '(${totalMs == 0 ? '-' : totalNodes * 1000 ~/ totalMs} NPS)');

  print('');
  print('| Perft (legal movegen) | Depth | Nodes | Time (ms) | NPS |');
  print('|---|---|---|---|---|');
  for (final (name, fen, depth) in [
    ('start', Chess.DEFAULT_POSITION, 4),
    ('kiwipete', positions['kiwipete']!, 3),
    ('endgame', positions['endgame']!, 5),
  ]) {
    final chess = Chess.fromFEN(fen);
    final stopwatch = Stopwatch()..start();
    final n = _perft(chess, depth);
    final ms = stopwatch.elapsedMilliseconds;
    print('| $name | $depth | $n | $ms | ${ms == 0 ? '-' : n * 1000 ~/ ms} |');
  }
}

int _perft(Chess chess, int depth) {
  final moves = chess.generate_moves();
  if (depth == 1) return moves.length;
  var nodes = 0;
  for (final m in moves) {
    chess.make_move(m);
    nodes += _perft(chess, depth - 1);
    chess.undo_move();
  }
  return nodes;
}

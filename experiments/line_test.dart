import 'dart:async';
import 'dart:isolate';

import 'package:chess/chess.dart';
import 'package:chess_engine/src/search.dart' as ab;
import 'package:chess_engine/src/search_tactical.dart' as tac;

/// Plays a line, then searches each position along it with both engines, printing
/// every completed depth (best move, score, PV) for comparison.
///
/// Usage: dart run experiments/line_test.dart [msPerPosition] [plies to analyse from the end] SAN...
/// e.g.   dart run experiments/line_test.dart 3000 2 e4 e5 f4 d5 fxe5
Future<void> main(List<String> args) async {
  final ms = args.isNotEmpty ? int.parse(args[0]) : 3000;
  final last = args.length > 1 ? int.parse(args[1]) : 2;
  final line = args.length > 2 ? args.sublist(2) : ['e4', 'e5', 'f4', 'd5', 'fxe5'];

  final chess = Chess();
  final fens = <(String, String)>[];
  for (var i = 0; i <= line.length; i++) {
    fens.add((line.take(i).join(' '), chess.fen));
    if (i < line.length && !chess.move(line[i])) {
      throw ArgumentError('illegal move ${line[i]} after ${line.take(i).join(' ')}');
    }
  }

  for (final (moves, fen) in fens.skip(fens.length - last)) {
    print('\n=== after ${moves.isEmpty ? '(start)' : moves}  [$fen]');
    final outputs = await Future.wait([
      for (final engine in ['regular', 'tactical'])
        Isolate.run(() {
          final out = StringBuffer();
          final c = Chess.fromFEN(fen);
          final limit = Duration(milliseconds: ms);
          // Capture the per-depth lines printed by iterativeDeepening.
          runZonedPrint(out, () {
            if (engine == 'regular') {
              ab.iterativeDeepening(c, 63, timeLimit: limit);
            } else {
              tac.iterativeDeepening(c, 64, timeLimit: limit);
            }
          });
          return '--- $engine\n$out';
        }),
    ]);
    outputs.forEach(print);
  }
}

void runZonedPrint(StringBuffer out, void Function() body) {
  runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (_, _, _, line) => out.writeln('  $line'),
    ),
  );
}

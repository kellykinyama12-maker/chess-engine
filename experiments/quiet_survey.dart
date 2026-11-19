import 'dart:isolate';

import 'package:chess/chess.dart';
import 'package:chess_engine/src/search.dart' as ab;
import 'package:chess_engine/src/search_tactical.dart' as tac;

/// Quiet positions: (name, moves from the start or null, FEN or null).
const positions = <(String, List<String>?, String?)>[
  ('start', [], null),
  ('italian', ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Bc5', 'c3', 'Nf6', 'd3', 'd6', 'O-O', 'O-O'], null),
  ('qgd', ['d4', 'd5', 'c4', 'e6', 'Nc3', 'Nf6', 'Bg5', 'Be7', 'e3', 'O-O', 'Nf3', 'h6', 'Bh4', 'b6'], null),
  ('ruy closed', ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6', 'Ba4', 'Nf6', 'O-O', 'Be7', 'Re1', 'b5', 'Bb3', 'd6', 'c3', 'O-O', 'h3'], null),
  ('caro-kann', ['e4', 'c6', 'd4', 'd5', 'Nc3', 'dxe4', 'Nxe4', 'Bf5', 'Ng3', 'Bg6', 'h4', 'h6', 'Nf3', 'Nd7'], null),
  ('london', ['d4', 'd5', 'Bf4', 'Nf6', 'e3', 'e6', 'Nf3', 'c5', 'c3', 'Nc6', 'Nbd2', 'Bd6', 'Bg3', 'O-O', 'Bd3'], null),
  ('kp opposition 1', null, '8/8/1k6/8/1K6/1P6/8/8 w - - 0 1'),
  ('kp opposition 2', null, '8/4k3/8/4K3/4P3/8/8/8 w - - 0 1'),
  ('kp opposition 3', null, '8/8/8/2k5/8/2K5/2P5/8 w - - 0 1'),
  ('kp win: king first', null, '8/8/4k3/8/8/4K3/4P3/8 w - - 0 1'),
  ('kp win: Kd3 not pawn', null, '8/8/8/3k4/8/8/3PK3/8 w - - 0 1'),
  ('lucena', null, '1K1k4/1P6/8/8/8/8/r7/2R5 w - - 0 1'),
];

Chess build((String, List<String>?, String?) p) {
  if (p.$3 != null) return Chess.fromFEN(p.$3!);
  final c = Chess();
  for (final m in p.$2!) {
    if (!c.move(m)) throw ArgumentError('${p.$1}: illegal $m');
  }
  return c;
}

String uci(Move m) =>
    '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}';

String run(int index, String engine, int ms) {
  final c = build(positions[index]);
  final limit = Duration(milliseconds: ms);
  if (engine == 'regular') {
    final r = ab.iterativeDeepening(c, 63, timeLimit: limit, verbose: false)[0];
    return '${r.san} (${uci(r.move)}) ${r.score} d${ab.depthReached}';
  }
  final r = tac.iterativeDeepening(c, 64, timeLimit: limit, verbose: false)[0];
  return '${r.san} (${uci(r.move)}) ${r.score} d${tac.depthReached}';
}

/// Usage: dart run experiments/quiet_survey.dart [ms ...]
Future<void> main(List<String> args) async {
  final times = args.isEmpty ? [1000, 3000] : args.map(int.parse).toList();
  for (var i = 0; i < positions.length; i++) {
    final c = build(positions[i]);
    if (c.game_over) throw StateError('${positions[i].$1} is already over');
  }

  final jobs = <(int, String, int)>[
    for (var i = 0; i < positions.length; i++)
      for (final ms in times)
        for (final e in ['regular', 'tactical']) (i, e, ms),
  ];
  final results = <(int, String, int), String>{};
  var next = 0;
  Future<void> worker() async {
    while (next < jobs.length) {
      final job = jobs[next++];
      results[job] = await Isolate.run(() => run(job.$1, job.$2, job.$3));
    }
  }

  await Future.wait([for (var w = 0; w < 16; w++) worker()]);

  for (var i = 0; i < positions.length; i++) {
    print('${positions[i].$1}  [${build(positions[i]).fen}]');
    for (final ms in times) {
      print('  ${ms}ms  regular ${results[(i, 'regular', ms)]}  |  tactical ${results[(i, 'tactical', ms)]}');
    }
  }
}

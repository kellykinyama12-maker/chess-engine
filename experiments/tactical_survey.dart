import 'dart:isolate';
import 'dart:math';

import 'package:chess/chess.dart';
import 'package:chess_engine/src/search.dart' as ab;
import 'package:chess_engine/src/search_tactical.dart' as tac;
import 'package:chess_engine/src/selective.dart';

/// Win At Chess positions (id, FEN, best move in SAN without +/#).
const suite = [
  ('WAC.001', '2rr3k/pp3pp1/1nnqbN1p/3pN3/2pP4/2P3Q1/PPB4P/R4RK1 w - - 0 1', 'Qg6'),
  ('WAC.002', '8/7p/5k2/5p2/p1p2P2/Pr1pPK2/1P1R3P/8 b - - 0 1', 'Rxb2'),
  ('WAC.004', 'r1bq2rk/pp3pbp/2p1p1pQ/7P/3P4/2PB1N2/PP3PPR/2KR4 w - - 0 1', 'Qxh7'),
  ('WAC.005', '5k2/6pp/p1qN4/1p1p4/3P4/2PKP2Q/PP3r2/3R4 b - - 0 1', 'Qc4'),
  ('WAC.006', '7k/p7/1R5K/6r1/6p1/6P1/8/8 w - - 0 1', 'Rb7'),
  ('WAC.007', 'rnbqkb1r/pppp1ppp/8/4P3/6n1/7P/PPPNPPP1/R1BQKBNR b KQkq - 0 1', 'Ne3'),
  ('WAC.008', 'r4q1k/p2bR1rp/2p2Q1N/5p2/5p2/2P5/PP3PPP/R5K1 w - - 0 1', 'Rf7'),
  ('WAC.009', '3q1rk1/p4pp1/2pb3p/3p4/6Pr/1PNQ4/P1PB1PP1/4RRK1 b - - 0 1', 'Bh2'),
  ('WAC.010', '2br2k1/2q3rn/p2NppQ1/2p1P3/Pp5R/4P3/1P3PPP/3R2K1 w - - 0 1', 'Rh7'),
];

String _strip(String san) => san.replaceAll(RegExp(r'[+#]'), '');

/// Best move (SAN without +/#), depth reached and nodes for one engine on one position.
({String move, int depth, int nodes}) _run(String engine, String fen, int ms) {
  final chess = Chess.fromFEN(fen);
  final limit = Duration(milliseconds: ms);
  switch (engine) {
    case 'regular':
      final m = ab.iterativeDeepening(chess, 63, timeLimit: limit, verbose: false)[0];
      return (move: _strip(m.san), depth: ab.depthReached, nodes: ab.nodes);
    case 'tactical':
      ab.resetSearchState(); // qsearch's in-check path uses search.dart's state.
      final m = tac.iterativeDeepening(chess, 63, timeLimit: limit, verbose: false)[0];
      return (move: _strip(m.san), depth: tac.depthReached, nodes: tac.nodes + ab.nodes);
    default:
      final m = selectiveSearch(chess, 64, timeLimit: limit)[0];
      return (move: _strip(m.san), depth: selectiveDepthReached, nodes: selectiveNodes);
  }
}

/// Fixed-depth root score, best move, nodes and time.
({int score, String move, int nodes, int ms}) _fixed(String engine, String fen, int plies) {
  final chess = Chess.fromFEN(fen);
  final sw = Stopwatch()..start();
  if (engine == 'regular') {
    final m = ab.iterativeDeepening(chess, plies - 1, verbose: false)[0];
    return (score: m.score, move: _strip(m.san), nodes: ab.nodes, ms: sw.elapsedMilliseconds);
  }
  ab.resetSearchState();
  final m = tac.iterativeDeepening(chess, plies - 1, verbose: false)[0];
  return (score: m.score, move: _strip(m.san), nodes: tac.nodes + ab.nodes, ms: sw.elapsedMilliseconds);
}

Future<List<T>> _pool<T>(List<T Function()> jobs, int concurrency) async {
  final results = List<T?>.filled(jobs.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < jobs.length) {
      final i = next++;
      results[i] = await Isolate.run(jobs[i]);
    }
  }

  await Future.wait([for (var i = 0; i < min(concurrency, jobs.length); i++) worker()]);
  return results.cast<T>();
}

/// Usage: dart run experiments/tactical_survey.dart [maxFixedPlies]
Future<void> main(List<String> args) async {
  final maxFixed = args.isNotEmpty ? int.parse(args[0]) : 5;

  // 1. Validate the suite: legal FEN, legal best move, and a long search agrees.
  print('== Suite validation (regular and selective at 5 s)');
  final valid = <(String, String, String)>[];
  final checks = await _pool([
    for (final (id, fen, bm) in suite)
      () {
        final chess = Chess.fromFEN(fen);
        final legal = chess.generate_moves().any((m) => _strip(chess.move_to_san(m)) == bm);
        if (!legal) return (id, false, '-', '-');
        return (id, true, _run('regular', fen, 5000).move, _run('selective', fen, 5000).move);
      },
  ], 16);
  for (var i = 0; i < suite.length; i++) {
    final (id, legal, regular, selective) = checks[i];
    final bm = suite[i].$3;
    final agree = legal && (regular == bm || selective == bm);
    print('$id bm $bm: legal $legal, regular 5s $regular, selective 5s $selective -> ${agree ? 'kept' : 'dropped'}');
    if (agree) valid.add(suite[i]);
  }

  // 2. Solve rates at fixed time.
  for (final ms in [250, 1000]) {
    print('\n== Solve rate at $ms ms');
    for (final engine in ['regular', 'tactical', 'selective']) {
      final results = await _pool([
        for (final (_, fen, _) in valid) () => _run(engine, fen, ms),
      ], 16);
      var solved = 0;
      final misses = <String>[];
      var depth = 0, nodeCount = 0;
      for (var i = 0; i < valid.length; i++) {
        final r = results[i];
        depth += r.depth;
        nodeCount += r.nodes;
        if (r.move == valid[i].$3) {
          solved++;
        } else {
          misses.add('${valid[i].$1}:${r.move}');
        }
      }
      print('${engine.padRight(9)} $solved/${valid.length} solved, avg depth '
          '${(depth / valid.length).toStringAsFixed(1)}, avg nodes ${nodeCount ~/ valid.length}'
          '${misses.isEmpty ? '' : ', missed ${misses.join(' ')}'}');
      print('          depth per position: '
          '${[for (var i = 0; i < valid.length; i++) '${valid[i].$1.substring(4)}:${results[i].depth}'].join(' ')}');
    }
  }

  // 3. Fixed depth: is the tactical search exact, and what does it cost?
  print('\n== Fixed depth vs exact alpha-beta (regular)');
  for (var plies = 1; plies <= maxFixed; plies++) {
    final jobs = <({int score, String move, int nodes, int ms}) Function()>[];
    for (final (_, fen, _) in valid) {
      jobs.add(() => _fixed('regular', fen, plies));
      jobs.add(() => _fixed('tactical', fen, plies));
    }
    final r = await _pool(jobs, 16);
    var sameScore = 0, sameMove = 0, abNodes = 0, tNodes = 0, abMs = 0, tMs = 0;
    for (var i = 0; i < valid.length; i++) {
      final a = r[2 * i], t = r[2 * i + 1];
      if (a.score == t.score) sameScore++;
      if (a.move == t.move) sameMove++;
      abNodes += a.nodes;
      tNodes += t.nodes;
      abMs += a.ms;
      tMs += t.ms;
    }
    print('$plies plies: same score $sameScore/${valid.length}, same move $sameMove/${valid.length}, '
        'nodes regular $abNodes vs tactical $tNodes, time ${abMs}ms vs ${tMs}ms');
  }
}

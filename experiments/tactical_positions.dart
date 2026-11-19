import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:chess/chess.dart';
import 'package:chess_engine/src/mcts_new.dart' as mcts;
import 'package:chess_engine/src/mcts_prior.dart' as typed;
import 'package:chess_engine/src/search.dart' as ab;
import 'package:chess_engine/src/search_forcing.dart' as forcing;
import 'package:chess_engine/src/search_tactical.dart' as tac;

/// (name, FEN, best move in SAN without +/#).
const positions = [
  // 1. e4 e5 2. f4 d5 3. fxe5 Qh4+: Stockfish g3 -522, Ke2 -687.
  ('KG 4.g3', 'rnb1kbnr/ppp2ppp/8/3pP3/4P2q/8/PPPP2PP/RNBQKBNR w KQkq - 1 4', 'g3'),
  // ...4.Ke2 Qxe4+ 5.Kf2 Bc5+ 6.Kg3: Qxe5+ Kf3 Qf5+ Kg3 Bf2#.
  ('KG mate', 'rnb1k1nr/ppp2ppp/8/2bpP3/4q3/6K1/PPPP2PP/RNBQ1BNR b kq - 3 6', 'Qxe5'),
  ('WAC.001', '2rr3k/pp3pp1/1nnqbN1p/3pN3/2pP4/2P3Q1/PPB4P/R4RK1 w - - 0 1', 'Qg6'),
  ('WAC.002', '8/7p/5k2/5p2/p1p2P2/Pr1pPK2/1P1R3P/8 b - - 0 1', 'Rxb2'),
  ('WAC.004', 'r1bq2rk/pp3pbp/2p1p1pQ/7P/3P4/2PB1N2/PP3PPR/2KR4 w - - 0 1', 'Qxh7'),
  ('WAC.005', '5k2/6pp/p1qN4/1p1p4/3P4/2PKP2Q/PP3r2/3R4 b - - 0 1', 'Qc4'),
  ('WAC.006', '7k/p7/1R5K/6r1/6p1/6P1/8/8 w - - 0 1', 'Rb7'),
  ('WAC.007', 'rnbqkb1r/pppp1ppp/8/4P3/6n1/7P/PPPNPPP1/R1BQKBNR b KQkq - 0 1', 'Ne3'),
  ('WAC.008', 'r4q1k/p2bR1rp/2p2Q1N/5p2/5p2/2P5/PP3PPP/R5K1 w - - 0 1', 'Rf7'),
  ('WAC.009', '3q1rk1/p4pp1/2pb3p/3p4/6Pr/1PNQ4/P1PB1PP1/4RRK1 b - - 0 1', 'Bh2'),
  ('WAC.010', '2br2k1/2q3rn/p2NppQ1/2p1P3/Pp5R/4P3/1P3PPP/3R2K1 w - - 0 1', 'Rxh7'),
  // Mined from tactical vs regular games (mine_positions.dart, seed 1); bm from selective at 10 s.
  ('G01', '2kr3r/1pp3pp/p4n2/P1b1Np2/BnPp4/4P2P/1P1P1PP1/R1B2RK1 b - - 0 17', 'Rhf8'),
  ('G02', '8/6pk/1R1B3p/1n6/8/P1p5/1r6/7K w - - 2 62', 'Bf4'),
  ('G03', 'r4r1k/ppp1p2P/4P3/1q1p3n/2P5/4P3/PP1B2QP/R3K1R1 b Q - 0 23', 'Qxb2'),
  ('G04', '3r1r2/pp2N1bk/3pQ3/q7/3P2p1/8/P4PPP/3RR1K1 b - - 0 33', 'Rf6'),
  ('G05', 'r1bqkb1r/p1p4p/2p1pn2/3p1p2/3P1Qp1/P1N1P3/1PP2PPP/R1B1K1NR w KQkq - 0 10', 'Qg5'),
  ('G06', 'r1bqkb1r/p1p4p/2p1p3/3p1p1n/3P1Qp1/P1N1P3/1PP1NPPP/R1B1K2R w KQkq - 2 11', 'Qe5'),
  ('G07', '5rk1/p1p4p/4p3/3PP3/5rpq/P7/1PPR1PpP/4R1K1 w - - 3 24', 'Ree2'),
  ('G08', '8/2R3k1/1P6/8/5r2/8/1K6/8 b - - 36 119', 'Kh6'),
  ('G09', 'r3kb1r/pp4pp/4b3/q2p3P/2nN1Bn1/2NQ4/PPP5/1R2KB1R b Kkq - 1 16', 'Bd7'),
  ('G10', 'r6r/pp3kNp/8/q2p3P/1b3B2/2N3Q1/PnP5/1R3RK1 b - - 1 21', 'Ke7'),
  ('G11', 'r1kq3r/pp4Np/8/2B4P/5Q2/2N5/PRP5/5RK1 b - - 0 29', 'Rg8'),
  ('G12', '1r2k2r/p3n1pp/8/2bB4/5B1P/2q5/P1P1K3/3Q3R w k - 0 22', 'Be6'),
  ('G13', 'r3r1k1/2R3pp/8/3p4/1P2p3/3NP3/n4PPP/R5K1 w - - 2 27', 'Nf4'),
  ('G14', '4R3/2p2pkp/3P4/r1P5/8/7P/5PK1/8 b - - 0 46', 'cxd6'),
  ('G15', '6k1/2p2p1p/2b1r2P/1p2P3/4rP2/P2p4/1P1P4/R1B2RK1 w - - 1 33', 'Rf3'),
];

final _depthLine = RegExp(r'(?:quiets (\d+) )?depth (\d+): best Rootmove\(move: (\S+), score: (-?\d+)\).*\((\d+) ms\)');

/// Per completed iteration: (label, move, score, ms); label is d<depth> or q<quiets>d<depth>.
typedef Iteration = (String, String, int, int);

Future<List<Iteration>> _search(String engine, String fen, int ms, String config) async {
  final lines = <String>[];
  await runZoned(
    () async {
      final chess = Chess.fromFEN(fen);
      final limit = Duration(milliseconds: ms);
      if (engine == 'regular') {
        ab.iterativeDeepening(chess, 63, timeLimit: limit);
      } else if (engine.startsWith('mcts') || engine.startsWith('typed')) {
        // mcts<priorMs> or typed<priorMs>[w<workers>] (node-typed priors, mcts_prior.dart),
        // e.g. typed150w8: simulations until the time limit, reported every 25.
        final m = RegExp(r'^(mcts|typed)(\d*)(?:w(\d+))?$').firstMatch(engine)!;
        final priorMs = int.tryParse(m[2]!) ?? 50;
        final workers = m[3] == null ? 1 : int.parse(m[3]!);
        final pool = workers > 1 ? await typed.TypedPriorPool.spawn(workers) : null;
        final mc = (m[1] == 'typed'
            ? (typed.TypedMonteCarlo()..typedPool = pool)
            : mcts.MonteCarlo())
          ..position = chess
          ..priorTimeLimit = Duration(milliseconds: priorMs);
        final sw = Stopwatch()..start();
        await mc.createRoot();
        var sims = 0;
        void report() {
          final best = mc.emitPv().first;
          print('depth $sims: best Rootmove(move: ${best.san}, score: ${best.score}) (${sw.elapsedMilliseconds} ms)');
        }

        while (sw.elapsed < limit) {
          mc.treePolicy();
          mc.backup(await mc.playOutPolicy());
          if (++sims % 25 == 0) report();
        }
        report();
        pool?.close();
      } else if (engine.startsWith('forcing')) {
        // forcing<runs>[c<checks>], e.g. forcing2c1: at most 2 quiet runs and 1 non-capturing check per line.
        final m = RegExp(r'^forcing(\d*)(?:c(\d+))?$').firstMatch(engine)!;
        forcing.iterativeDeepening(
          chess,
          64,
          maxRuns: int.tryParse(m[1]!) ?? 1,
          maxChecks: m[2] == null ? 64 : int.parse(m[2]!),
          timeLimit: limit,
        );
      } else {
        _configure(config);
        ab.resetSearchState(); // qsearch's in-check path uses search.dart's state.
        tac.iterativeDeepening(chess, 64, timeLimit: limit);
      }
    },
    zoneSpecification: ZoneSpecification(print: (_, _, _, line) => lines.add(line)),
  );
  return [
    for (final l in lines)
      if (_depthLine.firstMatch(l) case final m?)
        (
          '${m[1] == null ? '' : 'q${m[1]}'}d${m[2]}',
          m[3]!.replaceAll(RegExp(r'[+#]'), ''),
          int.parse(m[4]!),
          int.parse(m[5]!),
        ),
  ];
}

/// e.g. a=0,p=0,n=1,l=1,e=1 (see tournament.dart).
void _configure(String config) {
  for (final kv in config.split(',').where((s) => s.contains('='))) {
    final [key, value] = kv.split('=');
    final v = int.parse(value);
    switch (key) {
      case 'a':
        tac.adaptiveSearch = v != 0;
      case 'r':
        tac.probeReduction = v;
      case 'q':
        tac.probeQuietOnly = v != 0;
      case 'e':
        tac.checkExtension = v != 0;
      case 'p':
        tac.probeEnabled = v != 0;
      case 'n':
        tac.nullMovePruning = v != 0;
      case 'l':
        tac.lateMoveReductions = v != 0;
      default:
        throw ArgumentError('unknown tactical setting $key');
    }
  }
}

/// Solved = best move from some depth onwards; reports that depth and its time.
String _summary(List<Iteration> its, String bm) {
  if (its.isEmpty) return 'no depth completed';
  final last = its.last;
  var from = its.length;
  while (from > 0 && its[from - 1].$2 == bm) {
    from--;
  }
  final tail = 'final ${last.$2} ${last.$3} ${last.$1}';
  if (from == its.length) return 'MISS  $tail';
  return 'solved ${its[from].$1} at ${its[from].$4} ms; $tail';
}

/// Usage: dart run experiments/tactical_positions.dart [ms] [tactical config] [name filter] [engines, e.g. regular,forcing,tactical]
Future<void> main(List<String> args) async {
  final ms = args.isNotEmpty ? int.parse(args[0]) : 5000;
  final config = args.length > 1 ? args[1] : '';
  final filter = args.length > 2 && args[2] != 'all' ? args[2] : '';
  final engines = (args.length > 3 ? args[3] : 'regular,forcing').split(',');
  final selected = [for (final p in positions) if (p.$1.contains(filter)) p];

  final jobs = [
    for (final (_, fen, _) in selected)
      for (final engine in engines) (engine, fen),
  ];
  final results = List<List<Iteration>?>.filled(jobs.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < jobs.length) {
      final i = next++;
      final (engine, fen) = jobs[i];
      results[i] = await Isolate.run(() => _search(engine, fen, ms, config));
    }
  }

  // Engines with worker isolates (w<N>) leave fewer cores for parallel positions.
  final maxWorkers = engines
      .map((e) => int.tryParse(RegExp(r'w(\d+)$').firstMatch(e)?[1] ?? '') ?? 1)
      .reduce(max);
  final concurrency = max(1, 16 ~/ maxWorkers);
  await Future.wait([for (var i = 0; i < min(concurrency, jobs.length); i++) worker()]);

  print('$ms ms per position, tactical config "${config.isEmpty ? 'defaults' : config}"');
  final solved = {for (final e in engines) e: 0};
  for (var i = 0; i < selected.length; i++) {
    final (name, _, bm) = selected[i];
    print('${name.padRight(8)} bm ${bm.padRight(5)}');
    for (var k = 0; k < engines.length; k++) {
      final engine = engines[k];
      final its = results[i * engines.length + k]!;
      final s = _summary(its, bm);
      if (!s.startsWith('MISS') && its.isNotEmpty) solved[engine] = solved[engine]! + 1;
      print('  ${engine.padRight(8)} $s');
    }
  }
  print('solved: ${[for (final e in engines) '$e ${solved[e]}/${selected.length}'].join(', ')}');
}

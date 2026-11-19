import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:chess/chess.dart';
import 'package:chess_engine/src/eval.dart';
import 'package:chess_engine/src/mcts.dart';
import 'package:chess_engine/src/mcts_alphabeta.dart' show PriorPool;
import 'package:chess_engine/src/mcts_hybrid.dart';
import 'package:chess_engine/src/mcts_new.dart' as mcts_new;
import 'package:chess_engine/src/mcts_root.dart';
import 'package:chess_engine/src/pure_mcts.dart';
import 'package:chess_engine/src/search_tactical.dart' as tactical;
import 'package:chess_engine/src/search.dart';
import 'package:chess_engine/src/selective.dart';
import 'package:chess_engine/src/sss.dart';

typedef GameResult = ({
  int game,
  String result,
  String reason,
  int plies,
  List<int> hybridDepths,
  List<int> negamaxDepths,
  int overrides,
});

/// Experimental hybrid engine vs the regular alpha-beta negamax engine.
///
/// Engines: `sss` (negamax max / SSS* min), `sss-max` (SSS* max / negamax min), `mtdf`
/// (MTD(f) root over zero-width alpha-beta), `bns` (Best Node Search root over zero-width
/// alpha-beta), `bns-mcts` (BNS with test values guided by a UCT prepass), all in lib/src/sss.dart, or `mcts` (negamax
/// max / MCTS min, lib/src/mcts.dart), or `selective` (selective PVS: aspiration, null move,
/// late move reductions, check extension) and `pvs` (the same with only aspiration), both in
/// lib/src/selective.dart, or `mcts-root` (MCTS over root moves, each pull deepening that
/// move's alpha-beta search, lib/src/mcts_root.dart), or `pure-mcts` (UCT with playouts where
/// only quiet moves spend depth, lib/src/pure_mcts.dart; samples sets the quiet depth).
/// Each random opening is played twice with colours swapped.
/// Both engines get the same time per move. Every game runs in its own isolate, at most
/// [concurrency] at a time. Games longer than maxPlies are adjudicated by static eval (a side
/// ahead by more than 300 centipawns wins, otherwise a draw), which bounds the run time.
/// maxPlies 0 plays every game to the end (mate or a draw rule).
///
/// Usage: dart run experiments/tournament.dart [sss|sss-max|mtdf|bns|bns-mcts|mcts|selective|pvs|mcts-root|pure-mcts|tactical] [pairs] [msPerMove] [seed] [maxPlies] [concurrency] [samples]
Future<void> main(List<String> args) async {
  final engine = args.isNotEmpty ? args[0] : 'sss';
  if (!const [
    'sss',
    'sss-max',
    'mtdf',
    'bns',
    'bns-mcts',
    'mcts',
    'selective',
    'pvs',
    'mcts-root',
    'pure-mcts',
    'tactical',
    'mcts-new',
    'hybrid-mcts',
  ].contains(engine)) {
    throw ArgumentError(
      'engine must be sss, sss-max, mtdf, bns, bns-mcts, mcts, selective, pvs, mcts-root, pure-mcts or tactical, got $engine',
    );
  }
  final pairs = args.length > 1 ? int.parse(args[1]) : 8;
  final msPerMove = args.length > 2 ? int.parse(args[2]) : 100;
  final seed = args.length > 3 ? int.parse(args[3]) : 1;
  final maxPlies = args.length > 4 ? int.parse(args[4]) : 160;
  final games = 2 * pairs;
  final concurrency = min(games, args.length > 5 ? int.parse(args[5]) : 16);
  final samples = args.length > 6 ? int.parse(args[6]) : 4;
  // tactical only, e.g. a=0,r=2,q=1,e=1 (adaptive, probe reduction, quiet-only probes, check extension)
  final config = args.length > 7 ? args[7] : '';

  final boundSec = maxPlies <= 0
      ? null
      : (games / concurrency).ceil() * maxPlies * msPerMove / 1000;
  final name = switch (engine) {
    'sss' => 'negamax max / SSS* min',
    'sss-max' => 'SSS* max / negamax min',
    'mtdf' => 'MTD(f) root',
    'bns' => 'Best Node Search root',
    'bns-mcts' => 'Best Node Search root with MCTS guesses',
    'selective' => 'selective PVS',
    'pvs' => 'PVS + aspiration, no selectivity',
    'mcts-root' => 'MCTS at root, alpha-beta in the tree',
    'pure-mcts' => 'pure MCTS, quiet depth $samples',
    'tactical' => 'tactical-probe negamax (search_tactical.dart)',
    'mcts-new' => 'MCTS with alpha-beta priors (mcts_new.dart), $samples ms per prior',
    'hybrid-mcts' =>
      'alpha-beta for half the time, then MCTS to refute its move (mcts_hybrid.dart), $samples ms per prior',
    _ => 'negamax max / MCTS min, $samples samples',
  };
  print(
    'Hybrid ($name) vs negamax, $games games, $msPerMove ms/move, '
    '${maxPlies <= 0 ? 'no ply cap' : 'max $maxPlies plies'}, '
    'seed $seed, $concurrency concurrent',
  );
  print(
    boundSec == null
        ? 'No ply cap: games run until mate or a draw rule\n'
        : 'Worst-case wall time: ~${boundSec.toStringAsFixed(0)} s\n',
  );

  final wall = Stopwatch()..start();
  final results = <GameResult>[];
  var next = 0;
  var wins = 0, draws = 0, losses = 0;
  Future<void> runner() async {
    while (next < games) {
      final g = next++;
      final r = await Isolate.run(
        () => _playGame(g, engine, seed, msPerMove, samples, maxPlies, config),
      );
      results.add(r);
      switch (r.result) {
        case 'win':
          wins++;
        case 'loss':
          losses++;
        default:
          draws++;
      }
      print(
        '[${results.length}/$games] game ${g + 1}: ${r.result} by ${r.reason} in ${r.plies} plies '
        '| running score +$wins =$draws -$losses (${wall.elapsed.inSeconds} s)'
        '${r.overrides > 0 ? ', MCTS overrode alpha-beta ${r.overrides}x' : ''}',
      );
    }
  }

  await Future.wait([for (var i = 0; i < concurrency; i++) runner()]);
  results.sort((a, b) => a.game.compareTo(b.game));

  wins = 0;
  draws = 0;
  losses = 0;
  final reasons = <String, int>{};
  final hybridDepths = <int>[];
  final negamaxDepths = <int>[];
  for (final r in results) {
    hybridDepths.addAll(r.hybridDepths);
    negamaxDepths.addAll(r.negamaxDepths);
    switch (r.result) {
      case 'win':
        wins++;
      case 'loss':
        losses++;
      default:
        draws++;
    }
    reasons['${r.result}: ${r.reason}'] =
        (reasons['${r.result}: ${r.reason}'] ?? 0) + 1;
    print(
      'game ${r.game + 1} (opening ${r.game ~/ 2 + 1}, hybrid ${r.game.isEven ? 'white' : 'black'}): '
      '${r.result} by ${r.reason} in ${r.plies} plies',
    );
  }

  final score = (wins + draws / 2) / games;
  final elo = score <= 0 || score >= 1
      ? double.nan
      : -400 * log(1 / score - 1) / ln10;
  print(
    '\nHybrid vs negamax: +$wins =$draws -$losses '
    '(${(score * 100).toStringAsFixed(1)}%, Elo diff ${elo.isNaN ? 'n/a' : elo.toStringAsFixed(0)})',
  );
  reasons.forEach((k, v) => print('  $k: $v'));
  String avg(List<int> xs) =>
      (xs.reduce((a, b) => a + b) / xs.length).toStringAsFixed(2);
  print(
    'Average depth reached (plies): hybrid ${avg(hybridDepths)}, negamax ${avg(negamaxDepths)}',
  );
  print('Wall time: ${(wall.elapsedMilliseconds / 1000).toStringAsFixed(1)} s');
}

Future<GameResult> _playGame(
  int game,
  String engine,
  int seed,
  int msPerMove,
  int samples,
  int maxPlies,
  String config,
) async {
  var workers = 1;
  var marginCp = 30;
  for (final kv in config.split(',').where((s) => s.contains('='))) {
    final [key, value] = kv.split('=');
    final v = int.parse(value);
    switch (key) {
      case 'w':
        workers = v;
      case 'm':
        marginCp = v;
      case 'a':
        tactical.adaptiveSearch = v != 0;
      case 'r':
        tactical.probeReduction = v;
      case 'q':
        tactical.probeQuietOnly = v != 0;
      case 'e':
        tactical.checkExtension = v != 0;
      case 'p':
        tactical.probeEnabled = v != 0;
      case 'n':
        tactical.nullMovePruning = v != 0;
      case 'l':
        tactical.lateMoveReductions = v != 0;
      default:
        throw ArgumentError('unknown tactical setting $key');
    }
  }
  final pair = game ~/ 2;
  final hybridColor = game.isEven ? Color.WHITE : Color.BLACK;
  final timeLimit = Duration(milliseconds: msPerMove);
  final chess = _opening(Random(seed * 1000003 + pair), 4);
  final hybridDepths = <int>[];
  final negamaxDepths = <int>[];
  final mctsRng = Random(seed * 1000003 + game + 500009);
  final pool = engine.contains('mcts') && workers > 1
      ? await PriorPool.spawn(workers)
      : null;
  var overrides = 0;

  while (!chess.game_over &&
      (maxPlies <= 0 || chess.history.length < maxPlies)) {
    final Move move;
    if (chess.turn == hybridColor) {
      if (engine == 'hybrid-mcts') {
        final mc = mcts_new.MonteCarlo()
          ..position = chess
          ..priorTimeLimit = Duration(milliseconds: samples)
          ..priorPool = pool;
        final r = await hybridSearch(mc, timeLimit, marginCp: marginCp);
        move = r.move;
        if (r.override) overrides++;
        hybridDepths.add(r.alphaBetaDepth);
      } else if (engine == 'mcts-new') {
        final mc = mcts_new.MonteCarlo()
          ..position = chess
          ..maxSimulations = 1 << 30
          ..timeLimit = timeLimit
          ..priorTimeLimit = Duration(milliseconds: samples)
          ..priorPool = pool;
        await mc.simulate();
        move = mc.emitPv()[0].move;
        hybridDepths.add(mc.numOfSimulations);
      } else if (engine == 'tactical') {
        move = tactical.iterativeDeepening(
          chess,
          64,
          timeLimit: timeLimit,
          verbose: false,
        )[0].move;
        hybridDepths.add(tactical.depthReached);
      } else if (engine == 'pure-mcts') {
        move = pureMctsSearch(
          chess,
          timeLimit: timeLimit,
          quietDepth: samples,
          rng: mctsRng,
        )[0].move;
        hybridDepths.add(pureMctsStats.treeDepth);
      } else if (engine == 'mcts-root') {
        move = mctsRootSearch(chess, timeLimit: timeLimit)[0].move;
        hybridDepths.add(mctsRootDepthReached);
      } else if (engine == 'selective' || engine == 'pvs') {
        final selective = engine == 'selective';
        move = selectiveSearch(
          chess,
          64,
          timeLimit: timeLimit,
          nullMove: selective,
          lateMoveReductions: selective,
          checkExtension: selective,
        )[0].move;
        hybridDepths.add(selectiveDepthReached);
      } else if (engine != 'mcts') {
        move = negamaxSssSearch(
          chess,
          64,
          timeLimit: timeLimit,
          sssAtMaxNodes: engine == 'sss-max',
          mtdfAtRoot: engine == 'mtdf',
          bnsAtRoot: engine == 'bns',
          bnsMcts: engine == 'bns-mcts',
        )[0].move;
        hybridDepths.add(sssDepthReached);
      } else {
        move = negamaxMctsSearch(
          chess,
          64,
          timeLimit: timeLimit,
          samples: samples,
        )[0].move;
      }
    } else {
      move = iterativeDeepening(
        chess,
        63,
        timeLimit: timeLimit,
        verbose: false,
      )[0].move;
      negamaxDepths.add(depthReached);
    }
    chess.move(move);
  }
  pool?.close();

  GameResult done(String result, String reason) => (
    game: game,
    result: result,
    reason: reason,
    plies: chess.history.length,
    hybridDepths: hybridDepths.isEmpty ? [0] : hybridDepths,
    negamaxDepths: negamaxDepths.isEmpty ? [0] : negamaxDepths,
    overrides: overrides,
  );

  if (chess.in_checkmate)
    return done(chess.turn == hybridColor ? 'loss' : 'win', 'checkmate');
  if (!chess.game_over) {
    final e = eval(chess, hybridColor);
    return done(
      e > 300
          ? 'win'
          : e < -300
          ? 'loss'
          : 'draw',
      'adjudication at $maxPlies plies',
    );
  }
  return done(
    'draw',
    chess.in_stalemate
        ? 'stalemate'
        : chess.insufficient_material
        ? 'insufficient material'
        : chess.in_threefold_repetition
        ? 'threefold repetition'
        : '50-move rule',
  );
}

/// A random opening of [plies] moves that doesn't end the game.
Chess _opening(Random rng, int plies) {
  while (true) {
    final chess = Chess();
    for (var i = 0; i < plies && !chess.game_over; i++) {
      final moves = chess.generate_moves();
      chess.make_move(moves[rng.nextInt(moves.length)]);
    }
    if (!chess.game_over) return chess;
  }
}

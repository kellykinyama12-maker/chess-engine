import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:chess/chess.dart';
import 'package:chess_engine/src/expectimax.dart';
import 'package:chess_engine/src/mcts.dart';
import 'package:chess_engine/src/search.dart';

typedef GameResult = ({int game, String result, String reason, int plies, List<int> moveMs});

/// Engine vs a uniformly random mover, alternating colours. Games run in parallel isolates.
///
/// Usage: dart run experiments/vs_random.dart [games] [maxDepth] [msPerMove] [seed] [alphabeta|expectimax|mcts] [workers] [samples] [iterations]
/// For alphabeta, plies = maxDepth + 1 (plus quiescence). For expectimax and mcts (max/mean
/// search), maxDepth counts engine-move/random-reply pairs, so plies = 2 * maxDepth.
/// samples (default 4) and iterations (default 1) only apply to mcts; msPerMove only to alphabeta.
Future<void> main(List<String> args) async {
  final games = args.isNotEmpty ? int.parse(args[0]) : 20;
  final maxDepth = args.length > 1 ? int.parse(args[1]) : 2;
  final timeMs = args.length > 2 ? int.parse(args[2]) : 1000;
  final seed = args.length > 3 ? int.parse(args[3]) : 1;
  final mode = args.length > 4 ? args[4] : 'alphabeta';
  final workers = min(games, args.length > 5 ? int.parse(args[5]) : Platform.numberOfProcessors);
  final samples = args.length > 6 ? int.parse(args[6]) : 4;
  final iterations = args.length > 7 ? int.parse(args[7]) : 1;
  if (!const ['alphabeta', 'expectimax', 'mcts'].contains(mode)) {
    throw ArgumentError('search must be alphabeta, expectimax or mcts, got $mode');
  }

  print(switch (mode) {
    'alphabeta' => 'Alpha-beta engine (${maxDepth + 1} plies + qsearch, '
        '$timeMs ms/move) vs random, $games games, seed $seed, $workers workers\n',
    'expectimax' => 'Expectimax engine (${2 * maxDepth} plies) vs random, '
        '$games games, seed $seed, $workers workers\n',
    _ => 'Max/mean engine (${2 * maxDepth} plies, $samples samples, $iterations iterations) '
        'vs random, $games games, seed $seed, $workers workers\n',
  });

  final wall = Stopwatch()..start();
  final batches = await Future.wait([
    for (var w = 0; w < workers; w++)
      Isolate.run(() => [
            for (var g = w; g < games; g += workers)
              _playGame(g, maxDepth, timeMs, seed, mode, samples, iterations)
          ]),
  ]);
  final results = batches.expand((b) => b).toList()..sort((a, b) => a.game.compareTo(b.game));

  var wins = 0, draws = 0, losses = 0;
  final reasons = <String, int>{};
  final winPlies = <int>[];
  final engineMoveMs = <int>[];

  for (final r in results) {
    switch (r.result) {
      case 'win':
        wins++;
        winPlies.add(r.plies);
      case 'loss':
        losses++;
      default:
        draws++;
    }
    engineMoveMs.addAll(r.moveMs);
    reasons['${r.result}: ${r.reason}'] = (reasons['${r.result}: ${r.reason}'] ?? 0) + 1;
    print('game ${r.game + 1} (engine ${r.game.isEven ? 'white' : 'black'}): '
        '${r.result} by ${r.reason} in ${r.plies} plies');
  }

  final score = (wins + draws / 2) / games * 100;
  print('\nEngine: +$wins =$draws -$losses (${score.toStringAsFixed(1)}%)');
  reasons.forEach((k, v) => print('  $k: $v'));
  if (winPlies.isNotEmpty) {
    winPlies.sort();
    final avg = winPlies.reduce((a, b) => a + b) / winPlies.length;
    print('Plies to win: avg ${avg.toStringAsFixed(1)}, '
        'min ${winPlies.first}, median ${winPlies[winPlies.length ~/ 2]}, max ${winPlies.last}');
  }
  final avgMs = engineMoveMs.reduce((a, b) => a + b) / engineMoveMs.length;
  print('Engine time per move: avg ${avgMs.toStringAsFixed(1)} ms over ${engineMoveMs.length} moves');
  print('Wall time: ${(wall.elapsedMilliseconds / 1000).toStringAsFixed(1)} s');
}

GameResult _playGame(
    int game, int maxDepth, int timeMs, int seed, String mode, int samples, int iterations) {
  final rng = Random(seed * 1000003 + game);
  final searchRng = Random(seed * 1000003 + game + 500009);
  final engineColor = game.isEven ? Color.WHITE : Color.BLACK;
  final timeLimit = Duration(milliseconds: timeMs);
  final moveMs = <int>[];
  final chess = Chess();

  while (!chess.game_over) {
    if (chess.turn == engineColor) {
      final sw = Stopwatch()..start();
      final move = switch (mode) {
        'alphabeta' =>
          iterativeDeepening(chess, maxDepth, timeLimit: timeLimit, verbose: false)[0].move,
        'expectimax' => expectimaxSearch(chess, maxDepth)[0].move,
        _ => maxMeanSearch(chess, maxDepth,
                samples: samples, iterations: iterations, rng: searchRng)[0]
            .move,
      };
      moveMs.add(sw.elapsedMilliseconds);
      chess.move(move);
    } else {
      final moves = chess.generate_moves();
      chess.move(moves[rng.nextInt(moves.length)]);
    }
  }

  final plies = chess.history.length;
  if (chess.in_checkmate) {
    final result = chess.turn == engineColor ? 'loss' : 'win';
    return (game: game, result: result, reason: 'checkmate', plies: plies, moveMs: moveMs);
  }
  final reason = chess.in_stalemate
      ? 'stalemate'
      : chess.insufficient_material
          ? 'insufficient material'
          : chess.in_threefold_repetition
              ? 'threefold repetition'
              : '50-move rule';
  return (game: game, result: 'draw', reason: reason, plies: plies, moveMs: moveMs);
}

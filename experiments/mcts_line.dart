import 'package:chess/chess.dart';
import 'package:chess_engine/src/mcts_alphabeta.dart' show PriorPool;
import 'package:chess_engine/src/mcts_new.dart';
import 'package:chess_engine/src/mcts_prior.dart';

/// Runs mcts_new on each position along a line and prints the root statistics.
///
/// Usage: dart run experiments/mcts_line.dart [--no-rank-prior] [--no-ucb-prior] [--workers=N] [--typed] [simulations] [priorMs] [plies from end] SAN...
Future<void> main(List<String> allArgs) async {
  final typed = allArgs.contains('--typed');
  final rankByPrior = !allArgs.contains('--no-rank-prior');
  final ucbUsePrior = !allArgs.contains('--no-ucb-prior');
  final workersArg = allArgs.where((a) => a.startsWith('--workers=')).firstOrNull;
  final workers = workersArg == null ? 1 : int.parse(workersArg.split('=')[1]);
  final pool = workers > 1 ? await PriorPool.spawn(workers) : null;
  final args = [for (final a in allArgs) if (!a.startsWith('--')) a];
  final sims = args.isNotEmpty ? int.parse(args[0]) : 200;
  final priorMs = args.length > 1 ? int.parse(args[1]) : 50;
  final last = args.length > 2 ? int.parse(args[2]) : 3;
  final line = args.length > 3
      ? args.sublist(3)
      : 'e4 e5 f4 d5 fxe5 Qh4+ Ke2 Qxe4+ Kf2 Bc5+ Kg3'.split(' ');

  final chess = Chess();
  final positions = <(String, String)>[];
  for (var i = 0; i <= line.length; i++) {
    positions.add((line.take(i).join(' '), chess.fen));
    if (i < line.length && !chess.move(line[i])) throw ArgumentError('illegal ${line[i]}');
  }

  for (final (moves, fen) in positions.skip(positions.length - last)) {
    final mc = (typed ? TypedMonteCarlo() : MonteCarlo())
      ..position = Chess.fromFEN(fen)
      ..maxSimulations = sims
      ..rankByPrior = rankByPrior
      ..ucbUsePrior = ucbUsePrior
      ..priorTimeLimit = Duration(milliseconds: priorMs)
      ..priorPool = pool;
    final sw = Stopwatch()..start();
    await mc.simulate();
    final rootMoves = mc.emitPv();
    final edges = mc.currentNode().children;
    print('\n=== after $moves  ($sims simulations, ${sw.elapsedMilliseconds} ms)');
    print('best ${rootMoves[0].san} score ${rootMoves[0].score}  pv ${mc.pv.join(' ')}');
    final byPrior = edges.reduce((a, b) => a.prior >= b.prior ? a : b);
    print('best by prior: ${mc.position.move_to_san(byPrior.move)} (${mc.rewardToValue(byPrior.prior)} cp)');
    final top = [...edges]..sort((a, b) => b.visits.compareTo(a.visits));
    for (final e in top.take(5)) {
      print('  ${mc.position.move_to_san(e.move).padRight(7)} visits ${e.visits.toString().padLeft(4)}'
          '  Q ${e.meanActionValue.toStringAsFixed(3)}'
          '  P ${e.prior.toStringAsFixed(3)} (${mc.rewardToValue(e.prior)} cp)');
    }
  }
  pool?.close();
}

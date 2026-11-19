import 'package:chess/chess.dart';

import 'mcts_alphabeta.dart' show sameMove;
import 'mcts_new.dart';
import 'search.dart' as ab;

typedef HybridResult = ({
  Move move,
  bool override,
  int alphaBetaDepth,
  int simulations,
});

/// Spends [alphaBetaShare] of [total] on the regular alpha-beta search, then the rest on
/// MCTS ([mc], already configured) with alpha-beta's best move anchored at its deep score.
/// The MCTS choice replaces alpha-beta's only if its backed-up prior is [marginCp] better.
Future<HybridResult> hybridSearch(
  MonteCarlo mc,
  Duration total, {
  double alphaBetaShare = 0.5,
  int marginCp = 30,
}) async {
  final sw = Stopwatch()..start();
  final abBest = ab.iterativeDeepening(
    mc.position,
    63,
    timeLimit: total * alphaBetaShare,
    verbose: false,
  )[0];
  final depth = ab.depthReached;
  HybridResult result(Move move, bool override, int sims) => (
    move: move,
    override: override,
    alphaBetaDepth: depth,
    simulations: sims,
  );
  if (sw.elapsed >= total) return result(abBest.move, false, 0);

  await mc.createRoot();
  final root = mc.currentNode();
  Edge edgeOf(Move m) => root.children.firstWhere((e) => sameMove(m, e.move));
  edgeOf(abBest.move).prior = mc.valueToReward(abBest.score);

  var sims = 0;
  while (sw.elapsed < total) {
    mc.treePolicy();
    mc.backup(await mc.playOutPolicy());
    sims++;
  }

  final mctsBest = mc.emitPv().first.move;
  if (sameMove(abBest.move, mctsBest)) return result(abBest.move, false, sims);
  final gain =
      mc.rewardToValue(edgeOf(mctsBest).prior) -
      mc.rewardToValue(edgeOf(abBest.move).prior);
  return gain >= marginCp
      ? result(mctsBest, true, sims)
      : result(abBest.move, false, sims);
}

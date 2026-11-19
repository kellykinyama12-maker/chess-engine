import 'dart:isolate';
import 'dart:math';

import 'package:chess/chess.dart';
import 'package:chess_engine/src/search.dart' as ab;
import 'package:chess_engine/src/search_tactical.dart' as tac;
import 'package:chess_engine/src/selective.dart';

/// One searched ply: position before the move, who searched, move played, mover's score.
typedef Ply = ({String fen, String engine, String san, int score});

/// A position where the mover's own score fell after its move, re-checked by long searches.
typedef Candidate = ({
  String fen,
  String engine,
  String played,
  int drop,
  String bm,
  int bestScore,
  int playedScore,
  bool quiet,
});

const _cap = 3000;

/// Plays tactical vs regular from random openings and logs every ply.
List<Ply> _playGame(int game, int seed, int ms, String config) {
  _configure(config);
  final tacticalColor = game.isEven ? Color.WHITE : Color.BLACK;
  final chess = _opening(Random(seed * 1000003 + game ~/ 2), 4);
  final limit = Duration(milliseconds: ms);
  final plies = <Ply>[];
  while (!chess.game_over) {
    final fen = chess.fen;
    final tactical = chess.turn == tacticalColor;
    final (Move move, String san, int score) = tactical
        ? switch (tac.iterativeDeepening(chess, 64, timeLimit: limit, verbose: false)[0]) {
            final m => (m.move, m.san, m.score),
          }
        : switch (ab.iterativeDeepening(chess, 63, timeLimit: limit, verbose: false)[0]) {
            final m => (m.move, m.san, m.score),
          };
    plies.add((fen: fen, engine: tactical ? 'tactical' : 'regular', san: san, score: score));
    chess.move(move);
  }
  return plies;
}

/// Long selective search: best move and score, plus the score of [played] (mover's view).
Candidate _verify(Ply p, int drop, int ms) {
  final limit = Duration(milliseconds: ms);
  final chess = Chess.fromFEN(p.fen);
  final best = selectiveSearch(chess, 64, timeLimit: limit)[0];
  final playedMove = chess.generate_moves().firstWhere((m) => chess.move_to_san(m) == p.san);
  chess.make_move(playedMove);
  final reply = chess.game_over ? null : selectiveSearch(chess, 64, timeLimit: limit)[0];
  final playedScore = reply == null ? (chess.in_checkmate ? ab.mateScore : 0) : -reply.score;
  chess.undo_move();
  final bestMove = best.move;
  final capture = bestMove.captured != null || bestMove.promotion != null;
  chess.make_move(bestMove);
  final check = chess.in_check;
  return (
    fen: p.fen,
    engine: p.engine,
    played: p.san,
    drop: drop,
    bm: best.san.replaceAll(RegExp(r'[+#]'), ''),
    bestScore: best.score,
    playedScore: playedScore,
    quiet: !capture && !check,
  );
}

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

/// Mines tactical test positions from tactical-vs-regular games: plies after which the
/// mover's own next score fell by at least minDrop, kept if a long selective search finds a
/// different move at least minDrop better than the move played.
///
/// Usage: dart run experiments/mine_positions.dart [games] [msPerMove] [seed] [minDrop] [verifyMs] [tactical config]
Future<void> main(List<String> args) async {
  final games = args.isNotEmpty ? int.parse(args[0]) : 16;
  final ms = args.length > 1 ? int.parse(args[1]) : 100;
  final seed = args.length > 2 ? int.parse(args[2]) : 1;
  final minDrop = args.length > 3 ? int.parse(args[3]) : 150;
  final verifyMs = args.length > 4 ? int.parse(args[4]) : 10000;
  final config = args.length > 5 ? args[5] : 'a=0';

  final logs = await _pool([for (var g = 0; g < games; g++) () => _playGame(g, seed, ms, config)], 16);

  final suspects = <(Ply, int)>[];
  for (final plies in logs) {
    for (var i = 0; i + 2 < plies.length; i++) {
      final now = plies[i].score.clamp(-_cap, _cap);
      final later = plies[i + 2].score.clamp(-_cap, _cap);
      // Already lost or won: a further drop teaches nothing.
      if (now.abs() >= _cap) continue;
      if (now - later >= minDrop) suspects.add((plies[i], now - later));
    }
  }
  print('${logs.length} games, ${logs.fold(0, (n, l) => n + l.length)} plies, '
      '${suspects.length} suspects; verifying at $verifyMs ms');

  final checked = await _pool([for (final (p, d) in suspects) () => _verify(p, d, verifyMs)], 8);
  final kept = [
    for (final c in checked)
      if (c.bm != c.played.replaceAll(RegExp(r'[+#]'), '') &&
          c.bestScore.clamp(-_cap, _cap) - c.playedScore.clamp(-_cap, _cap) >= minDrop)
        c,
  ];
  print('${kept.length} confirmed (selective $verifyMs ms prefers another move by >= $minDrop)\n');
  for (final c in kept) {
    print("  // ${c.engine} played ${c.played} (${c.playedScore}), drop ${c.drop}; "
        "best ${c.bm} (${c.bestScore})${c.quiet ? ', quiet' : ''}");
    print("  ('mined', '${c.fen}', '${c.bm}'),");
  }
}

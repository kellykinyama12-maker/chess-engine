import 'dart:math';

import 'package:chess/chess.dart';
import 'package:chess_engine/chess_engine.dart';
import 'package:chess_engine/src/eval.dart';
import 'package:chess_engine/src/expectimax.dart';
import 'package:chess_engine/src/mcts.dart';
import 'package:chess_engine/src/mcts_root.dart';
import 'package:chess_engine/src/pure_mcts.dart';
import 'package:chess_engine/src/search.dart';
import 'package:chess_engine/src/see.dart';
import 'package:chess_engine/src/selective.dart';
import 'package:chess_engine/src/sss.dart';
import 'package:test/test.dart';

Move _san(Chess chess, String san) =>
    (chess.moves({'asObjects': true}) as List<Move>).firstWhere(
      (m) => chess.move_to_san(m) == san,
    );

void main() {
  test('calculate', () {
    expect(calculate(), 42);
  });

  test('is_capture checks the given move', () {
    final chess = Chess();

    expect(chess.is_capture('e4'), isFalse);
    chess.move('e4');
    chess.move('d5');
    expect(chess.is_capture('exd5'), isTrue);
    expect(chess.is_capture('e5'), isFalse);
    expect(chess.is_capture({'from': 'e4', 'to': 'd5'}), isTrue);

    final captures = (chess.moves({'asObjects': true}) as List<Move>)
        .where(chess.is_capture)
        .toList();
    expect(captures.length, 1);
  });

  test('is_capture detects en passant', () {
    final chess = Chess();
    chess.move('e4');
    chess.move('a6');
    chess.move('e5');
    chess.move('d5');

    expect(chess.is_capture('exd6'), isTrue);
  });

  test('eval is symmetric at the start', () {
    final chess = Chess();
    expect(eval(chess, Chess.WHITE), 0);
    expect(eval(chess, Chess.BLACK), 0);
  });

  test('eval rewards central development, relative to side', () {
    final chess = Chess();
    chess.move('Nf3');
    expect(eval(chess, Chess.WHITE), greaterThan(0));
    expect(eval(chess, Chess.BLACK), -eval(chess, Chess.WHITE));

    chess.move('Nf6');
    expect(eval(chess, Chess.WHITE), 0);
  });

  group('see', () {
    test('pawn takes defended knight wins knight for pawn', () {
      final chess = Chess.fromFEN('4k3/8/4p3/3n4/4P3/8/8/4K3 w - - 0 1');
      expect(see(chess, _san(chess, 'exd5')), 200);
    });

    test('queen takes defended pawn loses the queen', () {
      final chess = Chess.fromFEN('4k3/8/2p5/3p4/8/8/8/3QK3 w - - 0 1');
      expect(see(chess, _san(chess, 'Qxd5')), -800);
    });

    test('x-ray rook behind rook wins the pawn', () {
      final chess = Chess.fromFEN('3rk3/8/8/3p4/8/8/3R4/3RK3 w - - 0 1');
      expect(see(chess, _san(chess, 'Rxd5')), 100);
    });

    test('king cannot recapture a defended square', () {
      final chess = Chess.fromFEN('8/8/8/3k4/4p3/8/2B5/1B2K3 w - - 0 1');
      expect(see(chess, _san(chess, 'Bxe4+')), 100);
    });

    test('en passant', () {
      final chess = Chess.fromFEN('4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1');
      expect(see(chess, _san(chess, 'exd6')), 100);
    });
  });

  group('zobrist', () {
    void walk(Chess chess, int depth) {
      if (depth == 0) return;
      for (final m in chess.moves({'asObjects': true}) as List<Move>) {
        final before = chess.zobrist;
        chess.move(m);
        expect(chess.zobrist, chess.compute_zobrist(), reason: chess.fen);
        walk(chess, depth - 1);
        chess.undo_move();
        expect(chess.zobrist, before);
      }
    }

    test('incremental key matches full recompute on make and undo', () {
      for (final fen in [
        // Castling, en passant, captures.
        'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
        // Promotions, including capture-promotions.
        'n1n5/PPPk4/8/8/8/8/4Kppp/5N1N b - - 0 1',
        '4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1',
      ]) {
        walk(Chess.fromFEN(fen), 2);
      }
    });

    test('transpositions share a key', () {
      final a = Chess()
        ..move('Nf3')
        ..move('Nf6')
        ..move('Nc3');
      final b = Chess()
        ..move('Nc3')
        ..move('Nf6')
        ..move('Nf3');
      expect(a.zobrist, b.zobrist);
      expect(a.zobrist, isNot(Chess().zobrist));
    });

    test('repetitions and threefold', () {
      final chess = Chess();
      expect(chess.repetitions, 0);
      for (final m in ['Nf3', 'Nf6', 'Ng1', 'Ng8']) {
        chess.move(m);
      }
      expect(chess.repetitions, 1);
      expect(chess.in_threefold_repetition, isFalse);
      for (final m in ['Nf3', 'Nf6', 'Ng1', 'Ng8']) {
        chess.move(m);
      }
      expect(chess.repetitions, 2);
      expect(chess.in_threefold_repetition, isTrue);
    });
  });

  group('legal move generation perft', () {
    int perft(Chess chess, int depth) {
      final moves = chess.generate_moves();
      if (depth == 1) return moves.length;
      var nodes = 0;
      for (final m in moves) {
        chess.make_move(m);
        nodes += perft(chess, depth - 1);
        chess.undo_move();
      }
      return nodes;
    }

    const cases = {
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1': (4, 197281),
      'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1': (
        3,
        97862,
      ),
      // Horizontal en passant pin along the 5th rank.
      '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1': (5, 674624),
      'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1': (
        3,
        9467,
      ),
      'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8': (3, 62379),
      'r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10':
          (3, 89890),
      '8/PPP4k/8/8/8/8/4Kppp/8 w - - 0 1': (4, 89363),
    };

    cases.forEach((fen, expected) {
      test(fen, () {
        expect(perft(Chess.fromFEN(fen), expected.$1), expected.$2);
      });
    });
  });

  group('search', () {
    test('prefers the fastest mate and scores it by distance', () {
      final chess = Chess.fromFEN('6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1');
      final best = iterativeDeepening(chess, 3)[0];
      expect(best.san, 'Ra8#');
      expect(best.score, mateScore - 1);
      expect(isMateScore(best.score), isTrue);
    });

    test('mated side sees the mate distance', () {
      // Forced: 1...Kg8 2.Qg7#.
      final chess = Chess.fromFEN('7k/8/6KQ/8/8/8/8/8 b - - 0 1');
      final best = iterativeDeepening(chess, 2)[0];
      expect(best.san, 'Kg8');
      expect(best.score, -(mateScore - 2));
    });

    test(
      'time limit stops the search and keeps the last complete depth',
      () {
        final stopwatch = Stopwatch()..start();
        final moves = iterativeDeepening(
          Chess(),
          50,
          timeLimit: const Duration(milliseconds: 300),
        );
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
        // It may stop inside a depth or just after one finishes, depending on load.
        expect(depthReached, inInclusiveRange(1, 50));
        expect(moves, isNotEmpty);
      },
    );
  });

  group('expectimax', () {
    test('bestEvasionEval scores the best evasion, not the position in check', () {
      for (final fen in [
        // Queen check that the king can capture.
        '4k3/8/8/8/8/8/4q3/R3K3 w - - 0 1',
        // Knight check from d3 in a busy middlegame.
        'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2Nn1Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
        // Black in check.
        '4k3/8/8/1B6/8/8/8/4K3 b - - 0 1',
      ]) {
        final chess = Chess.fromFEN(fen);
        expect(chess.in_check, isTrue, reason: fen);
        final sign = chess.turn == Chess.WHITE ? 1 : -1;
        var best = -1 << 30;
        for (final m in chess.generate_moves()) {
          chess.make_move(m);
          best = max(best, sign * eval(chess, Chess.WHITE));
          chess.undo_move();
        }
        expect(sign * bestEvasionEval(chess)!, best, reason: fen);
      }
      final queenCheck = Chess.fromFEN('4k3/8/8/8/8/8/4q3/R3K3 w - - 0 1');
      expect(
        bestEvasionEval(queenCheck)!,
        greaterThan(eval(queenCheck, Chess.WHITE) + 800),
        reason: 'Kxe2 wins the queen',
      );
    });

    test('bestEvasionEval is null when checkmated', () {
      final chess = Chess.fromFEN('R5k1/5ppp/8/8/8/8/5PPP/6K1 b - - 0 1');
      expect(bestEvasionEval(chess), isNull);
    });

    test('evalDelta matches a full re-evaluation', () {
      for (final fen in [
        'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
        'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R b KQkq - 0 1',
        'n1n5/PPPk4/8/8/8/8/4Kppp/5N1N b - - 0 1',
        'n1n5/PPPk4/8/8/8/8/4Kppp/5N1N w - - 0 1',
        '4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1',
      ]) {
        final chess = Chess.fromFEN(fen);
        final before = eval(chess, Chess.WHITE);
        for (final m in chess.generate_moves()) {
          chess.make_move(m);
          expect(
            before + evalDelta(m),
            eval(chess, Chess.WHITE),
            reason: chess.fen,
          );
          chess.undo_move();
        }
      }
    });
    test('plays mate in one', () {
      final chess = Chess.fromFEN('6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1');
      final best = expectimaxSearch(chess, 1)[0];
      expect(best.san, 'Ra8#');
      expect(best.score, mateScore - 1);
    });

    test('takes a free queen', () {
      final chess = Chess.fromFEN('4k3/8/8/3q4/8/8/8/3QK3 w - - 0 1');
      expect(expectimaxSearch(chess, 1)[0].san, 'Qxd5');
    });
  });

  for (final (sssAtMax, mtdf, label) in [
    (false, false, 'SSS* at min nodes'),
    (true, false, 'SSS* at max nodes'),
    (false, true, 'MTD(f) root'),
  ]) {
    group('negamax/SSS* hybrid ($label)', () {
      test('plays mate in one', () {
        final chess = Chess.fromFEN('6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1');
        final best = negamaxSssSearch(
          chess,
          3,
          sssAtMaxNodes: sssAtMax,
          mtdfAtRoot: mtdf,
        )[0];
        expect(best.san, 'Ra8#');
        expect(best.score, mateScore - 1);
      });

      for (final fen in [
        Chess.DEFAULT_POSITION,
        'r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4',
        'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
      ]) {
        test('root score equals alpha-beta at depths 1-4: $fen', () {
          for (var plies = 1; plies <= 4; plies++) {
            final chess = Chess.fromFEN(fen);
            resetSearchState();
            final alphaBeta = rootMovesSearch(chess, plies - 1)[0];
            final hybrid = negamaxSssSearch(
              chess,
              plies,
              sssAtMaxNodes: sssAtMax,
              mtdfAtRoot: mtdf,
            )[0];
            expect(hybrid.score, alphaBeta.score, reason: '$plies plies');
          }
        });
      }

      test('stops at the time limit', () {
        final stopwatch = Stopwatch()..start();
        final moves = negamaxSssSearch(
          Chess(),
          64,
          timeLimit: const Duration(milliseconds: 200),
          sssAtMaxNodes: sssAtMax,
          mtdfAtRoot: mtdf,
        );
        expect(stopwatch.elapsedMilliseconds, lessThan(1500));
        expect(moves, isNotEmpty);
      });
    });
  }

  for (final (withMcts, label) in [
    (false, 'Best Node Search root'),
    (true, 'Best Node Search root with MCTS guesses'),
  ]) {
    group(label, () {
      List<RootMove> run(Chess chess, int plies, [Duration? timeLimit]) =>
          negamaxSssSearch(
            chess,
            plies,
            timeLimit: timeLimit,
            bnsAtRoot: !withMcts,
            bnsMcts: withMcts,
          );

      test('plays mate in one', () {
        final chess = Chess.fromFEN('6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1');
        expect(run(chess, 3)[0].san, 'Ra8#');
      });

      for (final fen in [
        Chess.DEFAULT_POSITION,
        'r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4',
        'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
      ]) {
        test('picks a move as good as alpha-beta\'s best at depths 1-4: $fen', () {
          for (var plies = 1; plies <= 4; plies++) {
            final chess = Chess.fromFEN(fen);
            resetSearchState();
            final bestScore = rootMovesSearch(chess, plies - 1)[0].score;
            final bns = run(chess, plies)[0];
            // Full-window search of just the chosen move gives its exact value.
            resetSearchState();
            final chosen = rootMovesSearch(chess, plies - 1, [bns])[0];
            expect(chosen.score, bestScore, reason: '$plies plies: ${bns.san}');
            expect(
              bns.score,
              lessThanOrEqualTo(bestScore),
              reason: 'lower bound',
            );
          }
        });
      }

      test('stops at the time limit', () {
        final stopwatch = Stopwatch()..start();
        final moves = run(Chess(), 64, const Duration(milliseconds: 200));
        expect(stopwatch.elapsedMilliseconds, lessThan(1500));
        expect(moves, isNotEmpty);
      });
    });
  }

  group('selective PVS', () {
    test('null move round-trips position and hash', () {
      final chess = Chess.fromFEN(
        'rnbqkbnr/pppp1ppp/8/4pP2/8/8/PPPPP1PP/RNBQKBNR b KQkq e6 0 2',
      );
      final fen = chess.fen;
      final key = chess.zobrist;
      chess.make_null_move();
      expect(chess.zobrist, chess.compute_zobrist());
      expect(chess.turn, Color.WHITE);
      chess.undo_null_move();
      expect(chess.fen, fen);
      expect(chess.zobrist, key);
    });

    test('plays mate in one', () {
      final chess = Chess.fromFEN('6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1');
      final best = selectiveSearch(chess, 4)[0];
      expect(best.san, 'Ra8#');
      expect(best.score, mateScore - 1);
    });

    for (final fen in [
      Chess.DEFAULT_POSITION,
      'r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4',
      'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
    ]) {
      test('without selectivity, equals alpha-beta at depths 1-5: $fen', () {
        for (var plies = 1; plies <= 5; plies++) {
          final chess = Chess.fromFEN(fen);
          resetSearchState();
          final alphaBeta = rootMovesSearch(chess, plies - 1)[0];
          final pvs = selectiveSearch(
            chess,
            plies,
            nullMove: false,
            lateMoveReductions: false,
            checkExtension: false,
          )[0];
          expect(pvs.score, alphaBeta.score, reason: '$plies plies');
        }
      });
    }

    test('stops at the time limit and leaves the position unchanged', () {
      final chess = Chess.fromFEN(
        'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
      );
      final fen = chess.fen;
      final stopwatch = Stopwatch()..start();
      final moves = selectiveSearch(
        chess,
        64,
        timeLimit: const Duration(milliseconds: 200),
      );
      expect(stopwatch.elapsedMilliseconds, lessThan(1500));
      expect(moves, isNotEmpty);
      expect(chess.fen, fen);
    });
  });

  group('pure MCTS', () {
    const kiwipete =
        'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1';

    test('only quiet moves spend the playout depth', () {
      final chess = Chess.fromFEN(kiwipete);
      final fen = chess.fen;
      final rng = Random(1);
      var noisyPlies = 0;
      for (var i = 0; i < 300; i++) {
        final r = quietRollout(chess, 3, rng);
        expect(r.quietMoves, lessThanOrEqualTo(3));
        expect(r.reward, inInclusiveRange(0, 1));
        noisyPlies += r.plies - r.quietMoves;
        expect(chess.fen, fen);
      }
      expect(
        noisyPlies,
        greaterThan(0),
        reason: 'captures were played for free',
      );
    });

    test('a quiet position with no budget is evaluated immediately', () {
      final r = quietRollout(Chess(), 0, Random(1));
      expect(r.plies, 0);
      expect(r.reward, 0.5);
    });

    test('captures are resolved even with no budget left', () {
      // White's free queen capture must be played before evaluating.
      final chess = Chess.fromFEN('4k3/8/8/3q4/8/8/8/3QK3 w - - 0 1');
      final r = quietRollout(chess, 0, Random(1));
      expect(r.plies, greaterThan(0));
      expect(r.quietMoves, 0);
      expect(r.reward, greaterThan(0.9));
    });

    test('an evasion is played rather than evaluating a position in check', () {
      final chess = Chess.fromFEN('4k3/8/8/1B6/8/8/8/4K3 b - - 0 1');
      final r = quietRollout(chess, 0, Random(1));
      expect(r.plies, 1);
      expect(r.quietMoves, 0);
    });

    test('plays mate in one', () {
      final chess = Chess.fromFEN('6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1');
      expect(
        pureMctsSearch(chess, iterations: 2000, rng: Random(1))[0].san,
        'Ra8#',
      );
    });

    test('takes a free queen', () {
      final chess = Chess.fromFEN('4k3/8/8/3q4/8/8/8/3QK3 w - - 0 1');
      expect(
        pureMctsSearch(chess, iterations: 2000, rng: Random(1))[0].san,
        'Qxd5',
      );
    });

    test('stops at the time limit and leaves the position unchanged', () {
      final chess = Chess.fromFEN(kiwipete);
      final fen = chess.fen;
      final stopwatch = Stopwatch()..start();
      final moves = pureMctsSearch(
        chess,
        timeLimit: const Duration(milliseconds: 200),
        rng: Random(1),
      );
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      expect(moves, isNotEmpty);
      expect(chess.fen, fen);
    });
  });

  group('MCTS root over alpha-beta', () {
    test('plays mate in one', () {
      final chess = Chess.fromFEN('6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1');
      final best = mctsRootSearch(chess, maxPulls: 50)[0];
      expect(best.san, 'Ra8#');
      expect(best.score, mateScore - 1);
    });

    test('takes a free queen', () {
      final chess = Chess.fromFEN('4k3/8/8/3q4/8/8/8/3QK3 w - - 0 1');
      expect(mctsRootSearch(chess, maxPulls: 50)[0].san, 'Qxd5');
    });

    test('stops at the time limit and leaves the position unchanged', () {
      final chess = Chess.fromFEN(
        'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
      );
      final fen = chess.fen;
      final stopwatch = Stopwatch()..start();
      final moves = mctsRootSearch(
        chess,
        timeLimit: const Duration(milliseconds: 200),
      );
      expect(stopwatch.elapsedMilliseconds, lessThan(1500));
      expect(moves, isNotEmpty);
      expect(chess.fen, fen);
    });
  });

  group('negamax/MCTS hybrid', () {
    test('plays mate in one', () {
      final chess = Chess.fromFEN('6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1');
      final best = negamaxMctsSearch(chess, 3)[0];
      expect(best.san, 'Ra8#');
      expect(best.score, mateScore - 1);
    });

    test('equals minimax when min nodes see every reply', () {
      final chess = Chess.fromFEN(
        'r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4',
      );
      resetSearchState();
      final minimax = rootMovesSearch(chess, 1)[0];
      final hybrid = negamaxMctsSearch(
        chess,
        2,
        samples: 1000,
        widening: 1000,
      )[0];
      expect(hybrid.score, minimax.score);
    });

    test('stops at the time limit', () {
      final stopwatch = Stopwatch()..start();
      final moves = negamaxMctsSearch(
        Chess(),
        64,
        timeLimit: const Duration(milliseconds: 200),
      );
      expect(stopwatch.elapsedMilliseconds, lessThan(1500));
      expect(moves, isNotEmpty);
    });
  });

  group('max/mean (mcts.dart)', () {
    test('plays mate in one', () {
      final chess = Chess.fromFEN('6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1');
      final best = maxMeanSearch(chess, 1, rng: Random(1))[0];
      expect(best.san, 'Ra8#');
      expect(best.score, mateScore - 1);
    });

    test('takes a free queen', () {
      final chess = Chess.fromFEN('4k3/8/8/3q4/8/8/8/3QK3 w - - 0 1');
      expect(maxMeanSearch(chess, 1, rng: Random(1))[0].san, 'Qxd5');
    });

    test('equals expectimax when every reply is sampled', () {
      final chess = Chess.fromFEN(
        'r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4',
      );
      final exact = {
        for (final m in expectimaxSearch(chess, 2)) m.san: m.score,
      };
      final sampled = maxMeanSearch(chess, 2, samples: 1000, rng: Random(1));
      expect(sampled.length, exact.length);
      for (final m in sampled) {
        expect(m.score, closeTo(exact[m.san]!, 1), reason: m.san);
      }
    });

    test('more iterations add samples without changing an exhausted node', () {
      final chess = Chess.fromFEN('4k3/8/8/3q4/8/8/8/3QK3 w - - 0 1');
      final once = maxMeanSearch(chess, 1, samples: 100, rng: Random(1));
      final thrice = maxMeanSearch(
        chess,
        1,
        samples: 100,
        iterations: 3,
        rng: Random(1),
      );
      expect(
        [for (final m in thrice) m.score],
        [for (final m in once) m.score],
      );
    });
  });
}

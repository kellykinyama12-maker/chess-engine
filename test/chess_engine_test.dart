import 'package:chess/chess.dart';
import 'package:chess_engine/chess_engine.dart';
import 'package:chess_engine/src/eval.dart';
import 'package:chess_engine/src/search.dart';
import 'package:chess_engine/src/see.dart';
import 'package:test/test.dart';

Move _san(Chess chess, String san) => (chess.moves({'asObjects': true}) as List<Move>)
    .firstWhere((m) => chess.move_to_san(m) == san);

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
      final a = Chess()..move('Nf3')..move('Nf6')..move('Nc3');
      final b = Chess()..move('Nc3')..move('Nf6')..move('Nf3');
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
      'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1': (3, 97862),
      // Horizontal en passant pin along the 5th rank.
      '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1': (5, 674624),
      'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1': (3, 9467),
      'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8': (3, 62379),
      'r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10': (3, 89890),
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

    test('time limit stops mid-iteration and keeps the last complete depth', () {
      final stopwatch = Stopwatch()..start();
      final moves = iterativeDeepening(Chess(), 50,
          timeLimit: const Duration(milliseconds: 300));
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      expect(searchStopped, isTrue);
      expect(moves, isNotEmpty);
    });
  });
}

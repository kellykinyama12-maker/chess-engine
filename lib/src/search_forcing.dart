import 'package:chess/chess.dart';

import 'eval.dart';
import 'search.dart' show RootMove, mateScore, maxPly, isDrawn, mvvLva, sameMove;
import 'see.dart';

/// Forcing-line search: captures, promotions, checks and check evasions spend depth;
/// a quiet move ends its line there (scored by quiescence). No re-searches.

int nodes = 0;
int depthReached = 0;

final Stopwatch _clock = Stopwatch();
Duration? _limit;
bool _stopped = false;
bool _armed = false;

final List<List<Move>> _pv = List.generate(maxPly + 1, (_) => <Move>[]);

bool _visit() {
  nodes++;
  if (_armed && (nodes & 1023) == 0 && _limit != null && _clock.elapsed >= _limit!) {
    _stopped = true;
  }
  return _stopped;
}

/// Captures by MVV-LVA (losing ones last), then the rest.
List<Move> _order(Chess position, List<Move> moves, Move? first) {
  int score(Move m) {
    if (sameMove(first, m)) return 1 << 30;
    if (m.captured != null) {
      return (see(position, m) >= 0 ? 1 << 20 : -(1 << 20)) + mvvLva(m);
    }
    if (m.promotion == PieceType.QUEEN) return 1 << 19;
    return 0;
  }

  final scored = [for (final m in moves) (m, score(m))]..sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final s in scored) s.$1];
}

/// Stand pat plus non-losing captures; in check, every evasion is searched.
int _qsearch(Chess position, int alpha, int beta, int ply) {
  if (_visit()) return 0;
  if (isDrawn(position)) return 0;
  if (ply >= maxPly) return eval(position, position.turn);

  final inCheck = position.in_check;
  final List<Move> moves;
  if (inCheck) {
    moves = position.generate_moves();
    if (moves.isEmpty) return -mateScore + ply;
  } else {
    final standPat = eval(position, position.turn);
    if (standPat >= beta) return beta;
    if (standPat > alpha) alpha = standPat;
    moves = [
      for (final m in position.generate_moves())
        if (m.captured != null && see(position, m) >= 0) m,
    ];
  }

  for (final move in _order(position, moves, null)) {
    position.make_move(move);
    final score = -_qsearch(position, -beta, -alpha, ply + 1);
    position.undo_move();
    if (_stopped) return 0;
    if (score >= beta) return beta;
    if (score > alpha) alpha = score;
  }
  return alpha;
}

/// Searches a move (already made) from the opponent's side. Forcing moves recurse. A quiet
/// move recurses while [quiets] lasts; one that doesn't directly follow a quiet move starts a
/// new quiet run and also needs [runs]. Otherwise its line ends there. A non-capturing check
/// is forcing while [checks] lasts (spending one), and quiet after that.
int _child(
  Chess position,
  bool capture,
  bool evasion,
  bool afterQuiet,
  int depth,
  int quiets,
  int runs,
  int checks,
  int alpha,
  int beta,
  int ply,
) {
  final quietCheck = !capture && !evasion && position.in_check;
  final forcing = evasion || capture || (quietCheck && checks > 0);
  if (forcing) {
    final left = quietCheck ? checks - 1 : checks;
    return -_search(position, depth - 1, quiets, runs, left, false, -beta, -alpha, ply);
  }
  if (quiets > 0 && (afterQuiet || runs > 0)) {
    final left = afterQuiet ? runs : runs - 1;
    return -_search(position, depth - 1, quiets - 1, left, checks, true, -beta, -alpha, ply);
  }
  _pv[ply] = [];
  return -_qsearch(position, -beta, -alpha, ply);
}

/// [afterQuiet]: the move into this node was quiet, so a quiet reply continues its run.
int _search(
  Chess position,
  int depth,
  int quiets,
  int runs,
  int checks,
  bool afterQuiet,
  int alpha,
  int beta,
  int ply,
) {
  if (_visit()) return 0;
  _pv[ply] = [];
  if (ply > 0 && isDrawn(position)) return 0;
  if (depth <= 0 || ply >= maxPly) {
    _horizon = true;
    return _qsearch(position, alpha, beta, ply);
  }

  final moves = position.generate_moves();
  final evasion = position.in_check;
  if (moves.isEmpty) return evasion ? -mateScore + ply : 0;

  final pvMove = ply < _prevPv.length ? _prevPv[ply] : null;
  for (final move in _order(position, moves, pvMove)) {
    final capture = move.captured != null || move.promotion != null;
    position.make_move(move);
    final score = _child(
      position, capture, evasion, afterQuiet, depth, quiets, runs, checks, alpha, beta, ply + 1);
    position.undo_move();
    if (_stopped) return 0;
    if (score >= beta) return beta;
    if (score > alpha) {
      alpha = score;
      _pv[ply] = [move, ..._pv[ply + 1]];
    }
  }
  return alpha;
}

/// Set when a line reaches the depth limit; if an iteration never does, deeper ones change nothing.
bool _horizon = false;
List<Move> _prevPv = [];

/// Quiet-move budget of the deepest completed iteration.
int quietsReached = 0;

/// Iterates the quiet-move budget (0, 1, 2, ...) and, within each budget, the depth until
/// no line reaches the horizon or [maxDepth]. A line may hold at most [maxRuns] separate
/// runs of consecutive quiet moves and at most [maxChecks] non-capturing checks.
/// Root moves are returned best first.
List<RootMove> iterativeDeepening(
  Chess position,
  int maxDepth, {
  int maxQuiets = 64,
  int maxRuns = 1,
  int maxChecks = 64,
  Duration? timeLimit,
  bool verbose = true,
}) {
  nodes = 0;
  depthReached = 0;
  quietsReached = 0;
  _limit = timeLimit;
  _stopped = false;
  _armed = false;
  _prevPv = [];
  _clock
    ..reset()
    ..start();

  final root = [
    for (final m in _order(position, position.generate_moves(), null))
      RootMove(m, position.move_to_san(m), 0),
  ];
  if (root.isEmpty) return root;
  final evasion = position.in_check;

  // Each budget level resumes at the last depth completed by the previous one.
  var startDepth = 1;
  for (var quiets = 0; quiets <= maxQuiets; quiets++) {
    for (var depth = startDepth; depth <= maxDepth; depth++) {
      _horizon = false;
      var alpha = -mateScore - 1;
      final scores = <RootMove, int>{};
      RootMove? best;
      List<Move> pv = [];
      for (final r in root) {
        final capture = r.move.captured != null || r.move.promotion != null;
        position.make_move(r.move);
        final score = _child(
          position, capture, evasion, false, depth, quiets, maxRuns, maxChecks, alpha, mateScore + 1, 1);
        position.undo_move();
        if (_stopped) break;
        scores[r] = score;
        if (score > alpha) {
          alpha = score;
          best = r;
          pv = [r.move, ..._pv[1]];
        }
      }
      if (_stopped) {
        if (verbose) {
          print('quiets $quiets depth $depth: stopped after ${_clock.elapsedMilliseconds} ms');
        }
        return root;
      }
      // Fail-low moves tie with the best at alpha; List.sort isn't stable, so break ties explicitly.
      final index = {for (var i = 0; i < root.length; i++) root[i]: i};
      for (final r in root) {
        r.score = scores[r]!;
      }
      root.sort((a, b) {
        if (a == best) return -1;
        if (b == best) return 1;
        final c = b.score.compareTo(a.score);
        return c != 0 ? c : index[a]!.compareTo(index[b]!);
      });
      depthReached = depth;
      startDepth = depth;
      quietsReached = quiets;
      _prevPv = pv;
      _armed = true;
      if (verbose) {
        final sans = <String>[];
        for (final m in pv) {
          sans.add(position.move_to_san(m));
          position.make_move(m);
        }
        for (var i = 0; i < pv.length; i++) {
          position.undo_move();
        }
        print('quiets $quiets depth $depth: best ${root.first} pv ${sans.join(' ')} '
            '(${_clock.elapsedMilliseconds} ms)');
      }
      if (root.first.score >= mateScore - maxPly) return root;
      if (!_horizon) break;
    }
  }
  return root;
}

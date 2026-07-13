import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chess_tournament_manager/providers/tournament_provider.dart';
import 'package:chess_tournament_manager/models/player.dart';
import 'package:chess_tournament_manager/models/pairing.dart';

// ===========================================================================
// 3 sequential 5-round tournaments with the SAME 15 players. Captures the
// full handicap trajectory (in-tournament static vs cross-tournament
// recompute) and surfaces math anomalies from importNewTournament's formula.
//
// Goal: replicate the production export → "Start New" import cycle the user
// would run in the browser: finalize T1 → export state → fresh provider →
// importNewTournament → start T2 → ... 3 times.
//
// Convention reminder (verified in pairing_engine_test.dart):
//   - Player.handicap is "lower = stronger" — the displayed "+1.5 vs -0.5"
//     board label is from this convention.
//   - Tournament 1 in Parity mode pairs (i, i+1) after sorting ascending by
//     handicap, so strongest vs 2nd-strongest, etc. With 15 players (odd),
//     the WEAKEST player (highest handicap value) gets the BYE.
//   - R2+ Swiss with no-repeat rule + color balancing.
// ===========================================================================

TournamentProvider _newProvider() {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return TournamentProvider();
}

void _inject(
  TournamentProvider p,
  String id,
  String name, {
  double handicap = 0.0,
}) {
  p.players.add(Player(id: id, name: name, handicap: handicap, hadBye: false));
}

// Deterministic pseudo-random in [0, 1) keyed on a string. Mix is a 31-bit
// multiplicative hash — pure function, no time/random input → reproducible.
double _seedRand(String key) {
  int h = 0;
  for (int i = 0; i < key.length; i++) {
    h = ((h * 31) + key.codeUnitAt(i)) & 0x7FFFFFFF;
  }
  return (h % 1000000) / 1000000.0;
}

// Outcome distribution tuned: ~50% whiteWin, ~30% draw, ~20% blackWin.
GameResult _decideResult(String key) {
  final r = _seedRand(key);
  if (r < 0.50) return GameResult.whiteWin;
  if (r < 0.80) return GameResult.draw;
  return GameResult.blackWin;
}

Map<String, dynamic> _export(TournamentProvider p) {
  return {
    'players': p.players.map((pl) => pl.toJson()).toList(),
    'rounds': p.rounds.map((ro) => ro.toJson()).toList(),
    'currentRoundNumber': p.currentRoundNumber,
    'isTournamentStarted': p.isTournamentStarted,
    'tournamentName': p.tournamentName,
    'secondsRemaining': 0,
  };
}

void _printRoundSnapshot(TournamentProvider p, String label) {
  debugPrint('\n[$label] per-player state:');
  for (final pl in p.players) {
    debugPrint(
      '  ${pl.id}: hcp=${pl.handicap.toStringAsFixed(2)} '
      'earned=${pl.earnedPoints.toStringAsFixed(1)} '
      'opps=${pl.opponentsPlayed.length} '
      'byes=${pl.hadBye ? "Y" : "N"} '
      'colors=${pl.colorHistory.length}',
    );
  }
}

void _runTournament(TournamentProvider p, int tnum, int totalRounds) {
  for (int r = 1; r <= totalRounds; r++) {
    if (r > 1) p.startNextRound(20);
    final round = p.rounds.last;
    for (final pairing in round.pairings) {
      if (pairing.isBye) continue; // default GameResult.bye is auto-settled
      final key =
          'T${tnum}_R${r}_${pairing.whitePlayerId}_${pairing.blackPlayerId}';
      final result = _decideResult(key);
      p.updateResult(pairing.whitePlayerId, pairing.blackPlayerId, result);
    }
    p.submitRound();
  }
  p.finalizeTournament();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  // -------------------------------------------------------------------------
  test(
    '3 sequential tournaments with same 15 players — handicap trajectory & bug watch',
    () {
      // Determinism sanity (catches any future refactor that accidentally
      // introduces a non-deterministic PRNG):
      expect(_seedRand('sample-key-a'), equals(_seedRand('sample-key-a')));
      expect(_seedRand('T1_R1_p01_p02'), isNot(equals(_seedRand('empty-key'))));

      SharedPreferences.setMockInitialValues(<String, Object>{});

      const ids = [
        'p01',
        'p02',
        'p03',
        'p04',
        'p05',
        'p06',
        'p07',
        'p08',
        'p09',
        'p10',
        'p11',
        'p12',
        'p13',
        'p14',
        'p15',
      ];
      const initialHandicaps = [
        -1.0, -0.9, -0.8, -0.7, -0.6, //   strong tier (5)
        0.0, 0.1, 0.2, 0.3, 0.4, //   mid tier     (5)
        0.6, 0.8, 1.0, 1.2, 1.5, //   weak tier    (5)
      ];

      debugPrint('\n=== INITIAL HANDICAP DISTRIBUTION ===');
      for (int i = 0; i < ids.length; i++) {
        debugPrint('  ${ids[i]}: ${initialHandicaps[i].toStringAsFixed(2)}');
      }

      // ===== TOURNAMENT 1 =====
      final p1 = _newProvider();
      for (int i = 0; i < ids.length; i++) {
        _inject(p1, ids[i], 'Player ${i + 1}', handicap: initialHandicaps[i]);
      }
      p1.startTournament(20);

      final r1 = p1.rounds.single;
      debugPrint('\n[T1 R1 pairings] (sorted-by-handicap Parity):');
      for (final pair in r1.pairings) {
        if (pair.isBye) {
          debugPrint('  BYE: ${pair.whitePlayerId}');
        } else {
          final w = p1.players.firstWhere((p) => p.id == pair.whitePlayerId);
          final b = p1.players.firstWhere((p) => p.id == pair.blackPlayerId);
          debugPrint(
            '  w=${pair.whitePlayerId}(hcp=${w.handicap.toStringAsFixed(2)}) '
            'v b=${pair.blackPlayerId}(hcp=${b.handicap.toStringAsFixed(2)})',
          );
        }
      }

      _runTournament(p1, 1, 5);
      _printRoundSnapshot(p1, 'T1 FINAL');

      // ===== TOURNAMENT 2 =====
      final p2 = _newProvider();
      p2.importNewTournament(_export(p1));
      debugPrint('\n=== POST-IMPORT handicaps going into T2 ===');
      for (final pl in p2.players) {
        debugPrint(
          '  ${pl.id}: hcp=${pl.handicap.toStringAsFixed(2)} '
          'earned=${pl.earnedPoints.toStringAsFixed(1)} '
          'history=${pl.history.map((h) => h.toStringAsFixed(1)).join(",")}',
        );
      }

      // Right-after-import invariants for T2 (first import):
      //   - earnedPoints must be reset to 0
      //   - history should have length 1 (empty incoming + earnedPoints appended)
      for (final pl in p2.players) {
        expect(
          pl.earnedPoints,
          0.0,
          reason: '${pl.id} earnedPoints must be 0 right after import',
        );
        expect(
          pl.history.length,
          1,
          reason: '${pl.id} history length should be 1 after first import',
        );
      }

      debugPrint('\n=== UNCLAMPED FORMULA CHECK before T2 ===');
      for (final pl in p1.players) {
        final hist = pl.history;
        final histAvg = hist.isEmpty
            ? TournamentProvider.handicapCenter
            : hist.reduce((a, b) => a + b) / hist.length;
        final unclamped =
            TournamentProvider.handicapCenter -
            ((pl.earnedPoints + histAvg) / 2);
        final clamped = unclamped.clamp(-1.5, 1.5);
        final clampHit = (unclamped - clamped).abs() > 0.001;
        debugPrint(
          '  ${pl.id}: earned=${pl.earnedPoints.toStringAsFixed(1)} '
          'histAvg=${histAvg.toStringAsFixed(2)} '
          'unclamped=${unclamped.toStringAsFixed(2)} '
          'clamped=${clamped.toStringAsFixed(2)} '
          '${clampHit ? "  ⚠ CLAMP HIT" : ""}',
        );
      }

      p2.startTournament(20);
      _runTournament(p2, 2, 5);
      _printRoundSnapshot(p2, 'T2 FINAL');

      // ===== TOURNAMENT 3 =====
      final p3 = _newProvider();
      p3.importNewTournament(_export(p2));
      debugPrint('\n=== POST-IMPORT handicaps going into T3 ===');
      for (final pl in p3.players) {
        debugPrint(
          '  ${pl.id}: hcp=${pl.handicap.toStringAsFixed(2)} '
          'earned=${pl.earnedPoints.toStringAsFixed(1)} '
          'history=${pl.history.map((h) => h.toStringAsFixed(1)).join(",")}',
        );
      }

      // Right-after-import invariants for T3 (second import):
      //   - earnedPoints must still be 0
      //   - history should have length 2 (1 prior + earnedPoints appended)
      for (final pl in p3.players) {
        expect(
          pl.earnedPoints,
          0.0,
          reason: '${pl.id} earnedPoints must be 0 right after import',
        );
        expect(
          pl.history.length,
          2,
          reason: '${pl.id} history length should be 2 after second import',
        );
      }

      debugPrint('\n=== UNCLAMPED FORMULA CHECK before T3 ===');
      for (final pl in p2.players) {
        final hist = pl.history;
        final histAvg = hist.isEmpty
            ? TournamentProvider.handicapCenter
            : hist.reduce((a, b) => a + b) / hist.length;
        final unclamped =
            TournamentProvider.handicapCenter -
            ((pl.earnedPoints + histAvg) / 2);
        final clamped = unclamped.clamp(-1.5, 1.5);
        final clampHit = (unclamped - clamped).abs() > 0.001;
        debugPrint(
          '  ${pl.id}: earned=${pl.earnedPoints.toStringAsFixed(1)} '
          'histAvg=${histAvg.toStringAsFixed(2)} '
          'unclamped=${unclamped.toStringAsFixed(2)} '
          'clamped=${clamped.toStringAsFixed(2)} '
          '${clampHit ? "  ⚠ CLAMP HIT" : ""}',
        );
      }

      p3.startTournament(20);
      _runTournament(p3, 3, 5);
      _printRoundSnapshot(p3, 'T3 FINAL');

      // ===== TRAJECTORY TABLE =====
      // Architecture note: in-tournament handicap is FROZEN — it only moves
      // at import boundaries. So columns "T1-end", "T2-end", "T3-end"
      // intentionally equal the post-import columns they precede.
      debugPrint(
        '\n=== HANDICAP TRAJECTORY (init → T1-end → entering-T2 → T2-end '
        '→ entering-T3 → T3-end) ===',
      );
      debugPrint('id   | init  | T1-end | →T2→  | T2-end | →T3→  | T3-end');
      debugPrint('-' * 70);
      final initById = <String, double>{
        for (int i = 0; i < ids.length; i++) ids[i]: initialHandicaps[i],
      };
      double h(TournamentProvider p, String id) =>
          p.players.firstWhere((pl) => pl.id == id).handicap;
      for (final id in ids) {
        debugPrint(
          '$id | ${initById[id]!.toStringAsFixed(2)} '
          '| ${h(p1, id).toStringAsFixed(2)} '
          '| ${h(p2, id).toStringAsFixed(2)} '
          '| ${h(p2, id).toStringAsFixed(2)} '
          '| ${h(p3, id).toStringAsFixed(2)} '
          '| ${h(p3, id).toStringAsFixed(2)}',
        );
      }

      // ===== TOP 5 STANDINGS PER TOURNAMENT =====
      debugPrint('\n=== TOP 5 STANDINGS PER TOURNAMENT ===');
      for (final entry in <(String, TournamentProvider)>[
        ('T1', p1),
        ('T2', p2),
        ('T3', p3),
      ]) {
        final label = entry.$1;
        final provider = entry.$2;
        final ranked = provider.getRankedPlayers();
        debugPrint('[$label]');
        for (int i = 0; i < (ranked.length < 5 ? ranked.length : 5); i++) {
          final pl = ranked[i];
          final buch = provider.calculateBuchholz(pl);
          debugPrint(
            '  #${i + 1} ${pl.id} '
            'totalScore=${pl.totalScore.toStringAsFixed(2)} '
            '(earned=${pl.earnedPoints.toStringAsFixed(1)} '
            'hcp=${pl.handicap.toStringAsFixed(2)}) '
            'Buchholz=${buch.toStringAsFixed(2)}',
          );
        }
      }

      // ===== SANITY ASSERTS =====

      // Finite / non-NaN across every tournament.
      for (final pl in [...p1.players, ...p2.players, ...p3.players]) {
        expect(
          pl.handicap.isFinite,
          isTrue,
          reason: '${pl.id} hcp must be finite, got ${pl.handicap}',
        );
        expect(pl.handicap.isNaN, isFalse);
        expect(pl.earnedPoints.isFinite, isTrue);
        expect(
          pl.earnedPoints,
          inInclusiveRange(0.0, 5.0),
          reason: '${pl.id} earnedPoints cannot exceed 5 in a 5-round event',
        );
      }

      // importNewTournament must clamp hcp into [-1.5, 1.5].
      for (final pl in [...p2.players, ...p3.players]) {
        expect(
          pl.handicap,
          inInclusiveRange(-1.5, 1.5),
          reason:
              'post-import hcp must respect clamp; '
              '${pl.id} = ${pl.handicap}',
        );
      }

      // Post-import invariants now live RIGHT AFTER each
      // importNewTournament call (see above) — they'd be wrong here because
      // T2/T3 runs have already accumulated earnedPoints. The end-of-test
      // block keeps only invariants that hold independently of tournament
      // play (finite values, post-import hcp in clamp range).
    },
  );
}

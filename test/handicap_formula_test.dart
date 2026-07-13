import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chess_tournament_manager/providers/tournament_provider.dart';
import 'package:chess_tournament_manager/models/player.dart';

// ============================================================================
// Focused unit test for `TournamentProvider.importNewTournament`'s handicap
// formula — pins each formula outcome to its exact float value so a future
// change to either `handicapCenter` (the centring constant) OR the formula's
// structure fails this test immediately.
//
// The integration test in `three_tournament_handicap_evolution_test.dart`
// only asserts that post-import handicap falls in [-1.5, 1.5], which is
// satisfied by BOTH the old (2.0) AND new (2.5) centring constants — too
// coarse to catch a centring regression.
//
// Formula (see `importNewTournament`):
//   historyAvg  = p.history.isEmpty ? handicapCenter : p.history.mean
//   newHandicap = handicapCenter - ((p.earnedPoints + historyAvg) / 2)
//   newHandicap = newHandicap.clamp(-1.5, 1.5)
//
// All numbers used here (0.0, 2.5, 5.0, 1.25, 3.75, -1.25, +1.5, -1.5) are
// exactly representable in IEEE-754 double precision, so `expect` equality
// without an epsilon is safe — no false negatives from floating-point noise.
// ============================================================================

double _importAndGetHcp({
  required List<double> history,
  required double earnedPoints,
}) {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final provider = TournamentProvider();
  final player = Player(
    id: 'tp',
    name: 'TestPlayer',
    earnedPoints: earnedPoints,
    history: List<double>.from(history),
  );
  provider.importNewTournament(<String, dynamic>{
    'players': [player.toJson()],
  });
  return provider.players.single.handicap;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('importNewTournament handicap formula '
      '(centred at TournamentProvider.handicapCenter = 2.5)', () {
    /// Fresh players have empty `history`, so `historyAvg` defaults to
    /// `handicapCenter` (= 2.5).  These three cases pin the centring
    /// constant's value AND the `/2` divisor:

    test('fresh winner: history=[], earned=5.0 → hcp = -1.25', () {
      // 2.5 - ((5.0 + 2.5) / 2) = 2.5 - 3.75 = -1.25  (no clamp)
      expect(_importAndGetHcp(history: <double>[], earnedPoints: 5.0), -1.25);
    });

    test('fresh loser: history=[], earned=0.0 → hcp = +1.25', () {
      // 2.5 - ((0.0 + 2.5) / 2) = 2.5 - 1.25 = +1.25  (no clamp)
      expect(_importAndGetHcp(history: <double>[], earnedPoints: 0.0), 1.25);
    });

    test('fresh midpoint: history=[], earned=2.5 → hcp = 0.0', () {
      // 2.5 - ((2.5 + 2.5) / 2) = 2.5 - 2.5 = 0.0
      expect(_importAndGetHcp(history: <double>[], earnedPoints: 2.5), 0.0);
    });

    /// Veterans have non-empty `history`, so `historyAvg` equals
    /// `history.mean`.  These three cases pin the history-averaging
    /// branch AND the clamp behaviour at both extremes:

    test('veteran winner: history=[5,5], earned=5.0 → hcp clamps to -1.5', () {
      // historyAvg = 5.0; 2.5 - ((5.0 + 5.0) / 2) = 2.5 - 5.0 = -2.5
      // → clamp(-1.5, 1.5) = -1.5
      expect(
        _importAndGetHcp(history: <double>[5.0, 5.0], earnedPoints: 5.0),
        -1.5,
      );
    });

    test('veteran loser: history=[0,0], earned=0.0 → hcp clamps to +1.5', () {
      // historyAvg = 0.0; 2.5 - ((0.0 + 0.0) / 2) = 2.5 - 0.0 = +2.5
      // → clamp(-1.5, 1.5) = +1.5
      expect(
        _importAndGetHcp(history: <double>[0.0, 0.0], earnedPoints: 0.0),
        1.5,
      );
    });

    test('mixed veteran: history=[5], earned=0.0 → hcp = 0.0', () {
      // historyAvg = 5.0; 2.5 - ((0.0 + 5.0) / 2) = 2.5 - 2.5 = 0.0
      expect(_importAndGetHcp(history: <double>[5.0], earnedPoints: 0.0), 0.0);
    });
  });
}

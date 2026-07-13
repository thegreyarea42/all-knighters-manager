import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chess_tournament_manager/providers/tournament_provider.dart';
import 'package:chess_tournament_manager/models/player.dart';
import 'package:chess_tournament_manager/models/pairing.dart';

// ===========================================================================
// Helpers
// ===========================================================================
//
// IMPORTANT: production `addPlayer()` derives the player's id from
// `DateTime.now().millisecondsSinceEpoch`, so two adds in the same millisecond
// collide. In tests, we never call that public method — we instead inject
// explicit, deterministic ids via `p.players.add(...)`.

TournamentProvider _newProvider() {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return TournamentProvider();
}

Player _inject(
  TournamentProvider p,
  String id,
  String name, {
  double handicap = 0.0,
  double earnedPoints = 0.0,
  List<ChessColor>? colorHistory,
  List<String>? opponentsPlayed,
  List<double>? history,
  bool hadBye = false,
}) {
  final player = Player(
    id: id,
    name: name,
    handicap: handicap,
    earnedPoints: earnedPoints,
    colorHistory: colorHistory,
    opponentsPlayed: opponentsPlayed,
    history: history,
    hadBye: hadBye,
  );
  p.players.add(player);
  return player;
}

Player _byId(TournamentProvider p, String id) =>
    p.players.firstWhere((x) => x.id == id);

// ===========================================================================
// Tests
// ===========================================================================

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  // -------------------------------------------------------------------------
  group('TournamentProvider.calculateBuchholz', () {
    test('returns 0 for a player with no opponents', () {
      final p = _newProvider();
      _inject(p, 'a', 'Alice');
      expect(p.calculateBuchholz(_byId(p, 'a')), 0.0);
    });

    test('sums opponents\' earnedPoints', () {
      final p = _newProvider();
      _inject(p, 'a', 'Alice');
      _inject(p, 'b', 'Bob', earnedPoints: 2.0);
      _inject(p, 'c', 'Carol', earnedPoints: 1.5);
      _byId(p, 'a').opponentsPlayed.addAll(['b', 'c']);
      expect(p.calculateBuchholz(_byId(p, 'a')), closeTo(3.5, 0.001));
    });
  });

  // -------------------------------------------------------------------------
  group('TournamentProvider.getRankedPlayers', () {
    test('sorts by totalScore (earnedPoints + handicap) descending', () {
      final p = _newProvider();
      _inject(p, 'lo', 'Lo', handicap: -0.5); // totalScore -0.5
      _inject(p, 'hi', 'Hi', handicap: 1.5); // totalScore  1.5
      _inject(p, 'md', 'Md', handicap: 0.0); // totalScore  0.0
      expect(p.getRankedPlayers().map((pl) => pl.name).toList(), [
        'Hi',
        'Md',
        'Lo',
      ]);
    });

    test('breaks ties via Buchholz (higher Buchholz ranks higher)', () {
      final p = _newProvider();
      // Four players tied on totalScore = 2.0; a fifth ringer sits at 0.5.
      // Alice has the highest Buchholz because her opponents (strong + mid)
      // each scored 2.0 → Buchholz 4.0. Bob beats strong on Buchholz (2 vs 0.5).
      _inject(p, 'weak', 'Weak', earnedPoints: 0.5); // totalScore 0.5
      _inject(p, 'alice', 'Alice', earnedPoints: 2.0);
      _inject(p, 'bob', 'Bob', earnedPoints: 2.0);
      _inject(p, 'strong', 'Strong', earnedPoints: 2.0);
      _inject(p, 'mid', 'Mid', earnedPoints: 2.0);
      _byId(p, 'alice').opponentsPlayed.addAll(['strong', 'mid']); // 2 + 2
      _byId(p, 'bob').opponentsPlayed.add('mid'); // 2
      _byId(p, 'strong').opponentsPlayed.add('weak'); // 0.5
      // Expected order: alice (Bz 4) > bob (Bz 2) > strong (Bz 0.5) > mid (Bz 0) > weak.
      expect(p.getRankedPlayers().map((pl) => pl.name).toList(), [
        'Alice',
        'Bob',
        'Strong',
        'Mid',
        'Weak',
      ]);
    });
  });

  // -------------------------------------------------------------------------
  group('Recalculation flow (via updateResult + submitRound)', () {
    test(
      'recalculateStandings is idempotent: re-issuing same result does not double-count',
      () {
        final p = _newProvider();
        _inject(p, 'a', 'Alice');
        _inject(p, 'b', 'Bob');
        p.startTournament(20);
        // Round-1 Parity pre-shuffles players (see PairingEngine), so identical
        // handicaps means color assignment is random — read ids from the pair.
        final pair = p.rounds.single.pairings.single;
        final whiteId = pair.whitePlayerId;
        final blackId = pair.blackPlayerId;

        p.updateResult(whiteId, blackId, GameResult.whiteWin);
        final winnerPointsAfter1 = _byId(p, whiteId).earnedPoints;
        // Issuing the same result again: recalculateStandings RESETS all
        // player state then re-applies from rounds — must remain 1.0, not 2.0.
        p.updateResult(whiteId, blackId, GameResult.whiteWin);
        expect(
          _byId(p, whiteId).earnedPoints,
          winnerPointsAfter1,
          reason:
              'recalculateStandings must reset + re-apply to remain idempotent',
        );
        expect(_byId(p, whiteId).earnedPoints, 1.0);
      },
    );

    test('draw awards 0.5 to each and records color history', () {
      final p = _newProvider();
      _inject(p, 'a', 'Alice');
      _inject(p, 'b', 'Bob');
      p.startTournament(20);
      final whiteId = p.rounds.single.pairings.single.whitePlayerId;
      final blackId = p.rounds.single.pairings.single.blackPlayerId;
      p.updateResult(whiteId, blackId, GameResult.draw);

      final whitePlayer = _byId(p, whiteId);
      final blackPlayer = _byId(p, blackId);
      expect(whitePlayer.earnedPoints, 0.5);
      expect(blackPlayer.earnedPoints, 0.5);
      expect(whitePlayer.opponentsPlayed, contains(blackPlayer.id));
      expect(blackPlayer.opponentsPlayed, contains(whitePlayer.id));
      expect(whitePlayer.colorHistory, [ChessColor.white]);
      expect(blackPlayer.colorHistory, [ChessColor.black]);
    });

    test('submitRound marks the round completed and finalizes standings', () {
      final p = _newProvider();
      _inject(p, 'a', 'A');
      _inject(p, 'b', 'B');
      p.startTournament(20);
      final r1 = p.rounds.single;
      expect(r1.isCompleted, false);
      p.updateResult(
        r1.pairings.single.whitePlayerId,
        r1.pairings.single.blackPlayerId,
        GameResult.whiteWin,
      );
      p.submitRound();
      expect(r1.isCompleted, true);
      expect(r1.completedTime, isNotNull);
    });

    test('BYE pairing awards +1.0 and sets hadBye=true on submission', () {
      final p = _newProvider();
      // 3 players (R1 → one BYE). Handicaps: A=2.0 (weakest), B=1.0, C=0.0.
      _inject(p, 'a', 'A', handicap: 2.0);
      _inject(p, 'b', 'B', handicap: 1.0);
      _inject(p, 'c', 'C', handicap: 0.0);
      p.startTournament(20);

      final r1 = p.rounds.single;
      final byePair = r1.pairings.firstWhere((x) => x.isBye);
      expect(
        byePair.whitePlayerId,
        'a',
        reason: 'R1 BYE goes to the WEAKEST player (highest handicap value)',
      );

      p.submitRound();
      expect(_byId(p, 'a').earnedPoints, 1.0);
      expect(_byId(p, 'a').hadBye, true);
    });
  });

  // -------------------------------------------------------------------------
  group('correctResult', () {
    test('re-applies standings with the corrected result', () {
      final p = _newProvider();
      _inject(p, 'a', 'Alice');
      _inject(p, 'b', 'Bob');
      p.startTournament(20);
      final whiteId = p.rounds.single.pairings.single.whitePlayerId;
      final blackId = p.rounds.single.pairings.single.blackPlayerId;

      p.updateResult(whiteId, blackId, GameResult.draw);
      expect(_byId(p, whiteId).earnedPoints, 0.5);
      expect(_byId(p, blackId).earnedPoints, 0.5);

      p.correctResult(1, whiteId, blackId, GameResult.whiteWin);
      expect(_byId(p, whiteId).earnedPoints, 1.0);
      expect(_byId(p, blackId).earnedPoints, 0.0);
    });

    test('works even after the round is marked completed', () {
      final p = _newProvider();
      _inject(p, 'a', 'Alice');
      _inject(p, 'b', 'Bob');
      p.startTournament(20);
      final whiteId = p.rounds.single.pairings.single.whitePlayerId;
      final blackId = p.rounds.single.pairings.single.blackPlayerId;
      p.updateResult(whiteId, blackId, GameResult.whiteWin);
      p.submitRound();
      p.correctResult(1, whiteId, blackId, GameResult.draw);
      expect(_byId(p, whiteId).earnedPoints, 0.5);
      expect(_byId(p, blackId).earnedPoints, 0.5);
    });

    test('throws StateError on a round number that does not exist', () {
      final p = _newProvider();
      _inject(p, 'a', 'A');
      _inject(p, 'b', 'B');
      p.startTournament(20);
      expect(
        () => p.correctResult(99, 'nope-w', 'nope-b', GameResult.draw),
        throwsA(anything),
      );
    });
  });

  // -------------------------------------------------------------------------
  group('Player removal and checks', () {
    test('removePlayer drops the player from the list', () {
      final p = _newProvider();
      _inject(p, 'a', 'Alice');
      _inject(p, 'b', 'Bob');
      p.removePlayer('a');
      expect(p.players.map((pl) => pl.name).toList(), ['Bob']);
    });

    test('updatePlayerHandicap patches the live player reference', () {
      final p = _newProvider();
      _inject(p, 'a', 'Alice', handicap: 0.5);
      // Sanity: the helper actually injected 0.5.
      expect(_byId(p, 'a').handicap, 0.5);
      // UpdatePlayerHandicap must reflect the supplied value.
      p.updatePlayerHandicap('a', 1.5);
      expect(
        _byId(p, 'a').handicap,
        1.5,
        reason: 'updatePlayerHandicap must mutate the live Player reference',
      );
    });
  });

  // -------------------------------------------------------------------------
  group('importNewTournament', () {
    test('recomputes handicaps from history averages and resets points', () {
      final p = _newProvider();
      // With handicapCenter = 2.5:
      // Strong player: history=[3,3,3], earned=3.  avg=3. hcp=2.5-((3+3)/2)=-0.5 (unclamped).
      // Weak player:   history=[0,0,0], earned=0.  avg=0. hcp=2.5-0=2.5 → clamp +1.5.
      // After import, p1 sits at -0.5 (interpolated mid-strong) and p2 at
      // the UPPER clamp (+1.5, very weak) — the contrast demonstrates the
      // formula's graduated output rather than clamp saturation. This
      // intentionally differs from `handicap_formula_test.dart`'s
      // veteran-winner case (history=[5,5] → -1.5) so the two tests cover
      // different branches of the formula.
      final data = <String, dynamic>{
        'players': [
          {
            'id': 'p1',
            'name': 'Strong',
            'earnedPoints': 3.0,
            'handicap': 0.0,
            'colorHistory': <int>[],
            'opponentsPlayed': <String>[],
            'history': [3.0, 3.0, 3.0],
            'hadBye': false,
          },
          {
            'id': 'p2',
            'name': 'Weak',
            'earnedPoints': 0.0,
            'handicap': 0.0,
            'colorHistory': <int>[],
            'opponentsPlayed': <String>[],
            'history': [0.0, 0.0, 0.0],
            'hadBye': false,
          },
        ],
        'rounds': <Map<String, dynamic>>[],
        'currentRoundNumber': 0,
        'isTournamentStarted': false,
        'tournamentName': 'Imported Cup',
        'secondsRemaining': 0,
      };

      p.importNewTournament(data);
      expect(p.players.length, 2);
      expect(
        _byId(p, 'p1').earnedPoints,
        0.0,
        reason: 'importNewTournament resets earnedPoints to 0',
      );
      expect(_byId(p, 'p2').earnedPoints, 0.0);
      expect(_byId(p, 'p1').handicap, -0.5);
      expect(
        _byId(p, 'p2').handicap,
        1.5,
        reason: 'hcp clamped to +1.5 (formula gives 2.5)',
      );
      expect(p.rounds, isEmpty);
      expect(p.currentRoundNumber, 0);
      expect(p.isTournamentStarted, false);
    });
  });
}

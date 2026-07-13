import 'package:flutter_test/flutter_test.dart';
import 'package:chess_tournament_manager/logic/pairing_engine.dart';
import 'package:chess_tournament_manager/models/player.dart';
import 'package:chess_tournament_manager/models/pairing.dart';

// ===========================================================================
// Helpers
// ===========================================================================

Player _p(
  String id,
  String name, {
  double handicap = 0.0,
  double earnedPoints = 0.0,
  List<ChessColor>? colorHistory,
  List<String>? opponentsPlayed,
  bool hadBye = false,
}) {
  return Player(
    id: id,
    name: name,
    handicap: handicap,
    earnedPoints: earnedPoints,
    colorHistory: colorHistory,
    opponentsPlayed: opponentsPlayed,
    hadBye: hadBye,
  );
}

/// Match-agnostic pair lookup (handles color assignment either way).
bool _matchExists(List<Pairing> pairs, String a, String b) {
  return pairs.any(
    (pair) =>
        (pair.whitePlayerId == a && pair.blackPlayerId == b) ||
        (pair.whitePlayerId == b && pair.blackPlayerId == a),
  );
}

Set<String> _pairedPlayerIds(List<Pairing> pairs) {
  final ids = <String>{};
  for (final pair in pairs) {
    ids.add(pair.whitePlayerId);
    if (!pair.isBye) ids.add(pair.blackPlayerId);
  }
  return ids;
}

// ===========================================================================
// Tests
// ===========================================================================

void main() {
  // -------------------------------------------------------------------------
  // Round 1 — Parity mode (default)
  // Convention: lower numeric handicap value === STRONGER player in this app.
  // -------------------------------------------------------------------------
  group('Round 1 — Parity mode (default)', () {
    test('even count: pairs players by ascending handicap (strongest vs 2nd-strongest, etc.)',
        () {
      final players = [
        _p('p1', 'Alice', handicap: 0.0), // strongest
        _p('p2', 'Bob',   handicap: 1.0),
        _p('p3', 'Carol', handicap: 2.0),
        _p('p4', 'Dave',  handicap: 3.0), // weakest
      ];

      final result = PairingEngine.generatePairings(
        players,
        isRound1: true,
      );

      expect(result.length, 2);
      expect(result.every((pair) => !pair.isBye), isTrue);
      expect(_matchExists(result, 'p1', 'p2'), isTrue,
          reason: 'Strongest two should be paired');
      expect(_matchExists(result, 'p3', 'p4'), isTrue,
          reason: 'Weakest two should be paired');
    });

    test('odd count: BYE goes to the WEAKEST player (highest numeric handicap value)',
        () {
      final players = [
        _p('strongest', 'Alice', handicap: 0.0),
        _p('mid',       'Bob',   handicap: 1.0),
        _p('weakest',   'Carol', handicap: 2.0),
      ];

      final result = PairingEngine.generatePairings(
        players,
        isRound1: true,
      );

      expect(result.length, 2, reason: 'one BYE pairing + one real game');

      final byes = result.where((pair) => pair.isBye).toList();
      expect(byes.length, 1);
      expect(byes.first.whitePlayerId, 'weakest');
      expect(byes.first.blackPlayerId, 'BYE');

      final games = result.where((pair) => !pair.isBye).toList();
      expect(games.length, 1);
      expect(_matchExists(games, 'strongest', 'mid'), isTrue);
    });

    test('does not mutate the input player list', () {
      final players = [
        _p('a', 'A'),
        _p('b', 'B'),
      ];
      final originalIds = players.map((p) => p.id).toList();

      PairingEngine.generatePairings(players, isRound1: true);

      expect(players.map((p) => p.id).toList(), equals(originalIds));
    });

    test('round-1 Parity handles duplicate handicaps without crashing', () {
      // The implementation pre-shuffles to randomize identical handicaps
      // (because Dart List.sort is stable). We only assert structural invariants.
      final players = [
        _p('a', 'A', handicap: 1.0),
        _p('b', 'B', handicap: 1.0),
        _p('c', 'C', handicap: 1.0),
        _p('d', 'D', handicap: 1.0),
      ];

      final result = PairingEngine.generatePairings(
        players,
        isRound1: true,
      );

      expect(result.length, 2);
      expect(result.every((pair) => !pair.isBye), isTrue);
      expect(_pairedPlayerIds(result), {'a', 'b', 'c', 'd'});
    });
  });

  // -------------------------------------------------------------------------
  // Round 1 — Random mode
  // -------------------------------------------------------------------------
  group('Round 1 — Random mode', () {
    test('even count: every player appears exactly once across both colors',
        () {
      final players = [
        _p('p1', 'A', handicap: 0.0),
        _p('p2', 'B', handicap: 0.0),
        _p('p3', 'C', handicap: 0.0),
        _p('p4', 'D', handicap: 0.0),
      ];

      final result = PairingEngine.generatePairings(
        players,
        isRound1: true,
        r1pMode: 'Random',
      );

      expect(result.length, 2);
      expect(result.every((pair) => !pair.isBye), isTrue);
      expect(_pairedPlayerIds(result), {'p1', 'p2', 'p3', 'p4'});
    });

    test('odd count: exactly one BYE + one game', () {
      final players = [
        _p('p1', 'A', handicap: 0.0),
        _p('p2', 'B', handicap: 1.0),
        _p('p3', 'C', handicap: 2.0),
      ];

      final result = PairingEngine.generatePairings(
        players,
        isRound1: true,
        r1pMode: 'Random',
      );

      expect(result.length, 2);
      expect(result.where((pair) => pair.isBye).length, 1);
      expect(result.where((pair) => !pair.isBye).length, 1);
      expect(_pairedPlayerIds(result).length, 3);
    });
  });

  // -------------------------------------------------------------------------
  // Round 1 — Seeded mode
  // Pairs index i with i + half (standard Swiss seeding), so for four players
  // sorted ascending [0.0, 1.0, 2.0, 3.0] we expect (0.0, 2.0) and (1.0, 3.0).
  // -------------------------------------------------------------------------
  group('Round 1 — Seeded mode', () {
    test('pairs i with i + half (Swiss seeding, not fold pairing)', () {
      final players = [
        _p('p1', 'A', handicap: 0.0), // strongest
        _p('p2', 'B', handicap: 1.0),
        _p('p3', 'C', handicap: 2.0),
        _p('p4', 'D', handicap: 3.0), // weakest
      ];

      final result = PairingEngine.generatePairings(
        players,
        isRound1: true,
        r1pMode: 'Seeded',
      );

      expect(result.length, 2);
      expect(_matchExists(result, 'p1', 'p3'), isTrue,
          reason: 'index 0 paired with index 2 (i+half)');
      expect(_matchExists(result, 'p2', 'p4'), isTrue,
          reason: 'index 1 paired with index 3 (i+half)');
    });

    test('odd count: BYE + Swiss-seeded pairing', () {
      final players = [
        _p('p1', 'A', handicap: 0.0),
        _p('p2', 'B', handicap: 1.0),
        _p('p3', 'C', handicap: 2.0),
        _p('p4', 'D', handicap: 3.0),
        _p('p5', 'E', handicap: 4.0),
      ];

      final result = PairingEngine.generatePairings(
        players,
        isRound1: true,
        r1pMode: 'Seeded',
      );

      expect(result.length, 3, reason: '1 BYE + 2 games');
      expect(result.where((pair) => pair.isBye).length, 1);
      expect(result.where((pair) => !pair.isBye).length, 2);
    });
  });

  // -------------------------------------------------------------------------
  // Round 2+ — Swiss pairing
  // -------------------------------------------------------------------------
  group('Round 2+ — Swiss', () {
    test('sorts by earnedPoints descending; highest earner faces next highest non-repeating opponent',
        () {
      final players = [
        _p('p1', 'A', earnedPoints: 3.0),
        _p('p2', 'B', earnedPoints: 2.0),
        _p('p3', 'C', earnedPoints: 1.0),
        _p('p4', 'D', earnedPoints: 0.0),
      ];

      final result = PairingEngine.generatePairings(players);

      expect(result.length, 2);
      expect(_matchExists(result, 'p1', 'p2'), isTrue,
          reason: 'Top two scoring players should be paired');
      expect(_matchExists(result, 'p3', 'p4'), isTrue);
    });

    test('no-repeat opponent rule: skips prior matchups from previous round', () {
      // Pretend Round 1 produced (1 vs 3) and (2 vs 4).
      final players = [
        _p('1', 'A', earnedPoints: 1.0, opponentsPlayed: const ['3']),
        _p('2', 'B', earnedPoints: 1.0, opponentsPlayed: const ['4']),
        _p('3', 'C', earnedPoints: 0.0, opponentsPlayed: const ['1']),
        _p('4', 'D', earnedPoints: 0.0, opponentsPlayed: const ['2']),
      ];

      final result = PairingEngine.generatePairings(players);

      expect(result.length, 2);
      expect(result.every((pair) => !pair.isBye), isTrue);
      expect(_matchExists(result, '1', '3'), isFalse,
          reason: 'No-repeat rule: 1 should NOT face 3 again');
      expect(_matchExists(result, '2', '4'), isFalse,
          reason: 'No-repeat rule: 2 should NOT face 4 again');
      // 1 must be paired against the only remaining valid opponent: 2
      expect(_matchExists(result, '1', '2'), isTrue,
          reason: 'Greedy Swiss pairs 1 (highest) with the first non-repeating opponent on the list');
    });

    test('returns no Swiss pairings when every possible pair has already played',
        () {
      // 4-player round-robin, everyone has played everyone else.
      final players = [
        _p('1', 'A', earnedPoints: 1.5,
            opponentsPlayed: const ['2', '3', '4']),
        _p('2', 'B', earnedPoints: 1.5,
            opponentsPlayed: const ['1', '3', '4']),
        _p('3', 'C', earnedPoints: 0.5,
            opponentsPlayed: const ['1', '2', '4']),
        _p('4', 'D', earnedPoints: 0.5,
            opponentsPlayed: const ['1', '2', '3']),
      ];

      final result = PairingEngine.generatePairings(players);

      // No valid Swiss pairing is reachable; _recursivePair returns null
      // which the engine converts to an empty additional-pairings list.
      expect(result, isEmpty);
    });

    test('odd count: BYE goes to lowest-point player without prior BYE', () {
      final players = [
        _p('top', 'A', earnedPoints: 2.0, hadBye: false),
        _p('mid', 'B', earnedPoints: 1.5, hadBye: true),  // already had one
        _p('low', 'C', earnedPoints: 0.5, hadBye: false),
      ];

      final result = PairingEngine.generatePairings(players);

      final byes = result.where((pair) => pair.isBye).toList();
      expect(byes.length, 1);
      expect(byes.first.whitePlayerId, 'low',
          reason:
              'Lowest-point player with hadBye=false should receive the BYE');
    });

    test('odd count: falls back to the lowest-point player when everyone has had a BYE',
        () {
      final players = [
        _p('top', 'A', earnedPoints: 2.0, hadBye: true),
        _p('mid', 'B', earnedPoints: 1.0, hadBye: true),
        _p('low', 'C', earnedPoints: 0.5, hadBye: true),
      ];

      final result = PairingEngine.generatePairings(players);

      final byes = result.where((pair) => pair.isBye).toList();
      expect(byes.length, 1);
      // Sort ascending by points: [C(0.5), B(1.0), A(2.0)]; none has hadBye=false
      // → fallback `byePlayer ??= activePlayers.first` → Carol.
      expect(byes.first.whitePlayerId, 'low');
    });

    test('color balance: higher colorBalance player gets BLACK in next pairing',
        () {
      // p1.A: points=1.5, colorHistory=[W,W] → colorBalance = +2 (more whites)
      // p2.B: points=1.0, colorHistory=[B,B] → colorBalance = -2 (more blacks)
      // P1 has more whites → should be assigned BLACK.
      final players = [
        _p(
          'a',
          'A',
          earnedPoints: 1.5,
          colorHistory: const [ChessColor.white, ChessColor.white],
        ),
        _p(
          'b',
          'B',
          earnedPoints: 1.0,
          colorHistory: const [ChessColor.black, ChessColor.black],
        ),
      ];

      final result = PairingEngine.generatePairings(players);

      expect(result.length, 1);
      expect(result.first.whitePlayerId, 'b',
          reason: 'B (more blacks so far) is assigned WHITE');
      expect(result.first.blackPlayerId, 'a',
          reason: 'A (more whites so far) is assigned BLACK');
    });

    test('color balance: lower colorBalance player gets WHITE', () {
      // p1.A: points=1.5, colorHistory=[] → colorBalance = 0
      // p2.B: points=1.0, colorHistory=[W] → colorBalance = +1
      // p1.balance (0) < p2.balance (1) → p1 should be assigned WHITE.
      final players = [
        _p('a', 'A', earnedPoints: 1.5),
        _p('b', 'B',
            earnedPoints: 1.0,
            colorHistory: const [ChessColor.white]),
      ];

      final result = PairingEngine.generatePairings(players);

      expect(result.length, 1);
      expect(result.first.whitePlayerId, 'a');
      expect(result.first.blackPlayerId, 'b');
    });

    test('color balance: equal balance falls back to p1.last-color alternation',
        () {
      // Both players have colorBalance = 0. Tied with last color rule:
      //   - p1.colorHistory.last == white → p1White = false (alternate)
      //   - else → p1White = true
      final players = [
        _p('a', 'A', earnedPoints: 1.5,
            colorHistory: const [ChessColor.white]),
        _p('b', 'B', earnedPoints: 1.0,
            colorHistory: const [ChessColor.black]),
      ];

      final result = PairingEngine.generatePairings(players);

      expect(result.length, 1);
      // balances equal: 1 vs 1; check p1's last color
      // a.balance (1) == b.balance (1) → equal branch.
      // p1.last was WHITE → aWhite = false.
      // So B gets WHITE, A gets BLACK.
      expect(result.first.whitePlayerId, 'b');
      expect(result.first.blackPlayerId, 'a');
    });
  });

  // -------------------------------------------------------------------------
  // Edge cases
  // -------------------------------------------------------------------------
  group('Edge cases', () {
    test('empty list returns empty pairings', () {
      final result = PairingEngine.generatePairings([]);
      expect(result, isEmpty);
    });

    test('single player in Round 1 → exactly one BYE pairing', () {
      final players = [_p('solo', 'Solo', handicap: 1.5)];
      final result =
          PairingEngine.generatePairings(players, isRound1: true);
      expect(result.length, 1);
      expect(result.first.isBye, isTrue);
      expect(result.first.whitePlayerId, 'solo');
      expect(result.first.blackPlayerId, 'BYE');
    });

    test('single player in Round 2+ → exactly one BYE pairing', () {
      final players = [_p('solo', 'Solo', earnedPoints: 1.0)];
      final result = PairingEngine.generatePairings(players);
      expect(result.length, 1);
      expect(result.first.isBye, isTrue);
      expect(result.first.whitePlayerId, 'solo');
    });

    test('bye pairing has GameResult.bye as default result', () {
      final players = [_p('solo', 'Solo', earnedPoints: 1.0)];
      final result = PairingEngine.generatePairings(players);
      expect(result.first.result, GameResult.bye);
    });
  });
}

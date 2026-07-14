import 'package:flutter_test/flutter_test.dart';
import 'package:chess_tournament_manager/logic/export_logic.dart';
import 'package:chess_tournament_manager/models/player.dart';
import 'package:chess_tournament_manager/models/round.dart';
import 'package:chess_tournament_manager/models/pairing.dart';

// ===========================================================================
// Helpers
// ===========================================================================

Player _p(
  String id,
  String name, {
  double earnedPoints = 0.0,
  double handicap = 0.0,
  List<ChessColor>? colorHistory,
  List<String>? opponentsPlayed,
  List<double>? history,
  bool hadBye = false,
}) => Player(
  id: id,
  name: name,
  earnedPoints: earnedPoints,
  handicap: handicap,
  colorHistory: colorHistory,
  opponentsPlayed: opponentsPlayed,
  history: history,
  hadBye: hadBye,
);

Round _round(
  int number,
  List<Pairing> pairings, {
  DateTime? startTime,
  DateTime? completedTime,
  bool isCompleted = true,
}) => Round(
  number: number,
  pairings: pairings,
  startTime: startTime ?? DateTime(2024, 1, 1, 10, 0),
  completedTime: completedTime ?? DateTime(2024, 1, 1, 10, 30),
  isCompleted: isCompleted,
);

/// Extract the body of the "## Final Leaderboard" section (between that
/// heading and the next `## ` heading).
String _leaderboardSection(String md) {
  const start = '## Final Leaderboard';
  const end = '## Player Data';
  final s = md.indexOf(start);
  final e = md.indexOf(end, s == -1 ? 0 : s);
  if (s == -1 || e == -1) return '';
  return md.substring(s, e);
}

/// Look up a row in the leaderboard by player name and return its pipe-split
/// cells (with empty edges stripped). Rows look like
/// `| 1 | Alice | 1.0 | 0.0 | 1.0 | 0.5 |` — note the space after the pipe.
List<String> _rowByName(String section, String name) {
  // `startsWith('$rank | $name')` and `contains(name)` both work; we pick
  // contains(name) so the same helper works for any column that mentions
  // the player by name (it appears only in the "Name" cell).
  final line = section
      .split('\n')
      .firstWhere((l) => l.contains(name), orElse: () => '');
  return line
      .split('|')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

// ===========================================================================
// Tests
// ===========================================================================

void main() {
  // -------------------------------------------------------------------------
  group('ExportLogic.sanitizeFileName', () {
    test(
      'replaces spaces with underscores (each space becomes one underscore; no trimming)',
      () {
        expect(ExportLogic.sanitizeFileName('Hello World'), 'Hello_World');
        // Strip phase removes non-word/whitespace/hyphen chars; replace phase
        // turns every ASCII space into an underscore (no collapsing).
        expect(
          ExportLogic.sanitizeFileName('  Multiple   Spaces  '),
          '__Multiple___Spaces__',
        );
      },
    );

    test('strips common disallowed characters (slash, asterisk, etc.)', () {
      expect(ExportLogic.sanitizeFileName('a/b\\c:d*e?f|g'), 'abcdefg');
      expect(ExportLogic.sanitizeFileName('left/right'), 'leftright');
    });

    test('preserves letters, digits, and hyphens', () {
      expect(
        ExportLogic.sanitizeFileName('Friday-Cup-2024'),
        'Friday-Cup-2024',
      );
      expect(ExportLogic.sanitizeFileName('Tournament_42'), 'Tournament_42');
    });

    test('an empty input yields empty output', () {
      expect(ExportLogic.sanitizeFileName(''), '');
    });

    test(
      'non-whitespace special chars are stripped (yield empty for only-special input)',
      () {
        expect(ExportLogic.sanitizeFileName(r'!@#$%^&*()'), '');
        // Three spaces survive stripping (whitespace is allowed by [^\w\s\-])
        // and become three underscores.
        expect(ExportLogic.sanitizeFileName('   '), '___');
      },
    );

    test('mixed: keeps allowed, strips rest, applies underscores', () {
      expect(
        ExportLogic.sanitizeFileName('Winter Cup: Finals! (2024)'),
        'Winter_Cup_Finals_2024',
      );
    });
  });

  // -------------------------------------------------------------------------
  group('ExportLogic.parseMarkdown', () {
    test('returns null when validation tag (`app: TiltClock`) is missing', () {
      expect(ExportLogic.parseMarkdown('# Random Markdown'), isNull);
      expect(ExportLogic.parseMarkdown(''), isNull);
      expect(ExportLogic.parseMarkdown('---\nclub: Foo\n---\n# Body'), isNull);
    });

    test(
      'returns null when STATE_JSON markers are missing despite valid tag',
      () {
        const md = '''---
app: TiltClock
club: All Knighters
---
# Tournament Name
This is body content without JSON.
''';
        expect(ExportLogic.parseMarkdown(md), isNull);
      },
    );

    test('extracts the STATE_JSON blob between markers', () {
      const md = '''---
app: TiltClock
---
# Tournament
<!-- STATE_JSON_START
{"tournamentName":"X Cup","totalRounds":4,"duration":20,"currentRoundNumber":0,"isTournamentStarted":true,"players":[],"rounds":[]}
STATE_JSON_END -->
''';
      final parsed = ExportLogic.parseMarkdown(md);
      expect(parsed, isNotNull);
      expect(parsed!['tournamentName'], 'X Cup');
      expect(parsed['totalRounds'], 4);
      expect(parsed['duration'], 20);
    });

    test('returns null on malformed JSON between markers', () {
      const md = '''---
app: TiltClock
---
<!-- STATE_JSON_START
{this is not valid json
STATE_JSON_END -->''';
      expect(ExportLogic.parseMarkdown(md), isNull);
    });

    test(
      'round-trip: generateMarkdown → parseMarkdown preserves GAME STATE',
      () {
        final players = [
          _p(
            'alice-id',
            'Alice',
            earnedPoints: 2.0,
            handicap: 0.5,
            opponentsPlayed: const ['bob-id'],
            colorHistory: const [ChessColor.white],
            history: const [2.0, 1.0],
          ),
          _p(
            'bob-id',
            'Bob',
            earnedPoints: 0.0,
            handicap: 0.0,
            opponentsPlayed: const ['alice-id'],
            colorHistory: const [ChessColor.black],
          ),
        ];
        final rounds = [
          _round(1, [
            Pairing(
              whitePlayerId: 'alice-id',
              blackPlayerId: 'bob-id',
              result: GameResult.whiteWin,
            ),
          ]),
        ];

        final md = ExportLogic.generateMarkdown(
          tournamentName: 'Round-Trip Cup',
          players: players,
          rounds: rounds,
          totalRounds: 4,
          duration: 20,
        );

        final parsed = ExportLogic.parseMarkdown(md)!;

        expect(parsed['tournamentName'], 'Round-Trip Cup');
        expect(parsed['totalRounds'], 4);
        expect(parsed['duration'], 20);
        expect(parsed['currentRoundNumber'], rounds.length);
        expect(parsed['isTournamentStarted'], true);

        final parsedPlayers = (parsed['players'] as List)
            .cast<Map<String, dynamic>>();
        expect(parsedPlayers.length, 2);
        final aliceJson = parsedPlayers.firstWhere(
          (j) => j['id'] == 'alice-id',
        );
        expect(aliceJson['name'], 'Alice');
        expect(aliceJson['earnedPoints'], 2.0);
        expect(aliceJson['handicap'], 0.5);
        expect(aliceJson['opponentsPlayed'], ['bob-id']);

        final parsedRounds = (parsed['rounds'] as List)
            .cast<Map<String, dynamic>>();
        expect(parsedRounds.length, 1);
        expect(parsedRounds.first['number'], 1);
        final parsedPairings = (parsedRounds.first['pairings'] as List)
            .cast<Map<String, dynamic>>();
        expect(parsedPairings[0]['whitePlayerId'], 'alice-id');
        expect(parsedPairings[0]['blackPlayerId'], 'bob-id');
        expect(parsedPairings[0]['result'], GameResult.whiteWin.index);
      },
    );
  });

  // -------------------------------------------------------------------------
  group('ExportLogic.generateMarkdown', () {
    test('emits all required top-level sections', () {
      final md = ExportLogic.generateMarkdown(
        tournamentName: 'Section Test',
        players: [_p('a', 'A'), _p('b', 'B')],
        rounds: const [],
        totalRounds: 4,
        duration: 20,
      );
      expect(md, contains('app: TiltClock'));
      expect(md, contains('club: All Knighters'));
      expect(md, contains('# Section Test'));
      expect(md, contains('## Final Leaderboard'));
      expect(md, contains('| Rank | Name | Points | Hcp | Total | Buchholz |'));
      expect(md, contains('## Player Data & History'));
      expect(md, contains('## Full Match History'));
      expect(md, contains('STATE_JSON_START'));
      expect(md, contains('STATE_JSON_END'));
    });

    test('leaderboard ranks by totalScore descending', () {
      // TotalScore = earnedPoints + handicap.
      final players = [
        _p('lo', 'Lo', earnedPoints: 0.0, handicap: -0.5), // total  -0.5
        _p('hi', 'Hi', earnedPoints: 1.0, handicap: 0.0), // total   1.0
        _p('md', 'Md', earnedPoints: 1.5, handicap: -1.0), // total   0.5
      ];
      final md = ExportLogic.generateMarkdown(
        tournamentName: 'Sort Test',
        players: players,
        rounds: const [],
        totalRounds: 1,
        duration: 20,
      );
      final section = _leaderboardSection(md);
      // Expected order in leaderboard rows: Hi (1.0), Md (0.5), Lo (-0.5)
      final hiIdx = section.indexOf('| Hi');
      final mdIdx = section.indexOf('| Md');
      final loIdx = section.indexOf('| Lo');
      expect(hiIdx, lessThan(mdIdx));
      expect(mdIdx, lessThan(loIdx));
    });

    test('leaderboard BUCHHOLZ column reflects opponents\' earnedPoints', () {
      // Alice played Bob (B has 0.5pt) → Buchholz = 0.5
      // Bob played Carol (C has 2.0pt) → Buchholz = 2.0
      // Carol played nobody   → Buchholz = 0.0
      final players = [
        _p(
          'alice',
          'Alice',
          earnedPoints: 1.0,
          handicap: 0.0,
          opponentsPlayed: const ['bob'],
        ),
        _p(
          'bob',
          'Bob',
          earnedPoints: 0.5,
          handicap: 0.0,
          opponentsPlayed: const ['carol'],
        ),
        _p(
          'carol',
          'Carol',
          earnedPoints: 2.0,
          handicap: 0.0,
          opponentsPlayed: const [],
        ),
      ];
      final md = ExportLogic.generateMarkdown(
        tournamentName: 'Buchholz Test',
        players: players,
        rounds: const [],
        totalRounds: 1,
        duration: 20,
      );
      final section = _leaderboardSection(md);
      final aliceCells = _rowByName(section, 'Alice');
      final bobCells = _rowByName(section, 'Bob');
      final carolCells = _rowByName(section, 'Carol');
      // Columns: rank, name, points, hcp, total, buchholz
      expect(aliceCells.length, greaterThanOrEqualTo(1));
      expect(double.parse(aliceCells[5]), closeTo(0.5, 0.001));
      expect(double.parse(bobCells[5]), closeTo(2.0, 0.001));
      expect(double.parse(carolCells[5]), closeTo(0.0, 0.001));
    });

    test('match history uses correct result symbol per GameResult', () {
      final players = [
        _p('w', 'WhiteStrong', earnedPoints: 1.0),
        _p('b', 'BlackStrong', earnedPoints: 1.0),
      ];
      final md = ExportLogic.generateMarkdown(
        tournamentName: 'Result Symbols',
        players: players,
        rounds: [
          _round(1, [
            Pairing(
              whitePlayerId: 'w',
              blackPlayerId: 'b',
              result: GameResult.whiteWin,
            ),
            Pairing(
              whitePlayerId: 'w',
              blackPlayerId: 'b',
              result: GameResult.blackWin,
            ),
            Pairing(
              whitePlayerId: 'w',
              blackPlayerId: 'b',
              result: GameResult.draw,
            ),
            Pairing(
              whitePlayerId: 'w',
              blackPlayerId: 'BYE',
              result: GameResult.bye,
            ),
          ]),
        ],
        totalRounds: 1,
        duration: 20,
      );
      expect(md, contains(r'| 1 | WhiteStrong | BlackStrong | 1 - 0 |'));
      expect(md, contains(r'| 2 | WhiteStrong | BlackStrong | 0 - 1 |'));
      expect(md, contains(r'| 3 | WhiteStrong | BlackStrong | ½ - ½ |'));
      expect(md, contains(r'| 4 | WhiteStrong | *BYE* | + - - |'));
    });

    test('pending pairing renders as "..."', () {
      final players = [_p('x', 'X'), _p('y', 'Y')];
      final md = ExportLogic.generateMarkdown(
        tournamentName: 'Pending',
        players: players,
        rounds: [
          _round(1, [
            Pairing(whitePlayerId: 'x', blackPlayerId: 'y'), // default: pending
          ]),
        ],
        totalRounds: 1,
        duration: 20,
      );
      expect(md, contains(r'| 1 | X | Y | ... |'));
    });

    test('player history field rolls the latest earnedPoints onto it', () {
      final alice = _p(
        'alice',
        'Alice',
        earnedPoints: 3.0,
        handicap: 0.0,
        history: const [1.0, 2.0],
      );
      final md = ExportLogic.generateMarkdown(
        tournamentName: 'History Test',
        players: [alice],
        rounds: const [],
        totalRounds: 1,
        duration: 20,
      );
      // The section appends current earnedPoints (3.0) onto last 4 entries, capped at 5.
      expect(md, contains('History: [1.0, 2.0, 3.0]'));
    });

    test('player history cap: long histories are trimmed to last 5', () {
      final alice = _p(
        'alice',
        'Alice',
        earnedPoints: 6.0,
        handicap: 0.0,
        history: const [1.0, 2.0, 3.0, 4.0, 5.0],
      );
      final md = ExportLogic.generateMarkdown(
        tournamentName: 'History Cap',
        players: [alice],
        rounds: const [],
        totalRounds: 1,
        duration: 20,
      );
      // After appending 6.0 → [2.0, 3.0, 4.0, 5.0, 6.0]
      expect(md, contains('History: [2.0, 3.0, 4.0, 5.0, 6.0]'));
    });
  });

  // -------------------------------------------------------------------------
  // parseMarkdown input robustness (empty / whitespace / BOM / non-Map).
  // -------------------------------------------------------------------------
  group('ExportLogic.parseMarkdown — input robustness', () {
    test('returns null on an empty string', () {
      expect(ExportLogic.parseMarkdown(''), isNull);
    });

    test('returns null on a whitespace-only string', () {
      expect(ExportLogic.parseMarkdown('   \n\t  \r\n  '), isNull);
    });

    test(
      'strips a UTF-8 BOM at the start of the document before validating',
      () {
        const body = '''---
app: TiltClock
---
<!-- STATE_JSON_START
{"tournamentName":"BOM Cup","totalRounds":4,"duration":20,"currentRoundNumber":0,"isTournamentStarted":true,"players":[],"rounds":[]}
STATE_JSON_END -->''';
        // Windows Notepad and some Markdown editors prepend a U+FEFF
        // byte-order mark.  parseMarkdown must not refuse such files.
        final punctuated = '\uFEFF$body';
        final parsed = ExportLogic.parseMarkdown(punctuated);
        expect(parsed, isNotNull, reason: 'BOM should not prevent parsing');
        expect(parsed!['tournamentName'], 'BOM Cup');
      },
    );

    test(
      'returns null when STATE_JSON markers exist but the payload is empty',
      () {
        // `<!-- STATE_JSON_START\nSTATE_JSON_END -->` has zero characters
        // of JSON between the markers.  Earlier code would call
        // jsonDecode('') which throws — must return null cleanly.
        const md = '''---
app: TiltClock
---
<!-- STATE_JSON_START
STATE_JSON_END -->''';
        expect(ExportLogic.parseMarkdown(md), isNull);
      },
    );

    test(
      'returns null when STATE_JSON_START appears AFTER STATE_JSON_END',
      () {
        // Defensive ordering check: if a user-edited file accidentally
        // swaps the markers, the substring(start + 16, end) window goes
        // negative-length / backwards.  Treat as invalid input.
        const md = '''---
app: TiltClock
---
<!-- STATE_JSON_END happens first
then later STATE_JSON_START
-->''';
        expect(ExportLogic.parseMarkdown(md), isNull);
      },
    );

    test(
      'returns null when jsonDecode yields a non-Map JSON value (array)',
      () {
        // jsonDecode('[1,2,3]') returns a List, but downstream
        // (importNewTournament, resumeFromData) treats `data['players']`
        // as a Map.  Falling back to null keeps the existing "Invalid
        // Tournament File" snackbar path active instead of throwing a
        // TypeError deep in the import flow.
        const md = '''---
app: TiltClock
---
<!-- STATE_JSON_START
[1, 2, 3]
STATE_JSON_END -->''';
        expect(ExportLogic.parseMarkdown(md), isNull);
      },
    );
  });
}

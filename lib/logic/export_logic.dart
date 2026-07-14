import 'dart:convert';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../models/player.dart';
import '../models/round.dart';
import '../models/pairing.dart';

class ExportLogic {
  static const String validationTag = 'app: TiltClock';

  static String sanitizeFileName(String name) {
    // Remove special characters and replace spaces with underscores
    return name.replaceAll(RegExp(r'[^\w\s\-]'), '').replaceAll(' ', '_');
  }

  /// Builds the markdown body for a tournament. Pure function (no I/O),
  /// intended as the canonical entry point for unit tests so that we can
  /// verify Buchholz, results formatting, round-trip integrity, etc.
  /// without invoking the platform-specific share channel.
  static String generateMarkdown({
    required String tournamentName,
    required List<Player> players,
    required List<Round> rounds,
    required int totalRounds,
    required int duration,
  }) {
    final now = DateTime.now();
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    final fileDateFormat = DateFormat('yyyy-MM-dd');
    final sb = StringBuffer();

    // Task 4: Integrated YAML-style Meta Header
    sb.writeln('---');
    sb.writeln('app: TiltClock');
    sb.writeln('club: All Knighters');
    sb.writeln('title: $tournamentName');
    sb.writeln('date: ${fileDateFormat.format(now)}');
    sb.writeln('---');
    sb.writeln();

    sb.writeln('# $tournamentName');
    sb.writeln('## All Knighters Chess Club | Tilt Clock Edition');
    sb.writeln('**Generated:** ${dateFormat.format(now)}');
    sb.writeln('**Settings:** $totalRounds Rounds | $duration min duration');
    sb.writeln();

    sb.writeln('## Final Leaderboard');
    sb.writeln('| Rank | Name | Points | Hcp | Total | Buchholz |');
    sb.writeln('|------|------|--------|-----|-------|----------|');

    final ranked = List<Player>.from(players);
    ranked.sort((a, b) {
      int cmp = b.totalScore.compareTo(a.totalScore);
      if (cmp != 0) return cmp;
      return _calculateBuchholz(
        b,
        players,
      ).compareTo(_calculateBuchholz(a, players));
    });

    for (int i = 0; i < ranked.length; i++) {
      final p = ranked[i];
      sb.writeln(
        '| ${i + 1} | ${p.name} | ${p.earnedPoints} | ${p.handicap} | ${p.totalScore} | ${_calculateBuchholz(p, players)} |',
      );
    }
    sb.writeln();

    sb.writeln('## Player Data & History');
    for (var p in ranked) {
      final nextHistory = List<double>.from(p.history)..add(p.earnedPoints);
      if (nextHistory.length > 5) nextHistory.removeAt(0);
      sb.writeln(
        '* ${p.name} | Score: ${p.earnedPoints} | Handicap: ${p.handicap} | History: [${nextHistory.join(", ")}]',
      );
    }
    sb.writeln();

    sb.writeln('## Full Match History');
    for (var round in rounds) {
      sb.writeln('### Round ${round.number}');
      sb.writeln('**Started:** ${dateFormat.format(round.startTime)}');
      if (round.completedTime != null) {
        sb.writeln('**Finalized:** ${dateFormat.format(round.completedTime!)}');
      }
      sb.writeln('| Board | White | Black | Result |');
      sb.writeln('|-------|-------|-------|--------|');
      for (int i = 0; i < round.pairings.length; i++) {
        final pair = round.pairings[i];
        final w = _getPlayerName(pair.whitePlayerId, players);
        final b = pair.isBye
            ? '*BYE*'
            : _getPlayerName(pair.blackPlayerId, players);
        sb.writeln('| ${i + 1} | $w | $b | ${_formatResult(pair.result)} |');
      }
      sb.writeln();
    }

    // Hidden section for technical resumption
    sb.writeln('<!-- STATE_JSON_START');
    final data = {
      'players': players.map((p) => p.toJson()).toList(),
      'rounds': rounds.map((r) => r.toJson()).toList(),
      'currentRoundNumber': rounds.length,
      'isTournamentStarted': true,
      'totalRounds': totalRounds,
      'duration': duration,
      'tournamentName': tournamentName,
    };
    sb.writeln(jsonEncode(data));
    sb.writeln('STATE_JSON_END -->');

    return sb.toString();
  }

  static Future<void> exportToMarkdown({
    required String tournamentName,
    required List<Player> players,
    required List<Round> rounds,
    required int totalRounds,
    required int duration,
  }) async {
    final now = DateTime.now();
    final fileDateFormat = DateFormat('yyyy-MM-dd');

    // Task 2: Dynamic Filename Formatting
    final sanitizedName = sanitizeFileName(tournamentName);
    final fileName = '${sanitizedName}_${fileDateFormat.format(now)}.md';

    final bytes = Uint8List.fromList(
      utf8.encode(
        generateMarkdown(
          tournamentName: tournamentName,
          players: players,
          rounds: rounds,
          totalRounds: totalRounds,
          duration: duration,
        ),
      ),
    );
    final xFile = XFile.fromData(
      bytes,
      mimeType: 'text/markdown',
      name: fileName,
    );

    await SharePlus.instance.share(
      ShareParams(
        files: [xFile],
        text: 'Chess Tournament: $tournamentName',
        fileNameOverrides: [fileName],
      ),
    );
  }

  static double _calculateBuchholz(Player player, List<Player> allPlayers) {
    double buchholz = 0;
    for (var opponentId in player.opponentsPlayed) {
      final opponent = allPlayers.firstWhere((p) => p.id == opponentId);
      buchholz += opponent.earnedPoints;
    }
    return buchholz;
  }

  static String _getPlayerName(String id, List<Player> players) {
    if (id == "BYE") return "BYE";
    return players.firstWhere((p) => p.id == id).name;
  }

  static String _formatResult(GameResult result) {
    switch (result) {
      case GameResult.whiteWin:
        return '1 - 0';
      case GameResult.blackWin:
        return '0 - 1';
      case GameResult.draw:
        return '½ - ½';
      case GameResult.bye:
        return '+ - -';
      case GameResult.pending:
        return '...';
    }
  }

  static Map<String, dynamic>? parseMarkdown(String content) {
    // Strip an optional UTF-8 BOM (Windows Notepad and some Markdown
    // editors emit one). Without this, downstream checks like
    // contains(validationTag) still match (the BOM sits at offset 0, not
    // between substrings) BUT keeping the BOM in the document can haunt
    // callers that re-emit or compare documents. Strip eagerly so all
    // downstream checks operate on the canonical document.
    String text = content;
    if (text.startsWith('\uFEFF')) {
      text = text.substring(1);
    }

    // Reject empty / whitespace-only input explicitly so users uploading
    // a zero-byte file don't get an opaque JSON error.
    if (text.trim().isEmpty) {
      return null;
    }

    // Task 3: Check for the app-specific tag so we don't try to parse
    // arbitrary user markdown as our state format.
    if (!text.contains(validationTag)) {
      return null;
    }

    try {
      final start = text.indexOf('STATE_JSON_START');
      final end = text.indexOf('STATE_JSON_END');
      // Both markers must exist AND the end must come AFTER the start,
      // otherwise substring(start + 16, end) is a 0-length or negative
      // window (the JSON payload is what callers actually depend on).
      if (start == -1 ||
          end == -1 ||
          end <= start + 'STATE_JSON_START'.length) {
        return null;
      }
      final jsonStr = text
          .substring(start + 'STATE_JSON_START'.length, end)
          .trim();
      if (jsonStr.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(jsonStr);
      // Guard against jsonDecode yielding a non-Map (array, scalar). The
      // callers — importNewTournament / resumeFromData — assume a Map
      // keyed by players / rounds / tournamentName etc. Returning null
      // here keeps the existing "Invalid Tournament File" UX path.
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      // Malformed JSON between the markers — treat as "not a valid
      // tournament export" rather than crashing the importer.
      return null;
    }
  }
}

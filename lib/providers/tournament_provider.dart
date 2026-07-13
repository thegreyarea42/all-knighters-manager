import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/player.dart';
import '../models/round.dart';
import '../models/pairing.dart';
import '../logic/pairing_engine.dart';

class TournamentProvider with ChangeNotifier {
  // Task 5: Unique storage key for All Knighters
  static const String _storageKey = 'ak_tm_data';

  /// Handicap centring constant. 5-round tournament earns span [0, 5], so
  /// 2.5 is the natural midpoint. Drives `importNewTournament`'s formula
  /// (used as both the empty-history default AND the formula's constant).
  /// Change with care — re-run
  /// `test/three_tournament_handicap_evolution_test.dart` after any shift
  /// to confirm the trajectory stays in the expected range.
  static const double handicapCenter = 2.5;

  List<Player> _players = [];
  List<Round> _rounds = [];
  int _currentRoundNumber = 0;
  bool _isTournamentStarted = false;
  String _tournamentName = "Weekly Club Tournament";

  // Timer State
  int _secondsRemaining = 0;
  bool _isTimerRunning = false;
  Timer? _ticker;
  String _r1pMode = 'Parity';

  List<Player> get players => _players;
  List<Round> get rounds => _rounds;
  int get currentRoundNumber => _currentRoundNumber;
  bool get isTournamentStarted => _isTournamentStarted;
  String get tournamentName => _tournamentName;
  int get secondsRemaining => _secondsRemaining;
  bool get isTimerRunning => _isTimerRunning;

  TournamentProvider() {
    loadFromPrefs();
  }

  void setTournamentName(String name) {
    _tournamentName = name;
    notifyListeners();
    saveToPrefs();
  }

  Round? get currentRound => _rounds.isNotEmpty ? _rounds.last : null;

  void addPlayer(String name, double handicap) {
    _players.add(
      Player(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        hadBye: false,
        handicap: handicap,
      ),
    );
    notifyListeners();
    saveToPrefs();
  }

  void removePlayer(String id) {
    _players.removeWhere((p) => p.id == id);
    notifyListeners();
    saveToPrefs();
  }

  void updatePlayerHandicap(String id, double handicap) {
    final player = _players.maybeFirstWhere((p) => p.id == id);
    if (player != null) {
      player.handicap = handicap;
      notifyListeners();
      saveToPrefs();
    }
  }

  void startTournament(
    int initialDurationMinutes, {
    String r1pMode = 'Parity',
  }) {
    if (_players.length < 2) return;
    _r1pMode = r1pMode;
    _isTournamentStarted = true;
    _secondsRemaining = initialDurationMinutes * 60;
    _nextRound();
  }

  void _nextRound() {
    _currentRoundNumber++;
    final isRound1 = _currentRoundNumber == 1;
    final pairings = PairingEngine.generatePairings(
      _players,
      isRound1: isRound1,
      r1pMode: _r1pMode,
    );

    pairings.sort((a, b) {
      if (a.isBye) return 1;
      if (b.isBye) return -1;
      final aSum =
          _players.firstWhere((p) => p.id == a.whitePlayerId).earnedPoints +
          _players.firstWhere((p) => p.id == a.blackPlayerId).earnedPoints;
      final bSum =
          _players.firstWhere((p) => p.id == b.whitePlayerId).earnedPoints +
          _players.firstWhere((p) => p.id == b.blackPlayerId).earnedPoints;
      return bSum.compareTo(aSum);
    });

    final newRound = Round(
      number: _currentRoundNumber,
      pairings: pairings,
      startTime: DateTime.now(),
    );
    _rounds.add(newRound);
    notifyListeners();
    saveToPrefs();
  }

  // Timer Controls
  void toggleTimer() {
    if (_isTimerRunning) {
      _ticker?.cancel();
    } else {
      _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_secondsRemaining > 0) {
          _secondsRemaining--;
          if (_secondsRemaining == 300) {
            _playWarningChime();
          }
          if (_secondsRemaining == 0) {
            _playBuzzer();
          }
          notifyListeners();
        } else {
          _ticker?.cancel();
          _isTimerRunning = false;
          notifyListeners();
        }
      });
    }
    _isTimerRunning = !_isTimerRunning;
    notifyListeners();
  }

  void _playBuzzer() {
    try {
      HapticFeedback.heavyImpact();
      final player = AudioPlayer();
      player.play(AssetSource('sounds/buzzer.mp3'));
    } catch (_) {}
  }

  void _playWarningChime() {
    try {
      HapticFeedback.mediumImpact();
      final player = AudioPlayer();
      player.play(AssetSource('sounds/chime.mp3'));
    } catch (_) {}
  }

  void importNewTournament(Map<String, dynamic> data) {
    _players = [];
    final oldPlayers = (data['players'] as List)
        .map((p) => Player.fromJson(p))
        .toList();
    for (var p in oldPlayers) {
      // Recompute each player's handicap from their final score + 5-game
      // history average. Centring on `handicapCenter` (= 2.5) keeps fresh
      // extremes at ±1.25 (no clamp) and veteran extremes clamping
      // symmetrically at ±1.5. (Previously `2.0` produced asymmetric fresh
      // range: winners clamped at -1.5 while losers only reached +1.0.)
      double historyAvg = handicapCenter;
      if (p.history.isNotEmpty) {
        historyAvg = p.history.reduce((a, b) => a + b) / p.history.length;
      }

      double newHandicap = handicapCenter - ((p.earnedPoints + historyAvg) / 2);
      newHandicap = newHandicap.clamp(-1.5, 1.5);

      final newHistory = List<double>.from(p.history)..add(p.earnedPoints);
      if (newHistory.length > 5) {
        newHistory.removeAt(0);
      }

      _players.add(
        Player(
          id: p.id,
          name: p.name,
          handicap: newHandicap,
          history: newHistory,
          earnedPoints: 0.0,
        ),
      );
    }

    _rounds = [];
    _currentRoundNumber = 0;
    _isTournamentStarted = false;
    _secondsRemaining = 0;
    _ticker?.cancel();
    _isTimerRunning = false;

    notifyListeners();
    saveToPrefs();
  }

  void adjustTime(int seconds) {
    _secondsRemaining = (_secondsRemaining + seconds).clamp(0, 3600);
    notifyListeners();
  }

  void stopRoundNow() {
    _secondsRemaining = 0;
    _ticker?.cancel();
    _isTimerRunning = false;
    notifyListeners();
  }

  void updateResult(String whiteId, String blackId, GameResult result) {
    if (currentRound == null) return;
    final pairing = currentRound!.pairings.firstWhere(
      (p) => p.whitePlayerId == whiteId && p.blackPlayerId == blackId,
    );
    pairing.result = result;
    recalculateStandings();
  }

  // Task 3: Result Correction & Auto-Recalculate
  void correctResult(
    int roundNumber,
    String whiteId,
    String blackId,
    GameResult newResult,
  ) {
    final round = _rounds.firstWhere((r) => r.number == roundNumber);
    final pairing = round.pairings.firstWhere(
      (p) => p.whitePlayerId == whiteId && p.blackPlayerId == blackId,
    );
    pairing.result = newResult;
    recalculateStandings();
  }

  void recalculateStandings() {
    // Reset all dynamic stats for all players
    for (var p in _players) {
      p.earnedPoints = 0;
      p.colorHistory = [];
      p.opponentsPlayed = [];
      p.hadBye = false;
    }

    // Apply results from ALL stored rounds chronologically
    for (var round in _rounds) {
      for (var pairing in round.pairings) {
        if (pairing.result == GameResult.pending) continue;

        final white = _players.firstWhere((p) => p.id == pairing.whitePlayerId);

        if (pairing.isBye) {
          white.earnedPoints += 1.0;
          white.hadBye = true;
        } else {
          final black = _players.maybeFirstWhere(
            (p) => p.id == pairing.blackPlayerId,
          );
          if (black == null) continue; // Should not happen

          white.colorHistory.add(ChessColor.white);
          white.opponentsPlayed.add(black.id);
          black.colorHistory.add(ChessColor.black);
          black.opponentsPlayed.add(white.id);

          if (pairing.result == GameResult.whiteWin) {
            white.earnedPoints += 1.0;
          } else if (pairing.result == GameResult.blackWin) {
            black.earnedPoints += 1.0;
          } else if (pairing.result == GameResult.draw) {
            white.earnedPoints += 0.5;
            black.earnedPoints += 0.5;
          }
        }
      }
    }
    notifyListeners();
    saveToPrefs();
  }

  void submitRound() {
    if (currentRound == null || currentRound!.isCompleted) return;
    currentRound!.isCompleted = true;
    currentRound!.completedTime = DateTime.now();
    recalculateStandings();
  }

  void startNextRound(int nextRoundDurationMinutes) {
    _secondsRemaining = nextRoundDurationMinutes * 60;
    _isTimerRunning = false;
    _ticker?.cancel();
    _nextRound();
  }

  void finalizeTournament() {
    _isTournamentStarted = false;
    notifyListeners();
    saveToPrefs();
  }

  double calculateBuchholz(Player player) {
    double buchholz = 0;
    for (var opponentId in player.opponentsPlayed) {
      final opponent = _players.maybeFirstWhere((p) => p.id == opponentId);
      if (opponent != null) buchholz += opponent.earnedPoints;
    }
    return buchholz;
  }

  List<Player> getRankedPlayers() {
    List<Player> ranked = List.from(_players);
    ranked.sort((a, b) {
      int cmp = b.totalScore.compareTo(a.totalScore);
      if (cmp != 0) return cmp;
      return calculateBuchholz(b).compareTo(calculateBuchholz(a));
    });
    return ranked;
  }

  Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'players': _players.map((p) => p.toJson()).toList(),
      'rounds': _rounds.map((r) => r.toJson()).toList(),
      'currentRoundNumber': _currentRoundNumber,
      'isTournamentStarted': _isTournamentStarted,
      'tournamentName': _tournamentName,
      'secondsRemaining': _secondsRemaining,
    };
    await prefs.setString(_storageKey, jsonEncode(data));
  }

  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr != null) {
      final data = jsonDecode(jsonStr);
      _players = (data['players'] as List)
          .map((p) => Player.fromJson(p))
          .toList();
      _rounds = (data['rounds'] as List).map((r) => Round.fromJson(r)).toList();
      _currentRoundNumber = data['currentRoundNumber'];
      _isTournamentStarted = data['isTournamentStarted'];
      _tournamentName = data['tournamentName'] ?? "Weekly Club Tournament";
      _secondsRemaining = data['secondsRemaining'] ?? 0;
      notifyListeners();
    }
  }

  void resumeFromData(Map<String, dynamic> data) {
    _players = (data['players'] as List)
        .map((p) => Player.fromJson(p))
        .toList();
    _rounds = (data['rounds'] as List).map((r) => Round.fromJson(r)).toList();
    _currentRoundNumber = data['currentRoundNumber'];
    _isTournamentStarted = data['isTournamentStarted'];
    _tournamentName =
        data['tournamentName'] ?? data['title'] ?? "Weekly Club Tournament";
    _secondsRemaining = data['secondsRemaining'] ?? 0;
    notifyListeners();
    saveToPrefs();
  }

  void resetTournament() async {
    _players = [];
    _rounds = [];
    _currentRoundNumber = 0;
    _isTournamentStarted = false;
    _secondsRemaining = 0;
    _ticker?.cancel();
    _isTimerRunning = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

extension ListExt<T> on List<T> {
  T? maybeFirstWhere(bool Function(T) test) {
    try {
      return firstWhere(test);
    } catch (_) {
      return null;
    }
  }
}

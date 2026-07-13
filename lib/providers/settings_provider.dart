import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider with ChangeNotifier {
  static const String _durationKey = 'ak_tm_round_duration';
  static const String _roundsKey = 'ak_tm_total_rounds';
  static const String _r1PairingKey = 'ak_tm_r1_pairing';

  int _roundDuration = 20;
  int _totalRounds = 4;
  String _round1PairingMode = 'Parity';

  int get roundDuration => _roundDuration;
  int get totalRounds => _totalRounds;
  String get round1PairingMode => _round1PairingMode;

  SettingsProvider() {
    _loadSettings();
  }

  void _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _roundDuration = prefs.getInt(_durationKey) ?? 20;
    _totalRounds = prefs.getInt(_roundsKey) ?? 4;
    _round1PairingMode = prefs.getString(_r1PairingKey) ?? 'Parity';
    notifyListeners();
  }

  void updateSettings(int duration, int rounds, {String? r1PairingMode}) async {
    _roundDuration = duration;
    _totalRounds = rounds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_durationKey, duration);
    await prefs.setInt(_roundsKey, rounds);
    if (r1PairingMode != null) {
      _round1PairingMode = r1PairingMode;
      await prefs.setString(_r1PairingKey, r1PairingMode);
    }
    notifyListeners();
  }
}

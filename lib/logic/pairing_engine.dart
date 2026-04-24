import '../models/player.dart';
import '../models/pairing.dart';

class PairingEngine {
  static List<Pairing> generatePairings(
    List<Player> players, {
    bool isRound1 = false,
    String r1pMode = 'Parity',
  }) {
    List<Player> activePlayers = List.from(players);
    List<Pairing> pairings = [];

    // 1. Handle Bye if odd
    if (activePlayers.length % 2 != 0) {
      Player? byePlayer;
      if (isRound1) {
        // Round 1: odd number, lowest handicap (newest/weakest player) gets bye. Weakest = highest actual value
        activePlayers.sort((a, b) => b.handicap.compareTo(a.handicap));
        byePlayer = activePlayers.first;
      } else {
        // Find lowest ranked player who hasn't had a bye
        activePlayers.sort((a, b) => a.earnedPoints.compareTo(b.earnedPoints));
        for (var player in activePlayers) {
          if (!player.hadBye) {
            byePlayer = player;
            break;
          }
        }
      }
      byePlayer ??= activePlayers.first;

      pairings.add(
        Pairing(
          whitePlayerId: byePlayer.id,
          blackPlayerId: "BYE",
          result: GameResult.bye,
        ),
      );
      activePlayers.remove(byePlayer);
    }

    if (isRound1) {
      // Pre-shuffle so identical handicaps are randomized due to stable sort
      activePlayers.shuffle();
      if (r1pMode == 'Random') {
        for (int i = 0; i < activePlayers.length; i += 2) {
          pairings.add(Pairing(whitePlayerId: activePlayers[i].id, blackPlayerId: activePlayers[i + 1].id));
        }
        return pairings;
      } else if (r1pMode == 'Seeded') {
        activePlayers.sort((a, b) => a.handicap.compareTo(b.handicap)); // Strongest first
        int half = activePlayers.length ~/ 2;
        for (int i = 0; i < half; i++) {
          pairings.add(Pairing(whitePlayerId: activePlayers[i].id, blackPlayerId: activePlayers[i + half].id));
        }
        return pairings;
      } else {
        // Default: Parity
        activePlayers.sort((a, b) => a.handicap.compareTo(b.handicap)); // Strongest first
        for (int i = 0; i < activePlayers.length; i += 2) {
          pairings.add(Pairing(whitePlayerId: activePlayers[i].id, blackPlayerId: activePlayers[i + 1].id));
        }
        return pairings;
      }
    }

    // Rounds 2 and Beyond -> Swiss System
    activePlayers.sort((a, b) => b.earnedPoints.compareTo(a.earnedPoints));

    // 3. Pair players (Greedy with backtracking or simplified Swiss)
    List<Pairing>? result = _recursivePair(activePlayers, []);
    if (result != null) {
      pairings.addAll(result);
    }

    return pairings;
  }

  static List<Pairing>? _recursivePair(
    List<Player> players,
    List<Pairing> currentPairings,
  ) {
    if (players.isEmpty) return currentPairings;

    Player p1 = players.first;
    for (int i = 1; i < players.length; i++) {
      Player p2 = players[i];

      // Check if they played before
      if (p1.opponentsPlayed.contains(p2.id)) continue;

      // Determine colors based on history
      // colorBalance: white - black
      // We want to balance colors.
      bool p1White;
      if (p1.colorBalance > p2.colorBalance) {
        p1White = false; // p1 has more whites, give him black
      } else if (p1.colorBalance < p2.colorBalance) {
        p1White = true; // p2 has more whites, give p1 white
      } else {
        // Equal balance, check last color if available
        if (p1.colorHistory.isNotEmpty &&
            p1.colorHistory.last == ChessColor.white) {
          p1White = false;
        } else {
          p1White = true;
        }
      }

      Pairing pairing = p1White
          ? Pairing(whitePlayerId: p1.id, blackPlayerId: p2.id)
          : Pairing(whitePlayerId: p2.id, blackPlayerId: p1.id);

      List<Player> remaining = List.from(players);
      remaining.remove(p1);
      remaining.remove(p2);

      List<Pairing>? result = _recursivePair(remaining, [
        ...currentPairings,
        pairing,
      ]);
      if (result != null) return result;
    }

    return null; // No valid pairing found
  }
}

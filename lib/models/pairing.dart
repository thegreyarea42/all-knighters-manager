enum GameResult { pending, whiteWin, blackWin, draw, bye }

class Pairing {
  final String whitePlayerId;
  final String blackPlayerId; // Empty for bye
  GameResult result;

  Pairing({
    required this.whitePlayerId,
    required this.blackPlayerId,
    this.result = GameResult.pending,
  });

  bool get isBye => blackPlayerId == "BYE";

  Map<String, dynamic> toJson() {
    return {
      'whitePlayerId': whitePlayerId,
      'blackPlayerId': blackPlayerId,
      'result': result.index,
    };
  }

  factory Pairing.fromJson(Map<String, dynamic> json) {
    return Pairing(
      whitePlayerId: json['whitePlayerId'],
      blackPlayerId: json['blackPlayerId'],
      result: GameResult.values[json['result']],
    );
  }
}

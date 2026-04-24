enum ChessColor { white, black, none }

class Player {
  final String id;
  final String name;
  double earnedPoints;
  double handicap;
  List<ChessColor> colorHistory;
  List<String> opponentsPlayed;
  List<double> history;
  bool hadBye;

  Player({
    required this.id,
    required this.name,
    this.earnedPoints = 0.0,
    this.handicap = 0.0,
    List<ChessColor>? colorHistory,
    List<String>? opponentsPlayed,
    List<double>? history,
    this.hadBye = false,
  }) : colorHistory = colorHistory ?? [],
       opponentsPlayed = opponentsPlayed ?? [],
       history = history ?? [];

  double get totalScore => earnedPoints + handicap;

  int get colorBalance {
    int balance = 0;
    for (var color in colorHistory) {
      if (color == ChessColor.white) balance++;
      if (color == ChessColor.black) balance--;
    }
    return balance;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'earnedPoints': earnedPoints,
      'handicap': handicap,
      'colorHistory': colorHistory.map((c) => c.index).toList(),
      'opponentsPlayed': opponentsPlayed,
      'history': history,
      'hadBye': hadBye,
    };
  }

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'],
      name: json['name'],
      earnedPoints: (json['earnedPoints'] ?? json['score'] ?? 0.0).toDouble(),
      handicap: (json['handicap'] ?? 0.0).toDouble(),
      colorHistory: (json['colorHistory'] as List)
          .map((i) => ChessColor.values[i])
          .toList(),
      opponentsPlayed: List<String>.from(json['opponentsPlayed']),
      history: List<double>.from(json['history'] ?? []),
      hadBye: json['hadBye'] ?? false,
    );
  }

  Player copyWith({
    double? earnedPoints,
    double? handicap,
    List<ChessColor>? colorHistory,
    List<String>? opponentsPlayed,
    List<double>? history,
    bool? hadBye,
  }) {
    return Player(
      id: id,
      name: name,
      earnedPoints: earnedPoints ?? this.earnedPoints,
      handicap: handicap ?? this.handicap,
      colorHistory: colorHistory ?? List.from(this.colorHistory),
      opponentsPlayed: opponentsPlayed ?? List.from(this.opponentsPlayed),
      history: history ?? List.from(this.history),
      hadBye: hadBye ?? this.hadBye,
    );
  }
}

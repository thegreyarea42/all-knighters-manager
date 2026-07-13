import 'pairing.dart';

class Round {
  final int number;
  final List<Pairing> pairings;
  final DateTime startTime;
  DateTime? completedTime;
  bool isCompleted;

  Round({
    required this.number,
    required this.pairings,
    required this.startTime,
    this.completedTime,
    this.isCompleted = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'number': number,
      'pairings': pairings.map((p) => p.toJson()).toList(),
      'startTime': startTime.toIso8601String(),
      'completedTime': completedTime?.toIso8601String(),
      'isCompleted': isCompleted,
    };
  }

  factory Round.fromJson(Map<String, dynamic> json) {
    return Round(
      number: json['number'],
      pairings: (json['pairings'] as List)
          .map((p) => Pairing.fromJson(p))
          .toList(),
      startTime: DateTime.parse(json['startTime']),
      completedTime: json['completedTime'] != null
          ? DateTime.parse(json['completedTime'])
          : null,
      isCompleted: json['isCompleted'],
    );
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:chess_tournament_manager/main.dart';
import 'package:provider/provider.dart';
import 'package:chess_tournament_manager/providers/tournament_provider.dart';

void main() {
  testWidgets('Smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => TournamentProvider(),
        child: const TournamentApp(),
      ),
    );
    expect(find.text('Tournament Check-in'), findsOneWidget);
  });
}

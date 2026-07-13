import 'package:flutter_test/flutter_test.dart';
import 'package:chess_tournament_manager/main.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chess_tournament_manager/providers/tournament_provider.dart';
import 'package:chess_tournament_manager/providers/settings_provider.dart';

void main() {
  setUp(() {
    // TournamentProvider's constructor fires loadFromPrefs() asynchronously;
    // without mocking the platform channel, that throws MissingPluginException
    // and the widget tree fails to build cleanly with a noisy error overlay.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('Smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => TournamentProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: const TournamentApp(),
      ),
    );
    expect(find.text('Tournament Check-in'), findsOneWidget);
  });
}

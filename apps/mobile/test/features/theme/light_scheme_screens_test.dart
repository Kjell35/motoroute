import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_theme.dart';
import 'package:motoroute_app/features/chat/presentation/chat_hub_screen.dart';
import 'package:motoroute_app/features/garage/garage_screen.dart';
import 'package:motoroute_app/features/tour_diary/presentation/tour_diary_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Garage, Chat und Touren faerben Flaechen und Texte selbst. Sie muessen
/// deshalb die Palette des AKTIVEN Schemas nutzen - vorher standen dort die
/// festen dunklen Tokens, und im hellen Schema lagen dunkle Flaechen unter
/// dunklen, aus dem Theme geerbten Texten.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget harness(Widget home) => ProviderScope(
        child: MaterialApp(theme: AppTheme.light, home: home),
      );

  Future<void> pumpLight(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(harness(home));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Scaffold scaffoldOf(WidgetTester tester) =>
      tester.widget<Scaffold>(find.byType(Scaffold).first);

  /// Ein Text, der im hellen Schema den Primaertext-Token traegt.
  final lightPrimaryText = find.byWidgetPredicate(
    (w) => w is Text && w.style?.color == AppColors.textPrimaryLight,
  );

  testWidgets('Garage nutzt im hellen Schema helle Flaeche und dunklen Text',
      (tester) async {
    await pumpLight(tester, const GarageScreen());

    expect(scaffoldOf(tester).backgroundColor, AppColors.bgBaseLight);
    expect(
      tester
          .widget<AppBar>(find.byType(AppBar).first)
          .backgroundColor,
      AppColors.bgBaseLight,
    );
    expect(lightPrimaryText, findsWidgets);
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && w.style?.color == AppColors.textPrimaryDark,
      ),
      findsNothing,
    );
  });

  testWidgets('Chat-Hub nutzt im hellen Schema die helle Palette',
      (tester) async {
    await pumpLight(tester, const ChatHubScreen());

    expect(scaffoldOf(tester).backgroundColor, AppColors.bgBaseLight);
    expect(lightPrimaryText, findsWidgets);
  });

  testWidgets('Touren nutzen im hellen Schema helle Flaeche und dunklen Text',
      (tester) async {
    await pumpLight(tester, const TourDiaryScreen());

    expect(scaffoldOf(tester).backgroundColor, AppColors.bgBaseLight);
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && w.style?.color == AppColors.textPrimaryDark,
      ),
      findsNothing,
    );
  });
}

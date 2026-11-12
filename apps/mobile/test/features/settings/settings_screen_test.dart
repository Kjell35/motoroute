import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:motoroute_app/core/network/error_reporter.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_theme.dart';
import 'package:motoroute_app/features/auth/auth_providers.dart';
import 'package:motoroute_app/core/i18n/i18n.dart';
import 'package:motoroute_app/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Admin-Konto ohne Backend: der Screen liest nur [AuthState.user].
class _AdminAuthController extends AuthController {
  _AdminAuthController() {
    state = const AuthState(
      user: AuthUser(id: 'admin-1', email: 'admin@example.com', isAdmin: true),
    );
  }
}

void main() {
  testWidgets('Settings rendert ohne Diagnose (entfernt) und mit Profil-Header',
      (tester) async {
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Diagnose ist bewusst raus (Release für normale Nutzer).
    expect(find.text('Diagnose'), findsNothing);
    expect(find.text('Tests starten'), findsNothing);

    // Calimoto-Look: Profil-Header mit Avatar + Sektionstitel in
    // Normalschreibung (nicht mehr Caps-Labels).
    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(find.text('Navigation'), findsOneWidget);

    // Auch normale Nutzer sehen den Reporter-Status - aber reduziert:
    // kein technischer Fehlergrund, kein Zurücksetzen-Knopf.
    await tester.scrollUntilVisible(
      find.text('Community'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Community'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.tap(find.text('Community'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.scrollUntilVisible(
      find.textContaining('beim Support angekommen'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.textContaining('beim Support angekommen'));
    // ensureVisible springt sofort, das Layout braucht aber einen Frame -
    // sonst rechnet der naechste tap() noch mit der alten Position.
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.textContaining('beim Support angekommen'), findsOneWidget);
    expect(find.textContaining('noch kein Bericht'), findsNothing);
    expect(find.byIcon(Icons.restart_alt), findsNothing);

    // Kopieren legt GENAU die angezeigte Zeile in die Zwischenablage.
    expect(find.byIcon(Icons.content_copy), findsOneWidget);
    await tester.ensureVisible(find.byIcon(Icons.content_copy));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(Icons.content_copy));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(copiedText, 'Noch kein Fehlerbericht beim Support angekommen.');
    expect(find.text('Status kopiert.'), findsOneWidget);
  });

  testWidgets('Admin setzt die Reporter-Zähler erst nach Rückfrage zurück',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    ErrorReporter.instance.debugReset();
    // Ein Bericht ist am Server gescheitert und wartet in der Warteschlange.
    // Bewusst ohne init(): das laedt PackageInfo ueber einen Plattform-Kanal,
    // auf den Fake-Async in Widget-Tests nie antwortet - der Test wuerde
    // haengen. Der injizierte Sender reicht fuer den Versand.
    ErrorReporter.instance.debugConfigure(
      sender: (payload) async => 400,
      appVersion: '1.0.3',
    );
    ErrorReporter.instance.report('chat.load', StateError('test'));
    await ErrorReporter.instance.debugIdle();
    expect(ErrorReporter.instance.diagnostics.queued, 1);
    expect(ErrorReporter.instance.diagnostics.failed, 1);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => _AdminAuthController()),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Community-Sektion aufklappen (startet eingeklappt). Sie liegt weit
    // unten in der ListView und wird erst beim Scrollen gebaut.
    await tester.scrollUntilVisible(
      find.text('Community'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Community'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.tap(find.text('Community'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.scrollUntilVisible(
      find.byIcon(Icons.restart_alt),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // scrollUntilVisible haelt sich fuer fertig, sobald das Widget GEBAUT
    // ist - es kann trotzdem unterhalb des Viewports liegen. ensureVisible
    // holt die Diagnosezeile wirklich ins Bild, sonst tippt der Test
    // ins Leere.
    await tester.ensureVisible(find.byIcon(Icons.restart_alt));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.textContaining('1 warten auf Versand'), findsOneWidget);
    // Kopieren gibt es auch für Admins, direkt neben dem Zurücksetzen.
    expect(find.byIcon(Icons.content_copy), findsOneWidget);
    expect(find.byIcon(Icons.restart_alt), findsOneWidget);

    // Tipp auf den Knopf fragt nach, weil ein Bericht verloren ginge.
    await tester.tap(find.byIcon(Icons.restart_alt));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.text('Diagnose zurücksetzen?'), findsOneWidget);
    expect(find.textContaining('1 wartende Berichte'), findsOneWidget);

    // Abbrechen: alles bleibt, wie es war.
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.text('Diagnose zurücksetzen?'), findsNothing);
    expect(ErrorReporter.instance.diagnostics.queued, 1);
    expect(ErrorReporter.instance.diagnostics.failed, 1);
    expect(find.textContaining('1 warten auf Versand'), findsOneWidget);

    // Verwerfen: Zähler und Warteschlange sind leer.
    await tester.tap(find.byIcon(Icons.restart_alt));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.tap(find.text('Verwerfen'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.text('Diagnose zurücksetzen?'), findsNothing);
    expect(ErrorReporter.instance.diagnostics.queued, 0);
    expect(ErrorReporter.instance.diagnostics.attempted, 0);
    expect(find.text('Noch kein Bericht gesendet.'), findsOneWidget);
  });

  testWidgets('Diagnosezeile folgt der Sprachwahl (EN)', (tester) async {
    ErrorReporter.instance.debugReset();
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          i18nProvider.overrideWith((ref) => const I18n(AppLanguage.en)),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.scrollUntilVisible(
      find.text('Community'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Community'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.tap(find.text('Community'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    // Konto-Sektion folgt ebenfalls der Sprachwahl (abgemeldet).
    await tester.scrollUntilVisible(
      find.text('Not signed in'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.text('Nicht angemeldet'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);

    // Auch die uebrigen Texte der Sektion folgen der Sprachwahl.
    expect(find.text('Send anonymous error reports'), findsOneWidget);
    expect(find.text('Anonyme Fehlerberichte senden'), findsNothing);
    expect(find.textContaining('Helps support find outages'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.textContaining('reached support'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.textContaining('reached support'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // Kein deutscher Rest, sondern der englische Katalog-Text.
    expect(find.text('No error report has reached support yet.'),
        findsOneWidget);
    expect(find.textContaining('beim Support angekommen'), findsNothing);

    await tester.ensureVisible(find.byIcon(Icons.content_copy));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(Icons.content_copy));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(copiedText, 'No error report has reached support yet.');
    expect(find.text('Status copied.'), findsOneWidget);
  });

  testWidgets('Helles Schema nutzt die Light-Tokens', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Flaechen und Untertitel muessen der Helligkeit des Themes folgen.
    // Mit den fest verdrahteten Dark-Tokens war der Screen im hellen
    // Schema dunkel auf dunkel und damit unlesbar.
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppColors.bgBaseLight);
    final subtitle = tester.widget<Text>(
        find.text('Beeinflusst Routing und Dauer'));
    expect(subtitle.style?.color, AppColors.textSecondaryLight);

    // Durchsichtige AppBar: ohne expliziten Stil blieben die
    // Statusleisten-Symbole hell auf hellem Grund.
    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find
          .descendant(
            of: find.byType(AppBar),
            matching:
                find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          )
          .first,
    );
    expect(region.value, AppTheme.statusOverlayLight);
  });
}

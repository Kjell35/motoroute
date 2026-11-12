import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/chat/presentation/conversation_screen.dart';

/// Ein fehlgeschlagener Sendevorgang darf nicht damit enden, dass der
/// Nutzer den Text wiederfindet und den Sendeknopf suchen muss: die Meldung
/// bietet den zweiten Versuch direkt an.
void main() {
  testWidgets('Meldung zeigt den zweiten Versuch und ruft ihn auf',
      (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                chatSendFailedSnackBar(
                  message: 'Senden fehlgeschlagen: kein Netz',
                  onRetry: () => retries++,
                ),
              ),
              child: const Text('zeigen'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('zeigen'));
    await tester.pumpAndSettle();

    expect(find.text('Senden fehlgeschlagen: kein Netz'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Erneut senden'),
        findsOneWidget);

    await tester.tap(find.text('Erneut senden'));
    await tester.pumpAndSettle();

    expect(retries, 1);
  });

  test('Meldung hat genau eine Aktion und keinen Auto-Hinweis', () {
    final snack = chatSendFailedSnackBar(message: 'kaputt', onRetry: () {});
    expect(snack.action, isNotNull);
    expect(snack.action!.label, 'Erneut senden');
    expect(snack.duration, const Duration(seconds: 6));
  });
}

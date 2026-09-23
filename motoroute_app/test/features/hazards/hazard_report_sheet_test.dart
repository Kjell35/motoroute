import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/hazards/presentation/hazard_report_sheet.dart';

void main() {
  testWidgets('2-Klick-Vertrag: Button erst nach Typ-Wahl aktiv', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: _SheetHost())),
      ),
    );

    // Klick 0: Sheet öffnen.
    await tester.tap(find.byKey(const Key('open-sheet')));
    await tester.pumpAndSettle();

    // Vor der Typ-Wahl: Button deaktiviert ("Erst Typ wählen").
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Erst Typ wählen'),
    );
    expect(button.onPressed, isNull);

    // Klick 1: Typ auswählen -> Button wird aktiv und benennt die Aktion.
    await tester.tap(find.text('🛢️ Ölspur'));
    await tester.pump();

    final active = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '🛢️ Ölspur MELDEN'),
    );
    expect(active.onPressed, isNotNull);
  });

  testWidgets('alle 4 Typen sind sichtbar und antippbar', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: _SheetHost())),
      ),
    );
    await tester.tap(find.byKey(const Key('open-sheet')));
    await tester.pumpAndSettle();

    expect(find.text('🚧 Rollsplitt'), findsOneWidget);
    expect(find.text('⛔ Sperrung'), findsOneWidget);
    expect(find.text('🚜 Baustelle'), findsOneWidget);
    expect(find.text('🛢️ Ölspur'), findsOneWidget);
  });

  testWidgets('Typ-Wechsel: letzte Wahl gewinnt', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: _SheetHost())),
      ),
    );
    await tester.tap(find.byKey(const Key('open-sheet')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('🚧 Rollsplitt'));
    await tester.pump();
    await tester.tap(find.text('⛔ Sperrung'));
    await tester.pump();

    expect(
      find.widgetWithText(ElevatedButton, '⛔ Sperrung MELDEN'),
      findsOneWidget,
    );
  });
}

class _SheetHost extends StatelessWidget {
  const _SheetHost();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        key: const Key('open-sheet'),
        onPressed: () => showHazardReportSheet(context),
        child: const Text('melden'),
      ),
    );
  }
}

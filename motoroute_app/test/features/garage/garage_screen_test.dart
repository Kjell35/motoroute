import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/garage/garage_screen.dart';
import 'package:motoroute_app/features/garage/garage_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Garage-Tab ohne Konto zeigt Verbinden-Karte (kein grauer Screen, kein Login-Formular)', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: GarageScreen()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(GarageScreen), findsOneWidget);
    // Kein Login-Formular mehr: Auto-Provisioning statt E-Mail/Passwort.
    expect(find.byType(TextField), findsNothing);
    // Die Verbinden-Karte ist da (Texte aus i18n, mit Fallback-Katalog).
    expect(find.textContaining('Garage'), findsWidgets);
  });

  testWidgets('Garage-Übersicht: Server-Fehler erscheint als Liste mit Meldung, nicht als Grau', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('garage.accessToken', 'test-token');
    await prefs.setString('garage.email', 'test@example.com');

    final container = ProviderContainer(overrides: [
      garageRepositoryProvider.overrideWithValue(_FailingGarageRepository()),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GarageScreen()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.byWidgetPredicate((w) => w is Text && (w.data?.contains('RenderException') ?? false)),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate((w) => w is Text && (w.data?.contains('Garage') ?? false)),
      findsWidgets,
    );
  });
}

class _FailingGarageRepository extends GarageRepository {
  _FailingGarageRepository() : super(Dio());

  @override
  Future<List<GarageVehicle>> garage(String baseUrl, String token) async {
    throw GarageApiException('Simulierter Server-Ausfall', 503);
  }
}

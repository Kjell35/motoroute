import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/weather/route_weather_providers.dart';
import 'package:motoroute_app/features/weather/route_weather_widget.dart';

RouteWeatherReport _report({
  String? alertMessage,
  StormSeverity alertSeverity = StormSeverity.none,
  int destinationCode = 800,
  double destinationTemp = 21,
  List<ShelterPoi> shelters = const [],
}) {
  return RouteWeatherReport(
    isEnabled: true,
    alertMessage: alertMessage,
    alertSeverity: alertSeverity,
    destinationSegment: RouteWeatherSegment(
      distanceFromStartM: 1000,
      time: DateTime.parse('2026-09-18T10:00:00.000Z'),
      tempC: destinationTemp,
      precipitationMmH: 0,
      conditionCode: destinationCode,
      severity: StormSeverity.none,
    ),
    shelters: shelters,
  );
}

/// Override des GLOBALEN Providers - das Widget watcht genau ihn, ein
/// separater Inline-Provider würde es nie erreichen (das hat der erste
/// Testlauf gezeigt).
Widget _host(RouteWeatherState state) {
  return ProviderScope(
    overrides: [
      routeWeatherControllerProvider.overrideWith(
        (ref) => _StubController(state),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const Scaffold(body: RouteWeatherWidget()),
    ),
  );
}

/// Setzt den State direkt - der Widget-Test will nicht den ganzen
/// Controller+Repository-Apparat starten.
class _StubController extends RouteWeatherController {
  _StubController(RouteWeatherState initialState) : super(_NoopRepo()) {
    state = initialState;
  }
}

class _NoopRepo implements RouteWeatherRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('dezent bei gutem Wetter: Zeile mit Temperatur, kein Alarm', (
    tester,
  ) async {
    await tester.pumpWidget(_host(
      RouteWeatherState(report: _report()),
    ));

    expect(find.text('21° · gute Fahrt'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('Feature aus (kein API-Key): gar nichts gerendert', (
    tester,
  ) async {
    await tester.pumpWidget(_host(
      const RouteWeatherState(
        report: RouteWeatherReport(isEnabled: false),
      ),
    ));
    expect(find.text('21° · gute Fahrt'), findsNothing);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('Unwetter: roter Alarm-Streifen mit Backend-Meldung', (
    tester,
  ) async {
    await tester.pumpWidget(_host(
      RouteWeatherState(
        report: _report(
          alertMessage: 'In 20 km zieht ein Gewitter auf: Gewitter',
          alertSeverity: StormSeverity.danger,
        ),
      ),
    ));

    expect(
        find.text('In 20 km zieht ein Gewitter auf: Gewitter'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('Tap auf Alarm öffnet Schutz-POI-Sheet mit Hotels/Treffs', (
    tester,
  ) async {
    await tester.pumpWidget(_host(
      RouteWeatherState(
        report: _report(
          alertMessage: 'In 20 km zieht ein Gewitter auf: Gewitter',
          alertSeverity: StormSeverity.danger,
          shelters: [
            const ShelterPoi(
              id: 'h1',
              name: 'Bikerhotel Adler',
              category: 'MOTO_HOTEL',
              lat: 48.1,
              lng: 11.2,
              distanceFromRouteM: 800,
            ),
            const ShelterPoi(
              id: 't1',
              name: 'Sonnenterrasse',
              category: 'BIKER_MEETUP',
              lat: 48.2,
              lng: 11.3,
              distanceFromRouteM: 1500,
            ),
          ],
        ),
      ),
    ));

    await tester.tap(find.text('In 20 km zieht ein Gewitter auf: Gewitter'));
    await tester.pumpAndSettle();

    expect(find.text('Bikerhotel Adler'), findsOneWidget);
    expect(find.text('Sonnenterrasse'), findsOneWidget);
    expect(find.textContaining('Motorradhotel'), findsOneWidget);
    expect(find.textContaining('Bikertreff'), findsOneWidget);
    expect(find.text('Verstanden'), findsOneWidget);
  });

  testWidgets('Alarm ohne Shelters: Sheet zeigt ehrlichen Hinweis', (
    tester,
  ) async {
    await tester.pumpWidget(_host(
      RouteWeatherState(
        report: _report(
          alertMessage: 'In 5 km kommt Starkregen auf: Starkregen',
          alertSeverity: StormSeverity.danger,
        ),
      ),
    ));

    await tester.tap(find.text('In 5 km kommt Starkregen auf: Starkregen'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Keine Schutz-POIs'),
      findsOneWidget,
    );
  });
}

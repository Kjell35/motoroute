import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/weather/route_weather_providers.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepository extends Mock implements RouteWeatherRepository {}

RouteWeatherReport reportFromJson(Map<String, dynamic> json) =>
    RouteWeatherReport.fromJson(json);

void main() {
  group('RouteWeatherReport.fromJson', () {
    test('parst Backend-Antwort mit Alert + Shelters', () {
      final json = {
        'isEnabled': true,
        'segments': [
          {
            'distanceFromStartM': 0,
            'time': '2026-09-18T10:00:00.000Z',
            'tempC': 18.5,
            'precipitationMmH': 0,
            'conditionCode': 800,
            'severity': 'none',
          },
          {
            'distanceFromStartM': 20000,
            'time': '2026-09-18T10:30:00.000Z',
            'tempC': 17,
            'precipitationMmH': 9,
            'windGustMs': 19,
            'conditionCode': 211,
            'severity': 'danger',
          },
        ],
        'alert': {
          'severity': 'danger',
          'kind': 'mixed',
          'message': 'In 20 km zieht Unwetter auf: Gewitter + Starkregen',
          'distanceFromStartM': 20000,
        },
        'shelters': [
          {
            'id': 'h1',
            'name': 'Bikerhotel Adler',
            'category': 'MOTO_HOTEL',
            'lat': 48.1,
            'lng': 11.2,
            'distanceFromRouteM': 800,
          },
        ],
      };

      final report = reportFromJson(json);
      expect(report.isEnabled, isTrue);
      expect(report.segments, hasLength(2));
      expect(report.hasAlert, isTrue);
      expect(report.alertSeverity, StormSeverity.danger);
      expect(report.alertMessage, contains('20 km'));
      // destinationSegment = letztes Segment (Ziel).
      expect(report.destinationSegment!.conditionCode, 211);
      expect(report.destinationSegment!.isStorm, isTrue);
      expect(report.shelters, hasLength(1));
      expect(report.shelters.first.categoryLabel, 'Motorradhotel');
    });

    test('ohne Alert: hasAlert false, destination = letztes Segment', () {
      final report = reportFromJson({
        'isEnabled': true,
        'segments': [
          {
            'distanceFromStartM': 0,
            'time': '2026-09-18T10:00:00.000Z',
            'tempC': 21,
            'precipitationMmH': 0,
            'conditionCode': 800,
            'severity': 'none',
          },
        ],
        'alert': null,
        'shelters': [],
      });
      expect(report.hasAlert, isFalse);
      expect(report.destinationSegment!.tempC, 21);
      expect(report.shelters, isEmpty);
    });

    test('Feature deaktiviert (isEnabled=false) und leere Segmente', () {
      final report = reportFromJson({
        'isEnabled': false,
        'segments': [],
        'alert': null,
        'shelters': [],
      });
      expect(report.isEnabled, isFalse);
      expect(report.destinationSegment, isNull);
      expect(report.hasAlert, isFalse);
    });
  });

  group('RouteWeatherController', () {
    late _MockRepository repo;

    setUp(() {
      repo = _MockRepository();
      registerFallbackValue(<List<double>>[]);
    });

    ProviderContainer containerWith(ControllerSeed seed) {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Repository-Override über den Provider-Familie-Trick: direkt
      // den Controller mit Mock bauen und State setzen.
      final controller = seed(repo);
      final provider = StateNotifierProvider<RouteWeatherController,
          RouteWeatherState>((_) => controller);
      // Trigger Start über den Container (liest/initialisiert).
      container.read(provider);
      return container;
    }

    test('lädt Report und setzt State', () async {
      final json = {
        'isEnabled': true,
        'segments': [
          {
            'distanceFromStartM': 0,
            'time': '2026-09-18T10:00:00.000Z',
            'tempC': 20,
            'precipitationMmH': 0,
            'conditionCode': 800,
            'severity': 'none',
          },
        ],
        'alert': null,
        'shelters': [],
      };
      when(() => repo.fetchForRoute(
            geometry: any(named: 'geometry'),
            durationSeconds: any(named: 'durationSeconds'),
          )).thenAnswer((_) async => reportFromJson(json));

      final container = ProviderContainer(overrides: [
        routeWeatherRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);

      final controller = container.read(routeWeatherControllerProvider.notifier);
      controller.startForRoute(
        geometry: const [
          [11, 48],
          [12, 48],
        ],
        durationSeconds: 3600,
      );
      await Future<void>.delayed(Duration.zero);

      final state = container.read(routeWeatherControllerProvider);
      expect(state.report, isNotNull);
      expect(state.report!.isEnabled, isTrue);
      expect(state.error, isNull);
    });

    test('Fehler degradiert: altes Report bleibt, Error gesetzt', () async {
      final ok = reportFromJson({
        'isEnabled': true,
        'segments': [
          {
            'distanceFromStartM': 0,
            'time': '2026-09-18T10:00:00.000Z',
            'tempC': 20,
            'precipitationMmH': 0,
            'conditionCode': 800,
            'severity': 'none',
          },
        ],
        'alert': null,
        'shelters': [],
      });
      when(() => repo.fetchForRoute(
            geometry: any(named: 'geometry'),
            durationSeconds: any(named: 'durationSeconds'),
          )).thenAnswer((_) async => ok);

      final container = ProviderContainer(overrides: [
        routeWeatherRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);
      final controller = container.read(routeWeatherControllerProvider.notifier);
      controller.startForRoute(
        geometry: const [
          [11, 48],
          [12, 48],
        ],
        durationSeconds: 3600,
      );
      await Future<void>.delayed(Duration.zero);
      expect(container.read(routeWeatherControllerProvider).report, isNotNull);

      // Danach Netzfehler -> altes Report muss bleiben.
      when(() => repo.fetchForRoute(
            geometry: any(named: 'geometry'),
            durationSeconds: any(named: 'durationSeconds'),
          )).thenThrow(Exception('down'));
      await controller.reloadForTest();

      final state = container.read(routeWeatherControllerProvider);
      expect(state.report, isNotNull, reason: 'altes Report bleibt sichtbar');
      expect(state.error, isNotNull);
    });
  });
}

typedef ControllerSeed = RouteWeatherController Function(
  _MockRepository repo,
);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/features/navigation_session/speed_camera_warner.dart';
import 'package:motoroute_app/features/poi/poi_providers.dart';
import 'package:mocktail/mocktail.dart';

class _MockPoiRepository extends Mock implements PoiRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockPoiRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = _MockPoiRepository();
    container = ProviderContainer(
      overrides: [poiRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
  });

  test('lädt Kameras entlang der Route (nur SPEED_CAMERA-Kategorie)', () async {
    when(() => repo.fetchInBoundingBox(
          minLng: any(named: 'minLng'),
          minLat: any(named: 'minLat'),
          maxLng: any(named: 'maxLng'),
          maxLat: any(named: 'maxLat'),
          categories: any(named: 'categories'),
        )).thenAnswer((_) async => const []);

    final notifier = container.read(speedCameraWarnerProvider.notifier);
    await notifier.loadForRoute([
      [11.5, 48.1],
      [11.6, 48.2],
    ]);

    final captured = verify(() => repo.fetchInBoundingBox(
          minLng: captureAny(named: 'minLng'),
          minLat: captureAny(named: 'minLat'),
          maxLng: captureAny(named: 'maxLng'),
          maxLat: captureAny(named: 'maxLat'),
          categories: captureAny(named: 'categories'),
        )).captured;

    expect(captured[4], contains(PoiCategory.speedCamera));
    // Bounding-Box umschließt die Route (+ Puffer)
    expect(captured[0] as double, lessThan(11.5));
    expect(captured[2] as double, greaterThan(11.6));
  });

  test('warnt bei Annäherung (< 120 m) einmalig und räumt nach dem Passieren auf', () async {
    when(() => repo.fetchInBoundingBox(
          minLng: any(named: 'minLng'),
          minLat: any(named: 'minLat'),
          maxLng: any(named: 'maxLng'),
          maxLat: any(named: 'maxLat'),
          categories: any(named: 'categories'),
        )).thenAnswer((_) async => const []);

    final notifier = container.read(speedCameraWarnerProvider.notifier);
    // Direkt Kameras setzen (Repository-Mock liefert []). Kamera ~60 m
    // entfernt (0.0005° lat ≈ 55 m).
    notifier.state = notifier.state.copyWith(
      cameras: const [(lat: 48.0995, lng: 11.5)],
    );

    await notifier.onPosition(48.1, 11.5, speedMps: 30); // ~78 m entfernt, 108 km/h
    expect(container.read(speedCameraWarnerProvider).activeWarning, isNotNull);

    // Kein zweiter Alarm für dieselbe Kamera.
    await notifier.onPosition(48.0998, 11.5001, speedMps: 30);
    final same = container.read(speedCameraWarnerProvider);
    expect(same.warnedIndices.length, 1);

    // Weit weg: Warnung wird aufgeräumt.
    await notifier.onPosition(48.2, 11.6, speedMps: 30);
    expect(container.read(speedCameraWarnerProvider).activeWarning, isNull);
  });

  test('keine Warnung ohne geladene Kameras (Datenfehler = still, kein Crash)', () async {
    final notifier = container.read(speedCameraWarnerProvider.notifier);
    await notifier.onPosition(48.1, 11.5);
    expect(container.read(speedCameraWarnerProvider).activeWarning, isNull);
  });
}

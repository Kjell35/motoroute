import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:motoroute_app/core/constants/route_enums.dart';
import 'package:motoroute_app/core/error/failure.dart';
import 'package:motoroute_app/features/routing/data/routing_repository_impl.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart';

class _MockDio extends Mock implements Dio {}

// Bekannte Punkte als (lat, lng). Der Polyline6-String wird im Test mit
// Faktor 1e6 erzeugt, damit der Decoder gegen eine bekannte Eingabe läuft.
const _knownPoints = <List<double>>[
  [38.5, -120.2],
  [40.7, -120.95],
  [43.252, -126.453],
];

String _encodePolyline6(List<List<double>> latLng) {
  final out = StringBuffer();
  var prevLat = 0;
  var prevLng = 0;

  void encodeValue(int delta) {
    var v = delta < 0 ? ~(delta << 1) : (delta << 1);
    while (v >= 0x20) {
      out.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    out.writeCharCode(v + 63);
  }

  for (final p in latLng) {
    final lat = (p[0] * 1e6).round();
    final lng = (p[1] * 1e6).round();
    encodeValue(lat - prevLat);
    encodeValue(lng - prevLng);
    prevLat = lat;
    prevLng = lng;
  }
  return out.toString();
}

final _polyline6Example = _encodePolyline6(_knownPoints);

void main() {
  late _MockDio dio;
  late RoutingRepositoryImpl repository;

  final waypoints = [
    const Waypoint(lat: 48.1351, lng: 11.5820, label: 'München'),
    const Waypoint(lat: 47.4210, lng: 11.8757, label: 'Garmisch-Partenkirchen'),
  ];
  const preference = RoutePreference(
    style: RouteStyle.extraCurvy,
    vehicleType: VehicleType.motorcycle,
    avoid: {AvoidOption.highway},
  );

  setUp(() {
    dio = _MockDio();
    repository = RoutingRepositoryImpl(dio);
  });

  Map<String, dynamic> backendRoute() => {
        'candidates': [
          {
            'distance_m': 95000,
            'duration_s': 5400,
            'geometry_polyline6': _polyline6Example,
            'curve_score': 6.5,
            'segments': [
              {'instruction': 'Links abbiegen', 'distance_m': 500, 'duration_s': 60},
            ],
          },
        ],
      };

  test('elevation_gain_meters wird geparst, fehlt es, bleibt es null', () async {
    when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/api/v1/route'),
        statusCode: 200,
        data: {
          'candidates': [
            {
              'distance_m': 95000,
              'duration_s': 5400,
              'geometry_polyline6': _polyline6Example,
              'segments': <dynamic>[],
              'elevation_gain_meters': 1234,
            },
          ],
        },
      ),
    );
    final withHeights = await repository.createRoute(waypoints: waypoints, preference: preference);
    withHeights.fold(
      (failure) => fail('Erwartete Right, bekam Left: $failure'),
      (route) => expect(route.elevationGainMeters, 1234),
    );

    when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/api/v1/route'),
        statusCode: 200,
        data: backendRoute(),
      ),
    );
    final withoutHeights =
        await repository.createRoute(waypoints: waypoints, preference: preference);
    withoutHeights.fold(
      (failure) => fail('Erwartete Right, bekam Left: $failure'),
      (route) => expect(route.elevationGainMeters, isNull),
    );
  });

  test('POST /api/v1/route sendet snake_case-Payload und mappt die Antwort', () async {
    when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/api/v1/route'),
        statusCode: 200,
        data: backendRoute(),
      ),
    );

    final result = await repository.createRoute(waypoints: waypoints, preference: preference);

    final captured = verify(() => dio.post(captureAny(), data: captureAny(named: 'data')))
        .captured;
    expect(captured[0], '/api/v1/route');
    final body = captured[1] as Map<String, dynamic>;
    expect(body['waypoints'], [
      {'lat': 48.1351, 'lon': 11.5820},
      {'lat': 47.4210, 'lon': 11.8757},
    ]);
    expect(body['preferences'], {
      'vehicle': 'motorcycle',
      'ride_style': 'extra_curvy',
      'avoid': ['highway'],
    });

    result.fold(
      (failure) => fail('Erwartete Right, bekam Left: $failure'),
      (route) {
        expect(route.distanceMeters, 95000);
        expect(route.durationSeconds, 5400);
        expect(route.preference.style, RouteStyle.extraCurvy);
        expect(route.waypoints, waypoints);
        expect(route.id, isNotEmpty);
        expect(route.segments.single.instruction, 'Links abbiegen');
        expect(route.segments.single.distanceMeters, 500);
        expect(route.geometry.first[0], closeTo(-120.2, 1e-9));
        expect(route.geometry.first[1], closeTo(38.5, 1e-9));
        expect(route.geometry.length, 3);
      },
    );
  });

  test('gibt RoutingFailure zurück, wenn keine Kandidaten geliefert werden', () async {
    when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/api/v1/route'),
        statusCode: 200,
        data: {'candidates': <dynamic>[]},
      ),
    );

    final result = await repository.createRoute(waypoints: waypoints, preference: preference);

    result.fold(
      (failure) => expect(failure, isA<RoutingFailure>()),
      (_) => fail('Erwartete Left, bekam Right'),
    );
  });

  test('übernimmt die Backend-Fehlermeldung aus detail.message', () async {
    when(() => dio.post(any(), data: any(named: 'data'))).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/api/v1/route'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/api/v1/route'),
          statusCode: 503,
          data: {
            'detail': {'code': 'ROUTING_UNAVAILABLE', 'message': 'Routing ist gerade nicht verfügbar.'},
          },
        ),
      ),
    );

    final result = await repository.createRoute(waypoints: waypoints, preference: preference);

    result.fold(
      (failure) {
        expect(failure, isA<RoutingFailure>());
        expect(failure.message, 'Routing ist gerade nicht verfügbar.');
      },
      (_) => fail('Erwartete Left, bekam Right'),
    );
  });

  test('gibt NetworkFailure zurück, wenn keine Verbindung besteht', () async {
    when(() => dio.post(any(), data: any(named: 'data'))).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/api/v1/route'),
        type: DioExceptionType.connectionError,
      ),
    );

    final result = await repository.createRoute(waypoints: waypoints, preference: preference);

    result.fold(
      (failure) => expect(failure, isA<NetworkFailure>()),
      (_) => fail('Erwartete Left, bekam Right'),
    );
  });

  test('POST /api/v1/roundtrips sendet target_distance_km und direction', () async {
    when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/api/v1/roundtrips'),
        statusCode: 200,
        data: backendRoute(),
      ),
    );

    final result = await repository.createRoundTrip(
      start: const Waypoint(lat: 48.1351, lng: 11.5820),
      targetDistanceKm: 120,
      style: RouteStyle.curvy,
      vehicleType: VehicleType.motorcycle,
      direction: 'NORTH',
    );

    final captured = verify(() => dio.post(captureAny(), data: captureAny(named: 'data')))
        .captured;
    expect(captured[0], '/api/v1/roundtrips');
    final body = captured[1] as Map<String, dynamic>;
    expect(body['start'], {'lat': 48.1351, 'lon': 11.5820});
    expect(body['target_distance_km'], 120);
    expect(body['direction'], 'NORTH');
    expect(body['preferences']['ride_style'], 'curvy');
    expect(result.isRight(), true);
  });

  group('decodePolyline6', () {
    test('dekodiert das Valhalla-Beispiel zu [lng, lat]-Paaren', () {
      final points = decodePolyline6(_polyline6Example);
      expect(points.length, _knownPoints.length);
      for (var i = 0; i < _knownPoints.length; i++) {
        // Ausgabe ist [lng, lat].
        expect(points[i][0], closeTo(_knownPoints[i][1], 1e-6));
        expect(points[i][1], closeTo(_knownPoints[i][0], 1e-6));
      }
    });

    test('wirft FormatException bei abgeschnittenem Input', () {
      // Ein einzelnes Continuation-Zeichen ohne Abschluss.
      expect(() => decodePolyline6('`'), throwsFormatException);
    });
  });
}

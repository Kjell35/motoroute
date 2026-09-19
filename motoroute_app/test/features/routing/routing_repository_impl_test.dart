import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:motoroute_app/core/constants/route_enums.dart';
import 'package:motoroute_app/core/error/failure.dart';
import 'package:motoroute_app/features/routing/data/routing_repository_impl.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart';

class _MockDio extends Mock implements Dio {}

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

  test('gibt eine NavigationRoute zurück, wenn das Backend erfolgreich antwortet', () async {
    when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/v1/routes'),
        statusCode: 201,
        data: {
          'id': 'route-1',
          'geometry': [
            [11.582, 48.1351],
            [11.8757, 47.421],
          ],
          'distanceMeters': 95000,
          'durationSeconds': 5400,
          'segments': [
            {'instruction': 'Links abbiegen', 'distanceMeters': 500, 'durationSeconds': 60},
          ],
        },
      ),
    );

    final result = await repository.createRoute(waypoints: waypoints, preference: preference);

    expect(result.isRight(), true);
    result.fold(
      (failure) => fail('Erwartete Right, bekam Left: $failure'),
      (route) {
        expect(route.id, 'route-1');
        expect(route.distanceMeters, 95000);
        expect(route.preference.style, RouteStyle.extraCurvy);
      },
    );
  });

  test('gibt NetworkFailure zurück, wenn keine Verbindung besteht', () async {
    when(() => dio.post(any(), data: any(named: 'data'))).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/v1/routes'),
        type: DioExceptionType.connectionError,
      ),
    );

    final result = await repository.createRoute(waypoints: waypoints, preference: preference);

    expect(result.isLeft(), true);
    result.fold(
      (failure) => expect(failure, isA<NetworkFailure>()),
      (_) => fail('Erwartete Left, bekam Right'),
    );
  });
}

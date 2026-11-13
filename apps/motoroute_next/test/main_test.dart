import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:motoroute_app/core/theme/app_theme.dart';
import 'package:motoroute_next/main.dart';

class _RouteAdapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final body = requestStream == null
        ? ''
        : utf8.decode(await requestStream.expand((chunk) => chunk).toList());
    if (body.isNotEmpty) {
      requests.add(jsonDecode(body) as Map<String, dynamic>);
    }
    if (options.path.endsWith('/api/v1/geocode')) {
      return ResponseBody.fromString(
        jsonEncode([
          {
            'id': 'N:123',
            'label': 'Marienplatz',
            'detail': '80331 München',
            'lat': 48.1375,
            'lon': 11.5755,
          }
        ]),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        },
      );
    }
    if (options.path.endsWith('/api/v1/route')) {
      return ResponseBody.fromString(
        jsonEncode({
          'candidates': [
            {
              'distance_m': 12800,
              'duration_s': 950,
              'geometry_polyline6': '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
              'curve_score': 8.2,
            }
          ],
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        },
      );
    }
    return ResponseBody.fromString('{}', 404);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  // Sprache, Theme und Kartenstil werden persistiert gelesen - im
  // Widget-Test ohne Plattform-Plugin braucht es den In-Memory-Store.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('map home exposes route planning and real map attribution',
      (tester) async {
    await tester.pumpWidget(const MotoRouteNextApp(testMode: true));
    await tester.pump();

    expect(find.text('MOTOROUTE'), findsWidgets);
    expect(find.text('Tour planen'), findsOneWidget);
    expect(find.text('© OpenStreetMap · © CARTO'), findsOneWidget);
    expect(find.byType(MapLibreMap), findsNothing);
  });

  testWidgets('planner lets the rider search for a destination',
      (tester) async {
    final adapter = _RouteAdapter();
    await tester.pumpWidget(MotoRouteNextApp(
      testMode: true,
      dio: Dio(BaseOptions(baseUrl: 'https://unit.test'))
        ..httpClientAdapter = adapter,
    ));

    await tester.tap(find.text('Tour planen'));
    await tester.pumpAndSettle();

    expect(find.text('Deine Route'), findsOneWidget);
    expect(find.text('Standort wählen'), findsOneWidget);
    expect(find.text('Ziel suchen oder Karte antippen'), findsOneWidget);

    await tester.tap(find.text('Ziel suchen oder Karte antippen'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'München');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Marienplatz'), findsOneWidget);
  });

  testWidgets('route request uses the backend schema and renders its summary',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final adapter = _RouteAdapter();
    await tester.pumpWidget(MotoRouteNextApp(
      testMode: true,
      dio: Dio(BaseOptions(baseUrl: 'https://unit.test'))
        ..httpClientAdapter = adapter,
    ));

    await tester.tap(find.text('Tour planen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ziel suchen oder Karte antippen'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'München');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Marienplatz').first);
    await tester.tap(find.text('Marienplatz').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Startort suchen'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'München');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Marienplatz').last);
    await tester.tap(find.text('Marienplatz').last);
    await tester.pumpAndSettle();

    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Ziel'), findsOneWidget);
    expect(find.text('Marienplatz'), findsWidgets);
    await tester.ensureVisible(find.text('Route berechnen'));
    await tester.ensureVisible(find.text('Route berechnen'));
    await tester.tap(find.text('Route berechnen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();

    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single['waypoints'], hasLength(2));
    expect(adapter.requests.single['preferences'], {
      'vehicle': 'motorcycle',
      'ride_style': 'fast_and_curvy',
      'avoid': <String>[],
    });
    expect(find.textContaining('12.8 km'), findsOneWidget);
    expect(find.textContaining('Kurven 8.2/10'), findsOneWidget);
  });

  testWidgets('palette follows the active theme brightness', (tester) async {
    late MotoColors light;
    late MotoColors dark;
    // Ohne die Null-Dauer liefert Theme.of() waehrend der Standard-Animation
    // noch das alte Theme - der Test wuerde die Palette nicht pruefen.
    await tester.pumpWidget(MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: AppTheme.light,
      home: Builder(builder: (context) {
        light = context.moto;
        return const SizedBox();
      }),
    ));
    await tester.pumpWidget(MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: ThemeData(brightness: Brightness.dark),
      home: Builder(builder: (context) {
        dark = context.moto;
        return const SizedBox();
      }),
    ));

    // Hell modus darf nicht versehentlich die dunklen Panels behalten.
    expect(light.background, isNot(dark.background));
    expect(light.surface, isNot(dark.surface));
    expect(light.text, isNot(dark.text));
    expect(dark.background, MotoColors.dark.background);
  });

  test('vehicle and ride style values match the backend enums', () {
    expect(MapVehicle.motorcycle.apiValue, 'motorcycle');
    expect(MapVehicle.car.apiValue, 'car');
    expect(MapVehicle.bicycle.apiValue, 'bicycle');
    expect(RideStyleOption.fast.apiValue, 'fast');
    expect(RideStyleOption.fastAndCurvy.apiValue, 'fast_and_curvy');
    expect(RideStyleOption.curvy.apiValue, 'curvy');
    expect(RideStyleOption.extraCurvy.apiValue, 'extra_curvy');
  });

  testWidgets('main navigation opens the ported garage screen', (tester) async {
    await tester.pumpWidget(const MotoRouteNextApp(testMode: true));

    await tester.tap(find.text('Garage').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('wird im neuen App-Aufbau'), findsNothing);
    expect(find.text('Garage'), findsWidgets);
    // Finish the garage session restore timeout so its timer is not left
    // pending when the widget test disposes the app.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('tours and account destinations use the existing app flows',
      (tester) async {
    await tester.pumpWidget(const MotoRouteNextApp(testMode: true));

    await tester.tap(find.text('Touren'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('wird im neuen App-Aufbau'), findsNothing);
    expect(find.text('Touren'), findsWidgets);

    await tester.tap(find.text('Konto'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Konto'), findsWidgets);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:motoroute_app/core/constants/route_enums.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/core/theme/app_theme.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart';
import 'package:motoroute_app/features/routing/route_overview_screen.dart';

const _route = ComputedRoute(
  id: 'overview-1',
  waypoints: [
    Waypoint(lat: 47.561, lng: 10.746, label: 'Start'),
    Waypoint(lat: 47.6, lng: 10.8, label: 'Ziel'),
  ],
  preference: RoutePreference(
    style: RouteStyle.fast,
    vehicleType: VehicleType.motorcycle,
  ),
  geometry: [
    [10.746, 47.561],
    [10.8, 47.6],
  ],
  distanceMeters: 12000,
  durationSeconds: 1800,
  segments: [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Die Routenübersicht bleibt dunkel (eigene AppBar über bgBaseDark);
  /// im hellen Schema muss die Statusleiste trotzdem helle Symbole
  /// anfordern, sonst stehen dunkle Symbole auf dunklem Grund.
  testWidgets('Routenübersicht fordert im hellen Schema helle Symbole an',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(activeRouteProvider.notifier).state = _route;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        home: const RouteOverviewScreen(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find
          .descendant(
            of: find.byType(AppBar),
            matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          )
          .first,
    );
    expect(region.value.statusBarIconBrightness, Brightness.light);

    await tester.pumpWidget(const SizedBox());
  });
}

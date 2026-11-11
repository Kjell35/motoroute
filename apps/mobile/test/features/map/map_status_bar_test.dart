import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:motoroute_app/core/theme/app_theme.dart';
import 'package:motoroute_app/features/map/data/location_repository.dart';
import 'package:motoroute_app/features/map/data/map_style.dart';
import 'package:motoroute_app/features/map/presentation/map_screen.dart';

class _DeniedLocation extends LocationRepository {
  @override
  Future<bool> ensurePermission() async => false;
}

Widget _app() => ProviderScope(
      overrides: [
        locationRepositoryProvider.overrideWithValue(_DeniedLocation()),
        // Fester Stil statt Asset-Laden: der Screen baut sofort, die
        // Statusleisten-Frage haengt nicht am Karten-Asset.
        mapStyleLoaderProvider.overrideWithValue((_) async => emptyMapStyle),
      ],
      child: const MaterialApp(home: MapScreen()),
    );

SystemUiOverlayStyle _statusBarStyle(WidgetTester tester) {
  final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
    find
        .descendant(
          of: find.byType(MapScreen),
          matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        )
        .first,
  );
  return region.value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Karte setzt die Statusleiste passend zum Kartenstil',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Standard-Kartenstil ist hell (Carto Positron): dunkle Symbole.
    expect(_statusBarStyle(tester), AppTheme.statusOverlayLight);

    final container = ProviderScope.containerOf(tester.element(find.byType(MapScreen)));
    await container.read(mapStyleChoiceProvider.notifier).set(MapStyleChoice.dark);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Dunkle Karte: helle Symbole.
    expect(_statusBarStyle(tester), AppTheme.statusOverlayDark);

    await tester.pumpWidget(const SizedBox());
  });
}

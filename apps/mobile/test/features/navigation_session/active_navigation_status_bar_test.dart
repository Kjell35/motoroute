import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:motoroute_app/core/theme/app_theme.dart';
import 'package:motoroute_app/features/map/data/map_style.dart';
import 'package:motoroute_app/features/navigation_session/active_navigation_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Navigationsscreen fordert helle Statusleisten-Symbole an',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        mapStyleLoaderProvider.overrideWithValue((_) async => emptyMapStyle),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const ActiveNavigationScreen(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find
          .descendant(
            of: find.byType(ActiveNavigationScreen),
            matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          )
          .first,
    );
    // Der Screen ist immer dunkel, also helle Symbole - auch im hellen Schema.
    expect(region.value, AppTheme.statusOverlayDark);
    expect(region.value.statusBarIconBrightness, Brightness.light);

    await tester.pumpWidget(const SizedBox());
  });
}

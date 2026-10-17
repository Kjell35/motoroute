import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'design/legacy/app_theme.dart';
import 'presentation/screens/map/map_screen.dart';
import 'presentation/screens/map_data/map_data_screen.dart';
import 'presentation/screens/onboarding/onboarding_screen.dart';
import 'presentation/screens/onboarding/welcome_screen.dart';
import 'presentation/screens/search/search_screen.dart';
import 'presentation/screens/route/route_planner_screen.dart';
import 'presentation/screens/route/route_scan_screen.dart';
import 'presentation/screens/shell/home_shell.dart';
import 'presentation/screens/splash/splash_screen.dart';

/// Root-Widget mit Router. Look & Start der v1.0.x-App: Splash → (erster
/// Start: Welcome → Onboarding) → Tab-Shell. '/', '/search', '/route',
/// '/map-data' und '/scan' bleiben als Einzelscreens erreichbar (pushed).
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeShell()),
      GoRoute(path: '/', builder: (_, __) => const MapScreen()),
      GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
      GoRoute(path: '/route', builder: (_, __) => const RoutePlannerScreen()),
      GoRoute(path: '/map-data', builder: (_, __) => const MapDataScreen()),
      GoRoute(path: '/scan', builder: (_, __) => const RouteScanScreen()),
    ],
  );
});

class MotoRouteApp extends ConsumerWidget {
  const MotoRouteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'MotoRoute',
      debugShowCheckedModeBanner: false,
      // Dark-first-Theme der v1.0.x-App (Phase 3) — der vertraute Look.
      theme: AppTheme.dark,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

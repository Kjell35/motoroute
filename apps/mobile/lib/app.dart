import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'design/tokens/mr_theme.dart';
import 'presentation/screens/map/map_screen.dart';
import 'presentation/screens/search/search_screen.dart';
import 'presentation/screens/route/route_planner_screen.dart';
import 'presentation/screens/map_data/map_data_screen.dart';
import 'presentation/screens/splash/splash_screen.dart';

/// Root-Widget mit Router (M0-Umfang: Splash → Map).
/// Weitere Screens folgen in M1+ (siehe docs/09-mvp-plan.md).
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/', builder: (_, __) => const MapScreen()),
      GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
      GoRoute(path: '/route', builder: (_, __) => const RoutePlannerScreen()),
      GoRoute(path: '/map-data', builder: (_, __) => const MapDataScreen()),
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
      theme: MrTheme.dark(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

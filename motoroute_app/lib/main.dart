import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart';
import 'package:motoroute_app/core/theme/app_theme.dart';
import 'package:motoroute_app/features/map/presentation/map_screen.dart';
import 'package:motoroute_app/features/navigation_session/active_navigation_screen.dart';
import 'package:motoroute_app/features/onboarding/onboarding_screen.dart';
import 'package:motoroute_app/features/onboarding/splash_screen.dart';
import 'package:motoroute_app/features/poi/poi_selection_screen.dart';
import 'package:motoroute_app/features/routing/route_overview_screen.dart';
import 'package:motoroute_app/features/routing/route_style_selection.dart';
import 'package:motoroute_app/features/search/search_screen.dart';
import 'package:motoroute_app/features/chat/data/chat_repository.dart' show ConversationType;
import 'package:motoroute_app/features/chat/presentation/chat_hub_screen.dart';
import 'package:motoroute_app/features/chat/presentation/conversation_screen.dart';
import 'package:motoroute_app/features/chat/presentation/group_create_screen.dart';
import 'package:motoroute_app/features/chat/presentation/group_info_screen.dart';
import 'package:motoroute_app/features/chat/presentation/group_join_screen.dart';
import 'package:motoroute_app/features/chat/presentation/new_chat_screen.dart';
import 'package:motoroute_app/features/group_routes/presentation/group_route_create_screen.dart';
import 'package:motoroute_app/features/group_routes/presentation/group_route_list_screen.dart';
import 'package:motoroute_app/features/group_routes/presentation/group_route_planner_screen.dart';
import 'package:motoroute_app/features/group_routes/presentation/group_route_start_screen.dart';
import 'package:motoroute_app/features/group_rides/presentation/group_ride_screen.dart';
import 'package:motoroute_app/features/settings/settings_screen.dart';
import 'package:motoroute_app/features/waypoints/waypoint_management_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Persistierte Einstellungen + Server-Override laden, BEVOR das
  // erste Widget gebaut wird (Provider-Startwerte lesen die Werte;
  // ApiClient.baseUrl muss vor dem ersten Request korrekt sein).
  await initSessionSettings();
  runApp(const ProviderScope(child: MotoRouteApp()));
}

class MotoRouteApp extends StatelessWidget {
  const MotoRouteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MotoRoute',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      // Automatische System-Umschaltung - Dark bleibt aber der
      // Startpunkt der visuellen Identität (Phase 3 Teil B.1).
      themeMode: ThemeMode.dark,
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/map': (context) => const MapScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
        '/search': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
          return SearchScreen(addWaypointMode: args?['addWaypoint'] == true);
        },
        '/route-style': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
          return RouteStyleSelectionScreen(
            start: args?['start'] as Waypoint,
            destination: args?['destination'] as Waypoint,
          );
        },
        '/route-overview': (context) => const RouteOverviewScreen(),
        '/navigation': (context) => const ActiveNavigationScreen(),
        '/waypoints': (context) => const WaypointManagementScreen(),
        '/pois': (context) => const PoiSelectionScreen(),
        '/settings': (context) => const SettingsScreen(),
        // ----------------------------------------- Chat-Bereich (💬)
        '/chat': (context) => const ChatHubScreen(),
        '/chat/conversation': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
          final typeRaw = (args?['type'] ?? 'private') as String;
          final type = switch (typeRaw) {
            'public' => ConversationType.public,
            'group' => ConversationType.group,
            _ => ConversationType.private,
          };
          return ConversationScreen(
            conversationId: args?['conversationId'] as String,
            type: type,
            group: args?['group'] as Map<String, dynamic>?,
            title: (args?['title'] as String?) ?? 'Chat',
            subtitle: args?['subtitle'] as String?,
          );
        },
        '/chat/new': (context) => const NewChatScreen(),
        '/chat/group-create': (context) => const GroupCreateScreen(),
        '/chat/group-join': (context) => const GroupJoinScreen(),
        '/chat/group-info': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
          return GroupInfoScreen(
            conversationId: (args?['conversationId'] ?? '') as String,
            group: args?['group'] as Map<String, dynamic>?,
          );
        },
        // ----------------------- Gemeinsame Routenplanung (🏍️)
        '/chat/group-route-create': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
          return GroupRouteCreateScreen(groupId: args?['groupId'] as String);
        },
        '/chat/group-route-list': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
          return GroupRouteListScreen(groupId: args?['groupId'] as String);
        },
        '/chat/group-route-planner': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
          return GroupRoutePlannerScreen(routeId: args?['routeId'] as String);
        },
        '/chat/group-route-start': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
          return GroupRouteStartScreen(routeId: args?['routeId'] as String);
        },
        '/chat/group-ride': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
          return GroupRideScreen(routeId: args?['routeId'] as String);
        },
      },
    );
  }
}

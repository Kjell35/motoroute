import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/i18n/i18n.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/features/auth/welcome_screen.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart';
import 'package:motoroute_app/core/theme/app_theme.dart';
import 'package:motoroute_app/features/navigation_session/active_navigation_screen.dart';
import 'package:motoroute_app/features/onboarding/onboarding_screen.dart';
import 'package:motoroute_app/features/onboarding/splash_screen.dart';
import 'package:motoroute_app/features/settings/legal_screens.dart';
import 'package:motoroute_app/features/poi/poi_selection_screen.dart';
import 'package:motoroute_app/features/routing/presentation/start_point_selection_screen.dart';
import 'package:motoroute_app/features/routing/route_overview_screen.dart';
import 'package:motoroute_app/features/routing/route_style_selection.dart';
import 'package:motoroute_app/features/search/search_screen.dart';
import 'package:motoroute_app/features/shell/home_shell.dart';
import 'package:motoroute_app/features/chat/data/chat_repository.dart' show ConversationType;
import 'package:motoroute_app/core/network/server_keep_alive.dart';
import 'package:motoroute_app/features/chat/presentation/conversation_screen.dart';
import 'package:motoroute_app/features/chat/presentation/group_create_screen.dart';
import 'package:motoroute_app/features/chat/presentation/group_info_screen.dart';
import 'package:motoroute_app/features/chat/presentation/group_join_screen.dart';
import 'package:motoroute_app/features/chat/presentation/new_chat_screen.dart';
import 'package:motoroute_app/features/tour_diary/presentation/gpx_import_screen.dart';
import 'package:motoroute_app/features/tour_diary/presentation/tour_diary_screen.dart';
import 'package:motoroute_app/features/group_routes/presentation/group_route_create_screen.dart';
import 'package:motoroute_app/features/group_routes/presentation/group_route_list_screen.dart';
import 'package:motoroute_app/features/group_routes/presentation/group_route_planner_screen.dart';
import 'package:motoroute_app/features/group_routes/presentation/group_route_start_screen.dart';
import 'package:motoroute_app/features/group_rides/presentation/group_ride_screen.dart';
import 'package:motoroute_app/features/waypoints/waypoint_management_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Persistierte Einstellungen + Server-Override laden, BEVOR das
  // erste Widget gebaut wird (Provider-Startwerte lesen die Werte;
  // ApiClient.baseUrl muss vor dem ersten Request korrekt sein).
  await initSessionSettings();
  // Backend wachhalten, solange die App offen ist (GitHub-Cron wird
  // massiv verzögert - ohne In-App-Ping schläft der Free-Tier-Server
  // ein und jede erste Aktion läuft in "Verbindung prüfen").
  ServerKeepAlive.instance.start();
  runApp(const MotoRouteApp());
}

class MotoRouteApp extends StatelessWidget {
  const MotoRouteApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ProviderScope GEHÖRT zur App (nicht zu main): Damit starten auch
    // Widget-Tests, die MotoRouteApp direkt pumpen, in einem Scope.
    return const ProviderScope(child: _MotoRouteAppBody());
  }
}

class _MotoRouteAppBody extends ConsumerWidget {
  const _MotoRouteAppBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Sprachwahl (DE/EN): aus den Einstellungen, geräteweit persistiert.
    final language = ref.watch(languageControllerProvider);
    final i18n = I18n(language);
    return MaterialApp(
      title: 'MotoRoute',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      // Automatische System-Umschaltung - Dark bleibt aber der
      // Startpunkt der visuellen Identität (Phase 3 Teil B.1).
      themeMode: ThemeMode.dark,
      // Sprachwahl: locale steuert auch die Material-Systemtexte
      // (Auswahlmenüs, Barrierefreiheit), der eigene Katalog die UI.
      locale: i18n.locale,
      supportedLocales: const [Locale('de'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      initialRoute: '/',
      routes: {
        // Splash entscheidet: Willkommen/Login, Onboarding oder Shell.
        '/': (context) => const SplashScreen(),
        '/home': (context) => const HomeShell(),
        '/welcome': (context) => const WelcomeScreen(),
        // Tab-Aliase (Deep-Links aus Nicht-Shell-Kontexten): Shell mit
        // dem jeweiligen Start-Tab.
        '/map': (context) => const HomeShell(initialTab: 0),
        '/tours': (context) => const HomeShell(initialTab: 1),
        '/chat': (context) => const HomeShell(initialTab: 2),
        '/settings': (context) => const HomeShell(initialTab: 3),
        '/onboarding': (context) => const OnboardingScreen(),
        // Recht & Info (aus den Einstellungen erreichbar).
        '/privacy': (context) => const PrivacyScreen(),
        '/imprint': (context) => const ImprintScreen(),
        '/about': (context) => const AboutScreen(),
        '/search': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
          return SearchScreen(
            addWaypointMode: args?['addWaypoint'] == true,
            returnResult: args?['returnResult'] == true,
          );
        },
        '/route-start': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
          return StartPointSelectionScreen(
            destination: args?['destination'] as Waypoint,
          );
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
        // --------------------------- Tour-Tagebuch (🏍️ Tagebuch)
        '/tour-detail': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as int?;
          return TourDetailScreen(tourId: args ?? 0);
        },
        '/tour-import': (context) => const GpxImportScreen(),
        '/tour-diary': (context) => const TourDiaryScreen(),
        // ----------------------------------------- Chat-Bereich (💬)
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

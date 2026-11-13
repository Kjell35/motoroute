import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/network/api_client.dart';
import 'package:motoroute_app/core/i18n/i18n.dart';
import 'package:motoroute_app/core/theme/app_theme.dart';
import 'package:motoroute_app/features/map/data/map_style.dart';
import 'package:motoroute_app/features/settings/theme_mode.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/features/auth/auth_providers.dart';
import 'package:motoroute_app/features/auth/welcome_screen.dart';
import 'package:motoroute_app/features/badges/presentation/badges_screen.dart';
import 'package:motoroute_app/features/chat/data/chat_repository.dart'
    show ConversationType;
import 'package:motoroute_app/features/chat/presentation/chat_hub_screen.dart';
import 'package:motoroute_app/features/chat/presentation/conversation_screen.dart';
import 'package:motoroute_app/features/navigation_session/active_navigation_screen.dart';
import 'package:motoroute_app/features/chat/presentation/group_create_screen.dart';
import 'package:motoroute_app/features/chat/presentation/group_info_screen.dart';
import 'package:motoroute_app/features/chat/presentation/group_join_screen.dart';
import 'package:motoroute_app/features/chat/presentation/new_chat_screen.dart';
import 'package:motoroute_app/features/garage/garage_screen.dart';
import 'package:motoroute_app/features/group_routes/presentation/group_route_create_screen.dart';
import 'package:motoroute_app/features/group_routes/presentation/group_route_list_screen.dart';
import 'package:motoroute_app/features/group_routes/presentation/group_route_planner_screen.dart';
import 'package:motoroute_app/features/group_routes/presentation/group_route_start_screen.dart';
import 'package:motoroute_app/features/group_rides/presentation/group_ride_screen.dart';
import 'package:motoroute_app/features/marketplace/marketplace_screen.dart';
import 'package:motoroute_app/features/pairing/presentation/route_scan_screen.dart';
import 'package:motoroute_app/features/poi/poi_selection_screen.dart';
import 'package:motoroute_app/features/ride_history/presentation/ride_stats_screen.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart'
    show Waypoint;
import 'package:motoroute_app/features/routing/presentation/roundtrip_planner_screen.dart';
import 'package:motoroute_app/features/routing/presentation/start_point_selection_screen.dart';
import 'package:motoroute_app/features/routing/route_overview_screen.dart';
import 'package:motoroute_app/features/routing/route_style_selection.dart';
import 'package:motoroute_app/features/search/search_screen.dart';
import 'package:motoroute_app/features/settings/legal_screens.dart';
import 'package:motoroute_app/features/settings/settings_screen.dart';
import 'package:motoroute_app/features/tour_diary/presentation/gpx_import_screen.dart';
import 'package:motoroute_app/features/tour_diary/presentation/tour_diary_screen.dart';
import 'package:motoroute_app/features/waypoints/waypoint_management_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF101419),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const MotoRouteNextApp());
}

/// Farb-Tokens des Neuaufbaus: im Dunkelmodus der gewohnte MotoRoute-Look,
/// im Hellmodus die Werte des Design-Systems aus `AppTheme.light`. Dadurch
/// folgen Kartenpanels, Community und Bedienelemente dem Theme-Schalter.
class MotoColors {
  const MotoColors({
    required this.background,
    required this.surface,
    required this.raised,
    required this.border,
    required this.text,
    required this.muted,
    required this.orange,
    required this.teal,
  });

  static const dark = MotoColors(
    background: Color(0xFF101419),
    surface: Color(0xFF191F25),
    raised: Color(0xFF232B33),
    border: Color(0xFF303A44),
    text: Color(0xFFF3F5F6),
    muted: Color(0xFFA3ADB6),
    orange: Color(0xFFFF6A2B),
    teal: Color(0xFF42D5C2),
  );

  /// Leitet die hellen Tokens aus dem aktiven Design-System ab, statt eine
  /// zweite feste Palette zu pflegen.
  static MotoColors of(BuildContext context) {
    final theme = Theme.of(context);
    if (theme.brightness == Brightness.dark) return dark;
    final scheme = theme.colorScheme;
    return MotoColors(
      background: theme.scaffoldBackgroundColor,
      surface: scheme.surface,
      raised: scheme.surfaceContainerHighest,
      border: scheme.outlineVariant,
      text: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      orange: scheme.primary,
      teal: scheme.secondary,
    );
  }

  final Color background;
  final Color surface;
  final Color raised;
  final Color border;
  final Color text;
  final Color muted;
  final Color orange;
  final Color teal;
}

extension MotoColorsContext on BuildContext {
  MotoColors get moto => MotoColors.of(this);
}

class MotoRouteNextApp extends StatelessWidget {
  const MotoRouteNextApp({super.key, this.dio, this.testMode = false});

  final Dio? dio;
  final bool testMode;

  @override
  Widget build(BuildContext context) => ProviderScope(
        child: _MotoRouteNextAppBody(dio: dio, testMode: testMode),
      );
}

/// Sprache und Theme werden aus Riverpod gelesen - dieser Teil muss deshalb
/// INNERHALB des ProviderScope liegen.
class _MotoRouteNextAppBody extends ConsumerWidget {
  const _MotoRouteNextAppBody({this.dio, this.testMode = false});

  final Dio? dio;
  final bool testMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Sprache und Hell/Dunkel kommen aus denselben Providern wie in den
    // Einstellungen. Ohne diese Verdrahtung waren beide Schalter im
    // Neuaufbau wirkungslos.
    final language = ref.watch(languageControllerProvider);
    final i18n = I18n(language);
    final themeMode = ref.watch(themeModeControllerProvider).flutterMode;
    final scheme = ColorScheme.fromSeed(
      seedColor: MotoColors.dark.orange,
      brightness: Brightness.dark,
      surface: MotoColors.dark.surface,
    );
    return MaterialApp(
      title: 'MotoRoute',
      debugShowCheckedModeBanner: false,
      // Hell: Design-System der App; Dunkel: der eigene MotoRoute-Next-Look.
      theme: AppTheme.light,
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: MotoColors.dark.background,
        appBarTheme: AppBarTheme(
          backgroundColor: MotoColors.dark.background,
          foregroundColor: MotoColors.dark.text,
          elevation: 0,
          centerTitle: false,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: MotoColors.dark.surface,
          indicatorColor: MotoColors.dark.orange.withValues(alpha: .16),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 11,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: MotoColors.dark.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 17,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: MotoColors.dark.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: MotoColors.dark.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide:
                BorderSide(color: MotoColors.dark.orange, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
      themeMode: themeMode,
      locale: i18n.locale,
      supportedLocales: const [Locale('de'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: RebuildShell(dio: dio, testMode: testMode),
      onGenerateRoute: _buildAppRoute,
    );
  }
}

enum AppArea { map, tours, garage, community, account }

Route<dynamic>? _buildAppRoute(RouteSettings settings) {
  final rawArguments = settings.arguments;
  final args = rawArguments is Map<String, dynamic>
      ? rawArguments
      : const <String, dynamic>{};
  final Widget? page = switch (settings.name) {
    '/home' || '/' => const RebuildShell(),
    '/map' => const RebuildShell(initialArea: AppArea.map),
    '/tours' => const RebuildShell(initialArea: AppArea.tours),
    '/garage' => const RebuildShell(initialArea: AppArea.garage),
    '/chat' => const RebuildShell(initialArea: AppArea.community),
    '/settings' => const RebuildShell(initialArea: AppArea.account),
    '/welcome' => const WelcomeScreen(),
    '/badges' => const BadgesScreen(),
    '/privacy' => const PrivacyScreen(),
    '/imprint' => const ImprintScreen(),
    '/about' => const AboutScreen(),
    '/search' => SearchScreen(
        addWaypointMode: args['addWaypoint'] == true,
        returnResult: args['returnResult'] == true,
      ),
    '/route-start' => StartPointSelectionScreen(
        destination: args['destination'] as Waypoint,
      ),
    '/route-style' => RouteStyleSelectionScreen(
        start: args['start'] as Waypoint,
        destination: args['destination'] as Waypoint,
      ),
    '/route-overview' => const RouteOverviewScreen(),
    '/roundtrip' => const RoundTripPlannerScreen(),
    '/ride-stats' => const RideStatsScreen(),
    '/navigation' => const ActiveNavigationScreen(),
    '/waypoints' => const WaypointManagementScreen(),
    '/pois' => const PoiSelectionScreen(),
    '/tour-diary' => const TourDiaryScreen(),
    '/tour-import' => const GpxImportScreen(),
    '/tour-detail' => TourDetailScreen(tourId: rawArguments as int? ?? 0),
    '/chat/hub' => const _CommunityDestination(screen: ChatHubScreen()),
    '/marketplace' => const _CommunityDestination(screen: MarketplaceScreen()),
    '/chat/conversation' => ConversationScreen(
        conversationId: args['conversationId'] as String? ?? '',
        type: switch (args['type']) {
          'public' => ConversationType.public,
          'group' => ConversationType.group,
          _ => ConversationType.private,
        },
        group: args['group'] as Map<String, dynamic>?,
        title: args['title'] as String? ?? 'Chat',
        subtitle: args['subtitle'] as String?,
      ),
    '/chat/new' => const NewChatScreen(),
    '/chat/group-create' => const GroupCreateScreen(),
    '/chat/group-join' => const GroupJoinScreen(),
    '/chat/group-info' => GroupInfoScreen(
        conversationId: args['conversationId'] as String? ?? '',
        group: args['group'] as Map<String, dynamic>?,
      ),
    '/chat/group-route-create' => GroupRouteCreateScreen(
        groupId: args['groupId'] as String? ?? '',
      ),
    '/chat/group-route-list' => GroupRouteListScreen(
        groupId: args['groupId'] as String? ?? '',
      ),
    '/chat/group-route-planner' => GroupRoutePlannerScreen(
        routeId: args['routeId'] as String? ?? '',
      ),
    '/chat/group-route-start' => GroupRouteStartScreen(
        routeId: args['routeId'] as String? ?? '',
      ),
    '/chat/group-ride' => GroupRideScreen(
        routeId: args['routeId'] as String? ?? '',
      ),
    '/scan' => const RouteScanScreen(),
    _ => null,
  };
  if (page == null) return null;
  return MaterialPageRoute<void>(
    builder: (_) => page,
    settings: settings,
  );
}

class RebuildShell extends ConsumerStatefulWidget {
  const RebuildShell({
    super.key,
    this.dio,
    this.testMode = false,
    this.initialArea = AppArea.map,
  });

  final Dio? dio;
  final bool testMode;
  final AppArea initialArea;

  @override
  ConsumerState<RebuildShell> createState() => _RebuildShellState();
}

class _RebuildShellState extends ConsumerState<RebuildShell> {
  late AppArea _area = widget.initialArea;
  final Map<AppArea, Widget> _tabs = {};

  @override
  void initState() {
    super.initState();
    _tabs[_area] = _createTab(_area);
    ApiClient.bindAuth(
      refresher: () =>
          ref.read(authControllerProvider.notifier).refreshTokenNow(),
    );
    if (!widget.testMode) unawaited(_initializeSession());
  }

  Future<void> _initializeSession() async {
    try {
      await initSessionSettings().timeout(const Duration(seconds: 3));
    } catch (_) {
      // Preferences are optional; keep the app usable with defaults.
    }
    try {
      await ref.read(authControllerProvider.notifier).restore().timeout(
            const Duration(seconds: 8),
          );
    } catch (_) {
      // An unavailable auth service must not block route planning.
    }
  }

  Widget _createTab(AppArea area) {
    return switch (area) {
      AppArea.map => MapHomeScreen(dio: widget.dio, testMode: widget.testMode),
      AppArea.tours => const TourDiaryScreen(),
      AppArea.garage => const GarageScreen(),
      AppArea.community => const CommunityScreen(),
      AppArea.account => const SettingsScreen(),
    };
  }

  void _selectArea(AppArea area) {
    if (_area == area) return;
    setState(() {
      _area = area;
      _tabs.putIfAbsent(area, () => _createTab(area));
    });
  }

  static const _items = [
    (AppArea.map, 'Karte', Icons.explore_outlined, Icons.explore_rounded),
    (AppArea.tours, 'Touren', Icons.route_outlined, Icons.route_rounded),
    (AppArea.garage, 'Garage', Icons.two_wheeler_outlined, Icons.two_wheeler),
    (AppArea.community, 'Community', Icons.groups_outlined, Icons.groups),
    (AppArea.account, 'Konto', Icons.person_outline, Icons.person),
  ];

  @override
  Widget build(BuildContext context) {
    ref.watch(authChatBridgeProvider);
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final current = _items.indexWhere((item) => item.$1 == _area);
    final body = IndexedStack(
      index: current,
      children: [
        for (final item in _items) _tabs[item.$1] ?? const SizedBox.shrink(),
      ],
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: wide
            ? Row(
                children: [
                  NavigationRail(
                    backgroundColor: context.moto.surface,
                    selectedIndex: current,
                    onDestinationSelected: (index) =>
                        _selectArea(_items[index].$1),
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      for (final item in _items)
                        NavigationRailDestination(
                          icon: Icon(item.$3),
                          selectedIcon: Icon(item.$4),
                          label: Text(item.$2),
                        ),
                    ],
                  ),
                  VerticalDivider(width: 1, color: context.moto.border),
                  Expanded(child: body),
                ],
              )
            : body,
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: current,
              onDestinationSelected: (index) => _selectArea(_items[index].$1),
              destinations: [
                for (final item in _items)
                  NavigationDestination(
                    icon: Icon(item.$3),
                    selectedIcon: Icon(item.$4),
                    label: item.$2,
                  ),
              ],
            ),
    );
  }
}

class MapHomeScreen extends ConsumerStatefulWidget {
  const MapHomeScreen({super.key, this.dio, this.testMode = false});

  final Dio? dio;
  final bool testMode;

  @override
  ConsumerState<MapHomeScreen> createState() => _MapHomeScreenState();
}

class _MapHomeScreenState extends ConsumerState<MapHomeScreen> {
  static const _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://motoroute-api-8fi9.onrender.com',
  );

  late final Dio _dio = widget.dio ??
      Dio(BaseOptions(
        baseUrl: _apiBaseUrl,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12),
      ));
  MapLibreMapController? _mapController;
  String? _style;
  bool _styleLoading = true;
  bool _mapReady = false;
  bool _locationLoading = false;
  bool _routeLoading = false;
  String? _mapError;
  String? _searchError;
  String? _routeError;
  String? _routeSummary;
  Timer? _searchDebounce;
  List<PlaceResult> _results = [];
  List<LatLng> _routePoints = [];
  LatLng? _start;
  PlaceResult? _destination;
  MapVehicle _vehicle = MapVehicle.motorcycle;
  RideStyleOption _rideStyle = RideStyleOption.fastAndCurvy;
  final _queryController = TextEditingController();
  bool _plannerOpen = false;

  @override
  void initState() {
    super.initState();
    if (widget.testMode) {
      _style = '{"version":8,"sources":{},"layers":[]}';
      _styleLoading = false;
    } else {
      // Stil folgt der Einstellung "Karte: hell/dunkel" - auch wenn sie
      // geändert wird, während diese Karte im Hintergrund offen ist.
      ref.listenManual<MapStyleChoice>(mapStyleChoiceProvider, (prev, next) {
        if (prev != next) unawaited(_loadStyle());
      });
      unawaited(_loadStyle());
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _queryController.dispose();
    if (widget.dio == null) {
      _dio.close(force: true);
    }
    super.dispose();
  }

  Future<void> _loadStyle() async {
    // Geteilter Loader: respektiert die Stil-Wahl, den optionalen
    // CARTO_BASEMAP_KEY und liefert nie eine Exception.
    final style = await loadMapStyle(ref.read(mapStyleChoiceProvider));
    if (!mounted) return;
    setState(() {
      _style = style;
      _mapError = isPlaceholderStyle(style)
          ? 'Karte offline - der Kartenstil konnte nicht geladen werden.'
          : null;
      _styleLoading = false;
    });
  }

  void _onQueryChanged(String query, StateSetter setSheetState) {
    _searchDebounce?.cancel();
    if (query.trim().length < 2) {
      setSheetState(() => _results = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350),
        () => _searchPlaces(query.trim(), setSheetState));
  }

  Future<void> _searchPlaces(String query, StateSetter setSheetState) async {
    if (!mounted) return;
    setSheetState(() => _searchError = null);
    try {
      final response = await _dio.get<List<dynamic>>('/api/v1/geocode',
          queryParameters: {'q': query, 'limit': 8});
      final places = (response.data ?? const [])
          .whereType<Map>()
          .map((json) => PlaceResult.fromJson(Map<String, dynamic>.from(json)))
          .toList();
      if (!mounted || _queryController.text.trim() != query) {
        return;
      }
      setSheetState(() => _results = places);
    } on DioException catch (error) {
      if (!mounted || _queryController.text.trim() != query) {
        return;
      }
      setSheetState(() {
        _results = [];
        _searchError = error.response?.statusCode == 401
            ? 'Die Suche ist für diesen App-Build nicht freigeschaltet.'
            : 'Suche gerade nicht erreichbar. Bitte erneut versuchen.';
      });
    } catch (_) {
      if (mounted) {
        setSheetState(() =>
            _searchError = 'Suchergebnisse konnten nicht gelesen werden.');
      }
    }
  }

  Future<void> _useCurrentLocation() async {
    if (_locationLoading) {
      return;
    }
    setState(() {
      _locationLoading = true;
      _routeError = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const _LocationUnavailable(
            'Standortzugriff fehlt. Du kannst den Startort auch suchen.');
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const _LocationUnavailable(
            'Bitte aktiviere die Standortdienste.');
      }
      final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 12)));
      if (!mounted) {
        return;
      }
      setState(() {
        _start = LatLng(position.latitude, position.longitude);
        _locationLoading = false;
      });
      await _mapController
          ?.animateCamera(CameraUpdate.newLatLngZoom(_start!, 13));
    } on _LocationUnavailable catch (error) {
      if (mounted) {
        setState(() {
          _routeError = error.message;
          _locationLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _routeError =
              'Standort konnte nicht ermittelt werden. Suche einen Startort.';
          _locationLoading = false;
        });
      }
    }
  }

  Future<PlaceResult> _reverseGeocode(LatLng point) async {
    try {
      final response =
          await _dio.get<List<dynamic>>('/api/v1/reverse', queryParameters: {
        'lat': point.latitude,
        'lon': point.longitude,
        'limit': 1,
      });
      final places = response.data ?? const [];
      if (places.isNotEmpty && places.first is Map) {
        return PlaceResult.fromJson(
            Map<String, dynamic>.from(places.first as Map));
      }
    } catch (_) {}
    return PlaceResult(
        id: 'map:${point.latitude}:${point.longitude}',
        label:
            '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}',
        lat: point.latitude,
        lon: point.longitude);
  }

  Future<void> _chooseStart() async {
    final picked = await _showPlacePicker(title: 'Startpunkt wählen');
    if (picked == null || !mounted) return;
    setState(() {
      _start = LatLng(picked.lat, picked.lon);
      _routeError = null;
    });
  }

  Future<void> _chooseDestination() async {
    final picked = await _showPlacePicker(title: 'Ziel wählen');
    if (picked == null || !mounted) return;
    setState(() {
      _destination = picked;
      _routePoints = [];
      _routeSummary = null;
      _routeError = null;
    });
  }

  Future<PlaceResult?> _showPlacePicker({required String title}) async {
    _queryController.clear();
    _results = [];
    _searchError = null;
    return showModalBottomSheet<PlaceResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.moto.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(22, 14, 22,
                  MediaQuery.viewInsetsOf(sheetContext).bottom + 20),
              child: SizedBox(
                height: MediaQuery.sizeOf(sheetContext).height * .66,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                        child: Container(
                            width: 44,
                            height: 4,
                            decoration: BoxDecoration(
                                color: context.moto.muted,
                                borderRadius: BorderRadius.circular(99)))),
                    const SizedBox(height: 18),
                    Text(title,
                        style: const TextStyle(
                            fontSize: 23, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _queryController,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: (query) {
                        setSheetState(() {});
                        _onQueryChanged(query, setSheetState);
                      },
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: 'Ort, Adresse oder Treffpunkt',
                        suffixIcon: IconButton(
                            onPressed: () {
                              _queryController.clear();
                              setSheetState(() => _results = []);
                            },
                            icon: const Icon(Icons.close_rounded)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Column(
                        children: [
                          if (_searchError != null)
                            Padding(
                                padding:
                                    const EdgeInsets.only(top: 4, bottom: 6),
                                child: Text(_searchError!,
                                    style: const TextStyle(
                                        color: Color(0xFFFF958B),
                                        fontSize: 13))),
                          Expanded(
                              child: AnimatedBuilder(
                            animation: _queryController,
                            builder: (context, _) {
                              final query = _queryController.text.trim();
                              if (query.length < 2) {
                                return ListView(children: [
                                  ListTile(
                                    leading: Icon(
                                        Icons.my_location_rounded,
                                        color: context.moto.teal),
                                    title:
                                        const Text('Aktuellen Standort nutzen'),
                                    subtitle:
                                        const Text('Als Startpunkt setzen'),
                                    onTap: () async {
                                      Navigator.of(sheetContext).pop();
                                      await _useCurrentLocation();
                                    },
                                  ),
                                  Padding(
                                    padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                                    child: Text(
                                        'TIPP: SUCHEN ODER KARTE ANTIPPEN',
                                        style: TextStyle(
                                            color: context.moto.muted,
                                            fontSize: 10,
                                            letterSpacing: .8,
                                            fontWeight: FontWeight.w800)),
                                  ),
                                ]);
                              }
                              return ListView(children: [
                                if (_searchError == null && _results.isEmpty)
                                  const Padding(
                                      padding: EdgeInsets.all(20),
                                      child: Center(
                                          child: CircularProgressIndicator())),
                                for (final place in _results)
                                  ListTile(
                                    leading: Icon(
                                        Icons.location_on_outlined,
                                        color: context.moto.orange),
                                    title: Text(place.label),
                                    subtitle: place.detail == null
                                        ? null
                                        : Text(place.detail!),
                                    onTap: () =>
                                        Navigator.of(sheetContext).pop(place),
                                  ),
                              ]);
                            },
                          )),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _calculateRoute() async {
    final start = _start;
    final destination = _destination;
    if (start == null || destination == null || _routeLoading) return;
    setState(() {
      _routeLoading = true;
      _routeError = null;
      _routePoints = [];
      _routeSummary = null;
    });
    try {
      final response =
          await _dio.post<Map<String, dynamic>>('/api/v1/route', data: {
        'waypoints': [
          {'lat': start.latitude, 'lon': start.longitude},
          {'lat': destination.lat, 'lon': destination.lon},
        ],
        'preferences': {
          'vehicle': _vehicle.apiValue,
          'ride_style': _rideStyle.apiValue,
          'avoid': <String>[],
        },
      });
      final data = response.data ?? const <String, dynamic>{};
      final candidates = data['candidates'];
      if (candidates is! List ||
          candidates.isEmpty ||
          candidates.first is! Map) {
        throw const _RouteFailure(
            'Für diese Strecke wurde keine Route gefunden.');
      }
      final candidate = Map<String, dynamic>.from(candidates.first as Map);
      final encoded = candidate['geometry_polyline6'];
      final points = encoded is String ? _decodePolyline6(encoded) : <LatLng>[];
      if (points.length < 2) {
        throw const _RouteFailure(
            'Der Routingdienst hat keine Routengeometrie geliefert.');
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _routePoints = points;
        final km = ((candidate['distance_m'] as num?)?.toDouble() ?? 0) / 1000;
        final minutes =
            (((candidate['duration_s'] as num?)?.toInt() ?? 0) / 60).round();
        final score = (candidate['curve_score'] as num?)?.toDouble();
        _routeSummary =
            '${km.toStringAsFixed(1)} km · ${_formatMinutes(minutes)}'
            '${score == null ? '' : ' · Kurven ${score.toStringAsFixed(1)}/10'}';
        _routeLoading = false;
      });
      await _drawRoute(points);
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() {
        _routeError = error.response?.statusCode == 401
            ? 'Der Routingdienst ist für diesen App-Build nicht freigeschaltet.'
            : error.response?.statusCode == 503
                ? 'Routing gerade nicht verfügbar. Bitte später erneut versuchen.'
                : 'Route konnte nicht geladen werden. Prüfe die Verbindung.';
        _routeLoading = false;
      });
    } on _RouteFailure catch (error) {
      if (mounted) {
        setState(() {
          _routeError = error.message;
          _routeLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _routeError = 'Route konnte nicht verarbeitet werden.';
          _routeLoading = false;
        });
      }
    }
  }

  Future<void> _drawRoute(List<LatLng> points) async {
    if (widget.testMode) {
      setState(() => _mapReady = true);
      return;
    }
    final controller = _mapController;
    if (controller == null || points.isEmpty) {
      return;
    }
    final screenSize = MediaQuery.sizeOf(context);
    try {
      await controller.clearLines();
      await controller.clearSymbols();
      await controller.addLine(LineOptions(
        geometry: points,
        lineColor: '#FF6A2B',
        lineWidth: 6,
        lineOpacity: .95,
      ));
      if (points.length > 1) {
        await controller.addSymbol(SymbolOptions(
          geometry: points.first,
          iconImage: 'marker-15',
          iconSize: 1.4,
          iconColor: '#42D5C2',
        ));
        await controller.addSymbol(SymbolOptions(
          geometry: points.last,
          iconImage: 'marker-15',
          iconSize: 1.4,
          iconColor: '#FF6A2B',
        ));
        var south = points.first.latitude;
        var north = south;
        var west = points.first.longitude;
        var east = west;
        for (final point in points.skip(1)) {
          if (point.latitude < south) south = point.latitude;
          if (point.latitude > north) north = point.latitude;
          if (point.longitude < west) west = point.longitude;
          if (point.longitude > east) east = point.longitude;
        }
        if ((north - south).abs() < 0.0001) {
          south -= 0.0001;
          north += 0.0001;
        }
        if ((east - west).abs() < 0.0001) {
          west -= 0.0001;
          east += 0.0001;
        }
        final topInset = math.min(220.0, screenSize.height * .26);
        final bottomInset = _plannerOpen
            ? math.min(390.0, screenSize.height * .5)
            : math.min(125.0, screenSize.height * .16);
        await controller.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds(
                southwest: LatLng(south, west), northeast: LatLng(north, east)),
            left: 42,
            top: topInset,
            right: 42,
            bottom: bottomInset,
          ),
          duration: const Duration(milliseconds: 500),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _routeError =
            'Route berechnet, konnte aber nicht auf der Karte gezeichnet werden.');
      }
    }
  }

  List<LatLng> _decodePolyline6(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lon = 0;
    while (index < encoded.length) {
      final latitudeDelta =
          _decodePolylineValue(encoded, () => index, (value) => index = value);
      final longitudeDelta =
          _decodePolylineValue(encoded, () => index, (value) => index = value);
      lat += latitudeDelta;
      lon += longitudeDelta;
      points.add(LatLng(lat / 1e6, lon / 1e6));
    }
    return points;
  }

  int _decodePolylineValue(
      String encoded, int Function() getIndex, void Function(int) setIndex) {
    var result = 0;
    var shift = 0;
    while (true) {
      if (getIndex() >= encoded.length) {
        throw const FormatException('Polyline truncated');
      }
      final byte = encoded.codeUnitAt(getIndex()) - 63;
      setIndex(getIndex() + 1);
      result |= (byte & 0x1f) << shift;
      shift += 5;
      if (byte < 0x20) break;
      if (shift > 35) throw const FormatException('Invalid polyline value');
    }
    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
  }

  String _formatMinutes(int minutes) {
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    return hours == 0
        ? '$remaining min'
        : '$hours h ${remaining.toString().padLeft(2, '0')} min';
  }

  Future<void> _onMapTap(LatLng point) async {
    final picked = await _reverseGeocode(point);
    if (!mounted) return;
    setState(() {
      if (_start == null || (_start != null && _destination != null)) {
        _start = point;
        _destination = null;
        _routePoints = [];
        _routeSummary = null;
      } else {
        _destination = picked;
      }
      _plannerOpen = true;
    });
  }

  void _openPlanner() => setState(() => _plannerOpen = true);
  void _closePlanner() => setState(() => _plannerOpen = false);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_styleLoading)
          ColoredBox(
              color: context.moto.background,
              child: Center(child: CircularProgressIndicator()))
        else if (widget.testMode) ...[
          ColoredBox(color: context.moto.background),
        ] else if (_style != null)
          MapLibreMap(
            styleString: _style!,
            initialCameraPosition:
                const CameraPosition(target: LatLng(48.1351, 11.5820), zoom: 9),
            myLocationEnabled: false,
            compassEnabled: true,
            onMapCreated: (controller) {
              _mapController = controller;
              setState(() => _mapReady = true);
              if (_routePoints.isNotEmpty) unawaited(_drawRoute(_routePoints));
            },
            onMapClick: (_, point) => unawaited(_onMapTap(point)),
          )
        else
          ColoredBox(
              color: context.moto.background,
              child: Center(
                  child: Text(_mapError ?? 'Karte nicht verfügbar',
                      style: TextStyle(color: context.moto.muted)))),
        Positioned(
          top: 4,
          left: 18,
          right: 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BrandRow(onLayers: _toggleMapStyle),
              const SizedBox(height: 14),
              Material(
                color: context.moto.surface.withValues(alpha: .97),
                borderRadius: BorderRadius.circular(17),
                child: InkWell(
                  borderRadius: BorderRadius.circular(17),
                  onTap: _openPlanner,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    child: Row(children: [
                      Icon(Icons.search_rounded,
                          color: context.moto.orange),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(
                        _destination?.label ?? 'Wohin soll die Tour gehen?',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: _destination == null
                                ? context.moto.muted
                                : context.moto.text,
                            fontSize: 15),
                      )),
                      Icon(Icons.tune_rounded,
                          color: context.moto.muted, size: 20),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _VehicleSelector(
                value: _vehicle,
                onChanged: (value) => setState(() => _vehicle = value),
              ),
            ],
          ),
        ),
        if (_mapReady && !widget.testMode)
          Positioned(
            right: 18,
            bottom: _plannerOpen ? 368 : 100,
            child: Column(children: [
              _MapControl(
                  icon: Icons.my_location_rounded,
                  tooltip: 'Standort zentrieren',
                  loading: _locationLoading,
                  onTap: () async {
                    await _useCurrentLocation();
                    if (_start != null) {
                      await _mapController?.animateCamera(
                          CameraUpdate.newLatLngZoom(_start!, 14));
                    }
                  }),
              const SizedBox(height: 10),
              _MapControl(
                  icon: Icons.layers_outlined,
                  tooltip: 'Kartenstil wechseln',
                  onTap: _toggleMapStyle),
            ]),
          ),
        if (!_plannerOpen && !_styleLoading)
          Positioned(
            left: 18,
            right: 18,
            bottom: 22,
            child: _routeSummary == null
                ? FilledButton.icon(
                    onPressed: _openPlanner,
                    icon: const Icon(Icons.add_road_rounded),
                    label: const Text('Tour planen'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 60),
                      backgroundColor: context.moto.orange,
                      foregroundColor: const Color(0xFF20150F),
                    ),
                  )
                : _RouteSummaryCard(
                    summary: _routeSummary!,
                    onPlanAnother: () {
                      setState(() {
                        _destination = null;
                        _routePoints = [];
                        _routeSummary = null;
                        _plannerOpen = true;
                      });
                    }),
          ),
        const Positioned(left: 16, bottom: 6, child: _MapAttribution()),
        if (_plannerOpen) _buildPlannerSheet(),
        if (_routeError != null && !_plannerOpen)
          Positioned(
              left: 18,
              right: 18,
              bottom: 92,
              child: _InlineError(
                  message: _routeError!,
                  onClose: () => setState(() => _routeError = null))),
      ],
    );
  }

  Widget _buildPlannerSheet() => Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .72,
            ),
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                decoration: BoxDecoration(
                  color: context.moto.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black45,
                        blurRadius: 24,
                        offset: Offset(0, -6))
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      const Expanded(
                          child: Text('Deine Route',
                              style: TextStyle(
                                  fontSize: 21, fontWeight: FontWeight.w900))),
                      IconButton(
                          onPressed: _closePlanner,
                          icon: const Icon(Icons.close_rounded)),
                    ]),
                    const SizedBox(height: 8),
                    _RoutePlaceRow(
                        icon: Icons.radio_button_checked_rounded,
                        color: context.moto.teal,
                        title: 'Start',
                        value:
                            _start == null ? 'Standort wählen' : _startLabel(),
                        trailing: IconButton(
                            tooltip: 'Startort suchen',
                            onPressed: _chooseStart,
                            icon: const Icon(Icons.search_rounded)),
                        onTap: _chooseStart),
                    Padding(
                        padding: EdgeInsets.only(left: 22),
                        child: SizedBox(
                            height: 14,
                            child: VerticalDivider(
                                width: 1, color: context.moto.border))),
                    _RoutePlaceRow(
                        icon: Icons.location_on_rounded,
                        color: context.moto.orange,
                        title: 'Ziel',
                        value: _destination?.label ??
                            'Ziel suchen oder Karte antippen',
                        trailing: IconButton(
                            tooltip: 'Ziel suchen',
                            onPressed: _chooseDestination,
                            icon: const Icon(Icons.search_rounded)),
                        onTap: _chooseDestination),
                    const SizedBox(height: 14),
                    Text('FAHRSTIL',
                        style: TextStyle(
                            color: context.moto.muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .9)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final style in RideStyleOption.values)
                        ChoiceChip(
                            label: Text(style.label),
                            selected: style == _rideStyle,
                            onSelected: (_) =>
                                setState(() => _rideStyle = style),
                            selectedColor:
                                context.moto.orange.withValues(alpha: .2),
                            side: BorderSide(
                                color: style == _rideStyle
                                    ? context.moto.orange
                                    : context.moto.border)),
                    ]),
                    if (_routeError != null) ...[
                      const SizedBox(height: 12),
                      _InlineError(
                          message: _routeError!,
                          onClose: () => setState(() => _routeError = null)),
                    ],
                    if (_routeSummary != null) ...[
                      const SizedBox(height: 12),
                      Text(_routeSummary!,
                          style: TextStyle(
                              color: context.moto.teal,
                              fontWeight: FontWeight.w800)),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                        onPressed: _routeLoading ? null : _calculateRoute,
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 56),
                            backgroundColor: context.moto.orange,
                            foregroundColor: const Color(0xFF20150F)),
                        child: _routeLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : Text(_routePoints.isEmpty
                                ? 'Route berechnen'
                                : 'Route aktualisieren')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  String _startLabel() {
    final start = _start!;
    return '${start.latitude.toStringAsFixed(4)}, ${start.longitude.toStringAsFixed(4)}';
  }

  Future<void> _toggleMapStyle() async {
    // Wechselt jetzt die geteilte, persistierte Stil-Wahl statt nur den
    // lokalen String - sonst wären Karte und Einstellungen wieder getrennt.
    final current = ref.read(mapStyleChoiceProvider);
    try {
      await ref.read(mapStyleChoiceProvider.notifier).set(
            current == MapStyleChoice.dark
                ? MapStyleChoice.light
                : MapStyleChoice.dark,
          );
    } catch (_) {
      if (mounted) {
        setState(
            () => _routeError = 'Kartenstil konnte nicht gewechselt werden.');
      }
    }
  }
}

class PlaceResult {
  const PlaceResult(
      {required this.id,
      required this.label,
      required this.lat,
      required this.lon,
      this.detail});
  final String id;
  final String label;
  final String? detail;
  final double lat;
  final double lon;

  factory PlaceResult.fromJson(Map<String, dynamic> json) => PlaceResult(
        id: json['id'] as String? ?? 'place',
        label: json['label'] as String? ?? 'Unbenannter Ort',
        detail: json['detail'] as String?,
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
      );
}

enum MapVehicle { motorcycle, car, bicycle }

extension MapVehicleData on MapVehicle {
  String get label => switch (this) {
        MapVehicle.motorcycle => 'Motorrad',
        MapVehicle.car => 'Auto',
        MapVehicle.bicycle => 'Fahrrad',
      };
  String get apiValue => switch (this) {
        MapVehicle.motorcycle => 'motorcycle',
        MapVehicle.car => 'car',
        MapVehicle.bicycle => 'bicycle',
      };
  IconData get icon => switch (this) {
        MapVehicle.motorcycle => Icons.two_wheeler_rounded,
        MapVehicle.car => Icons.directions_car_outlined,
        MapVehicle.bicycle => Icons.pedal_bike_outlined,
      };
}

enum RideStyleOption { fast, fastAndCurvy, curvy, extraCurvy }

extension RideStyleData on RideStyleOption {
  String get label => switch (this) {
        RideStyleOption.fast => 'Schnell',
        RideStyleOption.fastAndCurvy => 'Schnell & kurvig',
        RideStyleOption.curvy => 'Kurvig',
        RideStyleOption.extraCurvy => 'Extra kurvig',
      };
  String get apiValue => switch (this) {
        RideStyleOption.fast => 'fast',
        RideStyleOption.fastAndCurvy => 'fast_and_curvy',
        RideStyleOption.curvy => 'curvy',
        RideStyleOption.extraCurvy => 'extra_curvy',
      };
}

class _MapControl extends StatelessWidget {
  const _MapControl(
      {required this.icon,
      required this.tooltip,
      required this.onTap,
      this.loading = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) => Material(
        color: context.moto.surface.withValues(alpha: .96),
        shape: const CircleBorder(),
        child: IconButton(
            tooltip: tooltip,
            onPressed: onTap,
            icon: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(icon, color: context.moto.text)),
      );
}

class _RoutePlaceRow extends StatelessWidget {
  const _RoutePlaceRow(
      {required this.icon,
      required this.color,
      required this.title,
      required this.value,
      required this.trailing,
      required this.onTap});
  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Expanded(
            child: InkWell(
                onTap: onTap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: context.moto.muted, fontSize: 11)),
                    const SizedBox(height: 3),
                    Text(value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                  ],
                ))),
        trailing,
      ]);
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onClose});
  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
            color: const Color(0xFF5D2926).withValues(alpha: .55),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: const Color(0xFF9C5148))),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFFF958B), size: 19),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: TextStyle(
                      color: context.moto.text, fontSize: 12, height: 1.3))),
          IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close, size: 17),
              visualDensity: VisualDensity.compact),
        ]),
      );
}

class _RouteSummaryCard extends StatelessWidget {
  const _RouteSummaryCard({required this.summary, required this.onPlanAnother});
  final String summary;
  final VoidCallback onPlanAnother;

  @override
  Widget build(BuildContext context) => Material(
        color: context.moto.surface,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(children: [
              Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                      color: context.moto.teal.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(13)),
                  child:
                      Icon(Icons.route_rounded, color: context.moto.teal)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('Route bereit',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(summary,
                        style: TextStyle(
                            color: context.moto.muted, fontSize: 12)),
                  ])),
              IconButton(
                  onPressed: onPlanAnother,
                  tooltip: 'Andere Route planen',
                  icon:
                      Icon(Icons.add_rounded, color: context.moto.orange)),
            ])),
      );
}

class _LocationUnavailable implements Exception {
  const _LocationUnavailable(this.message);
  final String message;
}

class _RouteFailure implements Exception {
  const _RouteFailure(this.message);
  final String message;
}

class _VehicleSelector extends StatelessWidget {
  const _VehicleSelector({required this.value, required this.onChanged});
  final MapVehicle value;
  final ValueChanged<MapVehicle> onChanged;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.moto.surface.withValues(alpha: .96),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.moto.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Wrap(
            spacing: 2,
            children: [
              for (final vehicle in MapVehicle.values)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onChanged(vehicle),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                    decoration: BoxDecoration(
                      color: value == vehicle
                          ? context.moto.orange.withValues(alpha: .15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(vehicle.icon,
                            size: 16,
                            color: value == vehicle
                                ? context.moto.orange
                                : context.moto.muted),
                        const SizedBox(width: 6),
                        Text(vehicle.label,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: value == vehicle
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                color: value == vehicle
                                    ? context.moto.text
                                    : context.moto.muted)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandRow extends StatelessWidget {
  const _BrandRow({required this.onLayers});

  /// Wechselt den Kartenstil - der Ebenen-Button im Kopf hatte vorher
  /// keinen Handler und reagierte auf keinen Tipp.
  final VoidCallback onLayers;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: context.moto.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.moto.border),
          ),
          child: Icon(
            Icons.two_wheeler_rounded,
            color: context.moto.orange,
            size: 24,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MOTOROUTE',
                style: TextStyle(
                  color: context.moto.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 1.7,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'FINDE DEINE LIEBLINGSSTRECKE',
                style: TextStyle(
                  color: context.moto.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 9,
                  letterSpacing: .7,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Kartenstil wechseln',
          onPressed: onLayers,
          style: IconButton.styleFrom(
            backgroundColor: context.moto.surface,
            foregroundColor: context.moto.text,
          ),
          icon: const Icon(Icons.layers_outlined),
        ),
      ],
    );
  }
}

class MapPlaceholderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1D2B30), Color(0xFF26332F), Color(0xFF171F25)],
        ).createShader(rect),
    );

    final green = Paint()
      ..color = const Color(0xFF385443).withValues(alpha: .55);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * .12, size.height * .48),
        width: size.width * .6,
        height: size.height * .28,
      ),
      green,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * .84, size.height * .6),
        width: size.width * .58,
        height: size.height * .24,
      ),
      green,
    );
    final river = Path()
      ..moveTo(size.width * .86, 0)
      ..cubicTo(
        size.width * .72,
        size.height * .22,
        size.width * .94,
        size.height * .32,
        size.width * .75,
        size.height * .51,
      )
      ..cubicTo(
        size.width * .57,
        size.height * .69,
        size.width * .82,
        size.height * .82,
        size.width * .65,
        size.height,
      );
    canvas.drawPath(
      river,
      Paint()
        ..color = const Color(0xFF294A59)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 28,
    );

    final roads = [
      _road(
          size,
          const [
            (-.08, .24),
            (.16, .31),
            (.43, .27),
            (.71, .36),
            (1.08, .28),
          ],
          8),
      _road(
          size,
          const [
            (-.05, .65),
            (.22, .53),
            (.42, .58),
            (.65, .49),
            (1.1, .61),
          ],
          13),
      _road(
          size,
          const [
            (.1, -.1),
            (.29, .18),
            (.34, .4),
            (.23, .63),
            (.4, 1.1),
          ],
          6),
      _road(
          size,
          const [
            (.58, -.1),
            (.51, .22),
            (.62, .38),
            (.55, .7),
            (.76, 1.1),
          ],
          7),
      _road(
          size,
          const [
            (-.1, .43),
            (.28, .37),
            (.52, .45),
            (.77, .39),
            (1.1, .48),
          ],
          4),
      _road(
          size,
          const [
            (.02, .83),
            (.31, .72),
            (.49, .79),
            (.8, .72),
            (1.1, .82),
          ],
          4),
    ];
    for (final road in roads) {
      final casePaint = Paint()
        ..color = const Color(0xFF11171A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = road.$2 + 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(road.$1, casePaint);
      canvas.drawPath(
        road.$1,
        Paint()
          ..color =
              road.$2 > 10 ? const Color(0xFF52615D) : const Color(0xFF69756E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = road.$2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    final route = Path()
      ..moveTo(size.width * .25, size.height * .72)
      ..cubicTo(
        size.width * .16,
        size.height * .6,
        size.width * .43,
        size.height * .55,
        size.width * .36,
        size.height * .43,
      )
      ..cubicTo(
        size.width * .29,
        size.height * .32,
        size.width * .5,
        size.height * .29,
        size.width * .54,
        size.height * .41,
      )
      ..cubicTo(
        size.width * .59,
        size.height * .53,
        size.width * .48,
        size.height * .63,
        size.width * .7,
        size.height * .69,
      );
    canvas.drawPath(
      route,
      Paint()
        ..color = MotoColors.dark.orange.withValues(alpha: .22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 15
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      route,
      Paint()
        ..color = MotoColors.dark.orange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    _marker(
      canvas,
      Offset(size.width * .25, size.height * .72),
      Colors.white,
      true,
    );
    _marker(
      canvas,
      Offset(size.width * .7, size.height * .69),
      MotoColors.dark.orange,
      false,
    );
  }

  (Path, double) _road(Size size, List<(double, double)> points, double width) {
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final point = Offset(
        size.width * points[i].$1,
        size.height * points[i].$2,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return (path, width);
  }

  void _marker(Canvas canvas, Offset center, Color color, bool start) {
    canvas.drawCircle(
      center,
      13,
      Paint()..color = color.withValues(alpha: .22),
    );
    canvas.drawCircle(center, 8, Paint()..color = MotoColors.dark.background);
    canvas.drawCircle(center, 5, Paint()..color = color);
    if (start) {
      canvas.drawCircle(
        center,
        2,
        Paint()..color = MotoColors.dark.background.withValues(alpha: .8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant MapPlaceholderPainter oldDelegate) => false;
}

class _MapAttribution extends StatelessWidget {
  const _MapAttribution();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: context.moto.background.withValues(alpha: .78),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Text(
            '© OpenStreetMap · © CARTO',
            style: TextStyle(color: context.moto.muted, fontSize: 9),
          ),
        ),
      );
}

class _CommunityDestination extends StatelessWidget {
  const _CommunityDestination({required this.screen});

  final Widget screen;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: screen,
        bottomNavigationBar: SafeArea(
          top: false,
          child: NavigationBar(
            selectedIndex: 3,
            onDestinationSelected: (index) {
              final area = switch (index) {
                0 => AppArea.map,
                1 => AppArea.tours,
                2 => AppArea.garage,
                3 => AppArea.community,
                _ => AppArea.account,
              };
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute<void>(
                  builder: (_) => RebuildShell(initialArea: area),
                ),
                (route) => false,
              );
            },
            destinations: [
              for (final item in _RebuildShellState._items)
                NavigationDestination(
                  icon: Icon(item.$3),
                  selectedIcon: Icon(item.$4),
                  label: item.$2,
                ),
            ],
          ),
        ),
      );
}

class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: context.moto.background,
        appBar: AppBar(title: const _CompactBrand()),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Community',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text('Chatte, entdecke Angebote und plane gemeinsame Touren.',
                style: TextStyle(color: context.moto.muted)),
            const SizedBox(height: 20),
            _CommunityEntry(
              icon: Icons.forum_outlined,
              title: 'Nachrichten & Gruppen',
              subtitle: 'Öffentlicher Chat, private Nachrichten und Gruppen',
              onTap: () => Navigator.of(context).pushNamed('/chat/hub'),
            ),
            const SizedBox(height: 12),
            _CommunityEntry(
              icon: Icons.storefront_outlined,
              title: 'Marktplatz',
              subtitle: 'Motorradteile und Zubehör entdecken',
              onTap: () => Navigator.of(context).pushNamed('/marketplace'),
            ),
            const SizedBox(height: 12),
            _CommunityEntry(
              icon: Icons.emoji_events_outlined,
              title: 'Abzeichen',
              subtitle: 'Deine Meilensteine und Erfolge',
              onTap: () => Navigator.of(context).pushNamed('/badges'),
            ),
          ],
        ),
      );
}

class _CommunityEntry extends StatelessWidget {
  const _CommunityEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        color: context.moto.surface,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          leading: Icon(icon, color: context.moto.orange, size: 28),
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
      );
}

class _CompactBrand extends StatelessWidget {
  const _CompactBrand();

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.two_wheeler_rounded, color: context.moto.orange, size: 24),
          SizedBox(width: 10),
          Text(
            'MOTOROUTE',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ],
      );
}

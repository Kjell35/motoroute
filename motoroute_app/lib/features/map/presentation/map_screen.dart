import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:motoroute_app/core/constants/route_enums.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';
import 'package:motoroute_app/features/chat/chat_providers.dart';
import 'package:motoroute_app/features/chat/data/chat_realtime.dart';
import 'package:motoroute_app/features/hazards/hazard_repository.dart';
import 'package:motoroute_app/features/hazards/presentation/hazard_report_sheet.dart';
import 'package:motoroute_app/features/map/data/location_repository.dart';
import 'package:motoroute_app/features/poi/biker_poi_sync.dart';
import 'package:motoroute_app/features/poi/poi_map_layer.dart';
import 'package:motoroute_app/features/poi/poi_providers.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart';
import 'package:motoroute_app/features/search/search_providers.dart';
import 'package:motoroute_app/features/traffic/traffic_providers.dart';

/// CARTO-API-Key (Basemap-Lizenz): Wird beim Build via
/// --dart-define=CARTO_BASEMAP_KEY=... eingesetzt und zur Laufzeit in
/// den gebündelten Stil eingesetzt (Platzhalter __CARTO_KEY__).
/// Kein Key im Repo, kein Key im App-Store-Listing - nur im Build.
const _cartoBasemapKey = String.fromEnvironment('CARTO_BASEMAP_KEY');

/// Lädt den gebündelten Karten-Stil: CARTO Dark Matter (Vektor, 93
/// Layer, scharf auf jedem Display). Die Raster-Variante
/// (moto-route-dark.json) ist Stilllegungs-kandidat: CARTO brennt dort
/// ohne gültigen Key ein "API KEY REQUIRED"-Wasserzeichen in die
/// Kacheln. Vektor-Tiles laufen (Stand Sep 2026) auch ohne Key.
Future<String> _loadLocalStyle() async {
  final raw = await rootBundle.loadString('assets/styles/carto-dark-matter.json');
  if (_cartoBasemapKey.isEmpty) {
    // Ohne Build-Key: Key-Parameter komplett entfernen (Vektor-Tiles
    // funktionieren auch ohne - nur ohne Quota-Absicherung).
    return raw
        .replaceAll('?key=__CARTO_KEY__', '')
        .replaceAll('&key=__CARTO_KEY__', '');
  }
  return raw.replaceAll('__CARTO_KEY__', _cartoBasemapKey);
}

/// Screen 3+4 aus Phase 3, Teil C: Startseite und Kartenseite sind
/// bewusst DERSELBE Screen. Diese Version zeigt POI-Kreise (je nach
/// aktiven Kategorien, nachgeladen bei Kartenausschnitt-Wechsel),
/// unterstützt das Setzen von Wegpunkten per Kartentap (Modus über
/// Button aktivierbar) und öffnet bei POI-Antippen ein Detail-Popup.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  MaplibreMapController? _mapController;
  late final PoiMapLayer _poiLayer;
  bool _hasLocationPermission = false;
  String? _styleString;
  final List<Circle> _incidentCircles = [];
  final List<Circle> _hazardCircles = [];

  /// Kartentap-Modus: aktivierte Route "Auf Karte antippen" (Phase 3,
  /// Screen 9: expliziter Modus-Umschalter, kein versehentlicher Tap).
  bool _tapMode = false;

  Timer? _bikerPoiSyncTimer;
  StreamSubscription<List<({String id, String action})>>? _bikerPoiPushSub;
  ProviderSubscription<BikerPoiSyncState>? _bikerPoiStateSub;

  @override
  void initState() {
    super.initState();
    _poiLayer = PoiMapLayer(() => _mapController);
    _requestLocationPermission();
    _loadStyle();
    _startBikerPoiSync();
  }

  /// Biker-POI-Live-Anbindung: 1) WS-Push (bikerpoi.batch über die
  /// App-WebSocket) löst sofort einen Delta-Sync aus, 2) nach jedem
  /// Sync - ob durch Push, Intervall oder App-Start - zeichnet der
  /// Karten-Layer NEU, OHNE auf eine Kamerabewegung zu warten. Der
  /// 10-Minuten-Timer bleibt als Fallback, falls die WS gerade tot ist.
  void _startBikerPoiSync() {
    // WS-Verbindung frühzeitig sicherstellen (Singleton, idempotent
    // über isConnected): ohne Chat-Login gibt es auch keinen Push -
    // der kuratierte Sync ist ohnehin ein angemeldet-Feature.
    final token = ref.read(chatSessionTokenProvider);
    final realtime = ref.read(chatRealtimeProvider);
    if (token != null && !realtime.isConnected) realtime.connect(token);

    _bikerPoiPushSub = realtime.bikerPoiChanges.listen((changes) {
      if (!mounted) return;
      ref
          .read(bikerPoiSyncProvider.notifier)
          .applyPush(changes.map((c) => c.id).toSet());
    });

    // Render nach jedem Sync-State-Wechsel mit neuen POIs (Identitäts-
    // vergleich: isSyncing/error-Wechsel zeichnen nicht neu).
    _bikerPoiStateSub = ref.listenManual<BikerPoiSyncState>(bikerPoiSyncProvider, (prev, next) {
      if (!mounted || identical(prev?.pois, next.pois)) return;
      _poiLayer.applyBikerPois(ref);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final sync = ref.read(bikerPoiSyncProvider.notifier);
      await sync.restoreCache();
      await sync.sync();
      if (!mounted) return;
      _bikerPoiSyncTimer = Timer.periodic(const Duration(minutes: 10), (_) {
        if (mounted) sync.sync();
      });
    });
  }

  @override
  void dispose() {
    _bikerPoiSyncTimer?.cancel();
    _bikerPoiPushSub?.cancel();
    _bikerPoiStateSub?.close();
    _poiLayer.dispose();
    super.dispose();
  }

  Future<void> _loadStyle() async {
    const styleUrl = String.fromEnvironment('MAP_STYLE_URL', defaultValue: '');
    if (styleUrl.isNotEmpty) {
      setState(() => _styleString = styleUrl);
    } else {
      try {
        final local = await _loadLocalStyle();
        if (mounted) setState(() => _styleString = local);
      } catch (_) {
        // Style-Asset fehlt: leerer Stil statt Crash - Routing bleibt
        // nutzbar, auch ohne Tile-Anbieter.
        if (mounted) setState(() => _styleString = '');
      }
    }
  }

  Future<void> _requestLocationPermission() async {
    final granted = await LocationRepository().ensurePermission();
    if (mounted) setState(() => _hasLocationPermission = granted);
  }

  Future<void> _centerOnPosition() async {
    try {
      final position = await LocationRepository().getCurrentPosition();
      await _mapController?.animateCamera(
        CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Standort nicht verfügbar')),
        );
      }
    }
  }

  /// Vorfälle (Stau/Sperrung) im aktuellen Kartenausschnitt als Kreise
  /// anzeigen - rot = blockierend/hoch, orange = Warnhinweis.
  Future<void> _drawIncidents(WidgetRef ref) async {
    final controller = _mapController;
    if (controller == null) return;
    try {
      final bounds = await controller.getVisibleRegion();
      await ref.read(trafficControllerProvider.notifier).loadViewport(
            minLng: bounds.southwest.longitude,
            minLat: bounds.southwest.latitude,
            maxLng: bounds.northeast.longitude,
            maxLat: bounds.northeast.latitude,
          );
    } catch (_) {
      return;
    }

    for (final c in _incidentCircles) {
      try {
        await controller.removeCircle(c);
      } catch (_) {}
    }
    _incidentCircles.clear();

    for (final incident in ref.read(trafficControllerProvider).incidents.take(50)) {
      if (incident.geometry.isEmpty) continue;
      final point = incident.geometry.first;
      try {
        _incidentCircles.add(await controller.addCircle(
          CircleOptions(
            geometry: LatLng(point[1], point[0]),
            circleRadius: incident.isBlocking ? 9 : 6,
            circleColor: incident.isBlocking ? '#E5484D' : '#F5A623',
            circleStrokeWidth: 2,
            circleStrokeColor: '#0B0E11',
            circleOpacity: 0.85,
          ),
        ));
      } catch (_) {}
    }
  }

  /// Gefahrenmeldungen im Viewport als pulsierend-rote Kreise zeichnen
  /// (Radius nach Bestätigungen skaliert: mehr Upvotes = größer).
  Future<void> _drawHazards(WidgetRef ref) async {
    final controller = _mapController;
    if (controller == null) return;

    // Radar-Laden um Kartenmitte (serverseitig gefiltert auf aktiv +
    // 24-h-Ablauf); Throttle im Controller verhindert Request-Stürme.
    try {
      final bounds = await controller.getVisibleRegion();
      final centerLat = (bounds.northeast.latitude + bounds.southwest.latitude) / 2;
      final centerLng = (bounds.northeast.longitude + bounds.southwest.longitude) / 2;
      await ref
          .read(hazardRadarProvider.notifier)
          .loadViewport(centerLat: centerLat, centerLng: centerLng);
    } catch (_) {
      return;
    }

    for (final c in _hazardCircles) {
      try {
        await controller.removeCircle(c);
      } catch (_) {}
    }
    _hazardCircles.clear();

    for (final hazard in ref.read(hazardRadarProvider).reports.take(80)) {
      try {
        _hazardCircles.add(await controller.addCircle(
          CircleOptions(
            geometry: LatLng(hazard.lat, hazard.lng),
            circleRadius: 8 + (hazard.upvotes.clamp(1, 10)).toDouble(),
            circleColor: hazard.type == HazardType.sperrung
                ? '#E5484D'
                : '#F5A623',
            circleStrokeWidth: 2,
            circleStrokeColor: '#0B0E11',
            circleOpacity: 0.9,
          ),
          {'hazardId': hazard.id},
        ));
      } catch (_) {}
    }
  }

  /// Kartentap: zuerst Gefahr, dann POI, sonst (im Tap-Modus) Wegpunkt.
  Future<void> _onMapTap(LatLng tapped) async {
    final hazard = _nearestHazard(tapped);
    if (hazard != null) {
      _showHazardDetails(hazard);
      return;
    }
    final poi = _poiLayer.handleMapTap(tapped);
    if (poi != null) {
      _showPoiDetails(poi);
      return;
    }

    if (!_tapMode) return;

    final position = await LocationRepository().getCurrentPosition();
    final waypoints = [...ref.read(waypointListProvider)];
    if (waypoints.isEmpty) {
      waypoints.add(Waypoint(
        lat: position.latitude,
        lng: position.longitude,
        label: 'Start',
      ));
    }

    // Ortsname asynchron aufloesen (TomTom Reverse-Geocoding im BFF):
    // Der Wegpunkt erscheint sofort mit Fallback-Label, der Name wird
    // nachgereicht - fuehlt sich sofort an, heisst aber Klartext.
    final isTargetReplacement = waypoints.length >= 2;
    final fallbackLabel =
        '${tapped.latitude.toStringAsFixed(4)}, ${tapped.longitude.toStringAsFixed(4)}';
    ref.read(searchRepositoryProvider).reverse(lat: tapped.latitude, lng: tapped.longitude).then((result) {
      if (!mounted) return;
      final list = [...ref.read(waypointListProvider)];
      if (list.isEmpty) return;
      final updated = Waypoint(
        lat: tapped.latitude,
        lng: tapped.longitude,
        label: result?.label ?? fallbackLabel,
      );
      if (isTargetReplacement && list.length >= 2) {
        list[list.length - 1] = updated;
      } else {
        list.add(updated);
      }
      ref.read(waypointListProvider.notifier).state = list;
    });

    // Ziel wird ersetzt, wenn es schon existiert; sonst neuer Wegpunkt.
    if (isTargetReplacement) {
      waypoints[waypoints.length - 1] = Waypoint(
        lat: tapped.latitude,
        lng: tapped.longitude,
        label: fallbackLabel,
      );
    } else {
      waypoints.add(Waypoint(
        lat: tapped.latitude,
        lng: tapped.longitude,
        label: fallbackLabel,
      ));
    }
    ref.read(waypointListProvider.notifier).state = waypoints;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Wegpunkt gesetzt - Ort wird aufgeloest …'),
          action: SnackBarAction(
            label: 'Verwalten',
            onPressed: () => Navigator.of(context).pushNamed('/waypoints'),
          ),
        ),
      );
    }
  }

  /// Nächstgelegene Gefahr im Touch-Toleranzradius (28 m, etwas großzü-
  /// giger als die 24 m der POIs, da Gefahren klein/schlank sind).
  HazardReport? _nearestHazard(LatLng tapped) {
    HazardReport? best;
    double bestDist = double.infinity;
    for (final h in ref.read(hazardRadarProvider).reports) {
      final dLat = (tapped.latitude - h.lat) * 111320;
      final dLng = (tapped.longitude - h.lng) * 111320 * 0.7;
      final d = dLat * dLat + dLng * dLng;
      if (d < bestDist) {
        bestDist = d;
        best = h;
      }
    }
    return best != null && bestDist <= 28 * 28 ? best : null;
  }

  /// Gefahren-Popup: Typ, Alter, Bestätigungen, Alter-Ablauf, Upvote-
  /// Button ("Gefahr ist noch da").
  void _showHazardDetails(HazardReport hazard) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgSurfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(hazard.type.label, style: AppTypography.title),
                  const Spacer(),
                  // Bestätigungen: große Zahl = viele Biker haben sie
                  // bestätigt = glaubwürdig.
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.bgSurfaceRaisedDark,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '👍 ${hazard.upvotes}',
                      style: const TextStyle(
                          color: AppColors.textPrimaryDark,
                          fontWeight: FontWeight.w800,
                          fontSize: 14),
                    ),
                  ),
                ],
              ),
              if (hazard.description.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(hazard.description, style: AppTypography.caption),
              ],
              const SizedBox(height: AppSpacing.sm),
              Text(
                'vor ${_hazardAge(hazard.createdAt)} gemeldet · gültig noch ${_hazardRemaining(hazard.expiresAt)}',
                style: AppTypography.caption,
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                height: AppSpacing.touchTargetPlanning,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.of(sheetContext).pop();
                    final res =
                        await ref.read(hazardRadarProvider.notifier).upvote(hazard.id);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(res.expired
                            ? 'Meldung ist abgelaufen - die Gefahr ist vermutlich weg'
                            : res.alreadyVoted
                                ? 'Du hast diese Gefahr bereits bestätigt'
                                : 'Danke! Meldung um 6 Stunden verlängert'),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.statusDanger,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.thumb_up),
                  label: const Text('Gefahr bestätigen (+6 h gültig)'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _hazardAge(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) return 'weniger als 1 Min.';
    if (diff.inMinutes < 60) return '${diff.inMinutes} Min.';
    if (diff.inHours < 24) return '${diff.inHours} Std.';
    return '${diff.inDays} Tagen';
  }

  /// Restlaufzeit (umgekehrte Differenz - "gültig noch", nicht "seit").
  static String _hazardRemaining(DateTime expiresAt) {
    final diff = expiresAt.difference(DateTime.now());
    if (diff.isNegative) return 'abgelaufen';
    if (diff.inMinutes < 60) return '${diff.inMinutes} Min.';
    if (diff.inHours < 24) return '${diff.inHours} Std.';
    return '${diff.inDays} Tagen';
  }

  void _showPoiDetails(Poi poi) {
    final bikerPoi = poi is BikerPoi ? poi : null;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgSurfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_iconFor(poi.category),
                      color: AppColors.accentSecondary, size: 24),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(poi.name, style: AppTypography.title),
                  ),
                  // Biker-Score (Alleinstellungsmerkmal des Kuratierungs-
                  // dienstes): nur bei POIs aus dem Biker-POI-Dienst.
                  if (bikerPoi != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.accentPrimaryDark.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '🏍️ ${bikerPoi.bikerScore}',
                        style: const TextStyle(
                            color: AppColors.accentPrimaryDark,
                            fontWeight: FontWeight.w800,
                            fontSize: 13),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${poi.category.label} · Quelle: ${bikerPoi != null ? 'Biker-Service (kuratiert)' : poi.source}',
                style: AppTypography.caption,
              ),
              if (bikerPoi != null && (bikerPoi.motorcycleParking || bikerPoi.meetingPoint))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 6,
                    children: [
                      if (bikerPoi.motorcycleParking)
                        _amenityChip('🏍️ Motorradparkplatz'),
                      if (bikerPoi.meetingPoint) _amenityChip('👥 Treffpunkt'),
                    ],
                  ),
                ),
              Text(
                '${poi.lat.toStringAsFixed(5)}, ${poi.lng.toStringAsFixed(5)}',
                style: AppTypography.caption,
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                height: AppSpacing.touchTargetPlanning,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _startRoutingFrom(poi);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentPrimaryDark,
                    foregroundColor: AppColors.textPrimaryLight,
                  ),
                  icon: const Icon(Icons.navigation),
                  label: const Text('Als Ziel setzen'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                height: AppSpacing.touchTargetPlanning,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _addBikerPoiAsWaypoint(poi);
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.accentSecondary),
                  ),
                  icon: const Icon(Icons.add_road, color: AppColors.accentSecondary),
                  label: const Text('Als Stopp in die Route',
                      style: TextStyle(color: AppColors.accentSecondary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// POI als Ziel: Start = aktueller Standort, dann Fahrstil-Auswahl.
  Future<void> _startRoutingFrom(Poi poi) async {
    try {
      final position = await LocationRepository().getCurrentPosition();
      final destination = Waypoint(
        lat: poi.lat,
        lng: poi.lng,
        label: poi.name,
      );
      ref.read(waypointListProvider.notifier).state = [
        Waypoint(lat: position.latitude, lng: position.longitude, label: 'Start'),
        destination,
      ];
      if (mounted) {
        Navigator.of(context).pushNamed('/route-style', arguments: {
          'start': ref.read(waypointListProvider).first,
          'destination': destination,
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Standort nicht verfügbar - Ziel kann nicht gesetzt werden')),
        );
      }
    }
  }

  /// Biker-POI als Stopp in die aktuelle Planung einreihen (vor dem Ziel).
  void _addBikerPoiAsWaypoint(Poi poi) {
    final current = ref.read(waypointListProvider);
    if (current.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Setze zuerst Start und Ziel - dann füge Stopps hinzu')),
      );
      return;
    }
    final stop = Waypoint(lat: poi.lat, lng: poi.lng, label: poi.name);
    ref.read(waypointListProvider.notifier).state = [
      ...current.sublist(0, current.length - 1),
      stop,
      current.last,
    ];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${poi.name}" als Stopp eingereiht')),
    );
  }

  Widget _amenityChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.bgSurfaceRaisedDark,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 11)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vehicleType = ref.watch(vehicleTypeProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      body: _styleString == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                MaplibreMap(
                  // Fallback: leerer Stil - maplibre_gl verlangt einen
                  // nicht-leeren String. Routing bleibt trotzdem nutzbar.
                  styleString: _styleString!.isEmpty
                      ? '{"version":8,"sources":{},"layers":[]}'
                      : _styleString!,
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(48.1351, 11.5820), // München als Startpunkt
                    zoom: 12,
                  ),
                  // Cockpit-Steuerung: Kompass dreht mit (tap = nach Norden
                  // zurück), Kameraposition wird getrackt.
                  compassEnabled: true,
                  compassViewPosition: CompassViewPosition.topRight,
                  trackCameraPosition: true,
                  myLocationEnabled: _hasLocationPermission,
                  myLocationTrackingMode: MyLocationTrackingMode.tracking,
                  onMapCreated: (controller) {
                    _mapController = controller;
                    _drawIncidents(ref);
                    _drawHazards(ref);
                  },
                  onMapClick: (point, latLng) => _onMapTap(latLng),
                  onCameraIdle: () {
                    _poiLayer.onCameraIdle(ref);
                    _drawIncidents(ref);
                    _drawHazards(ref);
                  },
                ),
                // Quellen-Hinweis (Pflicht bei OSM/CARTO-Daten) + ehrlicher
                // Fallback-Hinweis, falls Tiles nicht laden (Offline).
                Positioned(
                  left: AppSpacing.sm,
                  bottom: AppSpacing.xs,
                  child: Text(
                    _styleString!.isEmpty
                        ? 'Karte offline - POIs, Routing und Navigation funktionieren weiter'
                        : '© OpenStreetMap-Mitwirkende © CARTO',
                    style: const TextStyle(
                      color: AppColors.textMutedDark,
                      fontSize: 10,
                    ),
                  ),
                ),
                _buildTopBar(context, vehicleType),
                _buildSideButtons(context),
                if (_tapMode) _buildTapModeBanner(context),
              ],
            ),
    );
  }

  Widget _buildTopBar(BuildContext context, VehicleType vehicleType) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pushNamed('/search'),
                child: Container(
                  height: AppSpacing.touchTargetPlanning,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurfaceDark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderHairlineDark),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.search, color: AppColors.textSecondaryDark),
                      SizedBox(width: AppSpacing.sm),
                      Text('Ziel suchen',
                          style: TextStyle(color: AppColors.textSecondaryDark)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _VehicleSwitcher(current: vehicleType),
            const SizedBox(width: AppSpacing.sm),
            GestureDetector(
              onTap: () => Navigator.of(context).pushNamed('/chat'),
              child: const _ChatEntryButton(),
            ),
            const SizedBox(width: AppSpacing.sm),
            GestureDetector(
              onTap: () => Navigator.of(context).pushNamed('/settings'),
              child: _buildIconBox(Icons.person_outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSideButtons(BuildContext context) {
    return Positioned(
      right: AppSpacing.lg,
      bottom: AppSpacing.xxxl,
      child: Column(
        children: [
          // POI-Layer-Button
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).pushNamed('/pois');
            },
            child: _buildIconBox(Icons.layers, circular: true),
          ),
          const SizedBox(height: AppSpacing.md),
          // Community-Radar: Gefahrenstelle melden (2 Klicks von unterwegs).
          GestureDetector(
            onTap: () => showHazardReportSheet(context),
            child: Container(
              width: AppSpacing.touchTargetPlanning,
              height: AppSpacing.touchTargetPlanning,
              decoration: BoxDecoration(
                color: AppColors.bgSurfaceRaisedDark,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.borderHairlineDark),
              ),
              child: const Icon(Icons.warning_amber_rounded,
                  color: AppColors.statusDanger),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // "Wegpunkt per Kartentap setzen"-Button (Phase 3 Screen 9)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _tapMode = !_tapMode);
            },
            child: Container(
              width: AppSpacing.touchTargetPlanning,
              height: AppSpacing.touchTargetPlanning,
              decoration: BoxDecoration(
                color: _tapMode
                    ? AppColors.accentPrimaryDark
                    : AppColors.bgSurfaceRaisedDark,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _tapMode
                      ? AppColors.accentPrimaryDark
                      : AppColors.borderHairlineDark,
                ),
              ),
              child: Icon(
                Icons.add_location_alt_outlined,
                color: _tapMode
                    ? AppColors.textPrimaryDark
                    : AppColors.accentPrimaryDark,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          GestureDetector(
            onTap: _centerOnPosition,
            child: Container(
              width: AppSpacing.touchTargetPlanning,
              height: AppSpacing.touchTargetPlanning,
              decoration: BoxDecoration(
                color: AppColors.bgSurfaceRaisedDark,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.borderHairlineDark),
              ),
              child: const Icon(Icons.my_location,
                  color: AppColors.accentPrimaryDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTapModeBanner(BuildContext context) {
    return Positioned(
      top: AppSpacing.xxxl + AppSpacing.touchTargetPlanning + AppSpacing.lg,
      left: AppSpacing.lg,
      right: AppSpacing.lg,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.accentPrimaryDark.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.touch_app, color: AppColors.textPrimaryDark, size: 18),
            const SizedBox(width: AppSpacing.sm),
            const Expanded(
              child: Text(
                'Karte antippen, um einen Wegpunkt zu setzen',
                style: TextStyle(color: AppColors.textPrimaryDark),
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _tapMode = false),
              child: const Icon(Icons.close, color: AppColors.textPrimaryDark, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconBox(IconData icon, {bool circular = false}) {
    return Container(
      width: AppSpacing.touchTargetPlanning,
      height: AppSpacing.touchTargetPlanning,
      decoration: BoxDecoration(
        color: AppColors.bgSurfaceDark,
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderHairlineDark),
      ),
      child: Icon(icon, color: AppColors.textPrimaryDark),
    );
  }

  IconData _iconFor(PoiCategory category) => switch (category) {
        PoiCategory.fuel => Icons.local_gas_station,
        PoiCategory.motoHotel => Icons.hotel,
        PoiCategory.bikerMeetup => Icons.local_bar,
        PoiCategory.campsite => Icons.forest,
        PoiCategory.iceCream => Icons.icecream,
        PoiCategory.speedCamera => Icons.camera_alt,
        PoiCategory.restaurant => Icons.restaurant,
        PoiCategory.pub => Icons.sports_bar,
        PoiCategory.snack => Icons.fastfood,
      };
}

/// 💬 Chat-Einstieg auf der Karte mit Unread-Badge (Abschnitt 17:
/// „💬 Chat 🔴 3“) - liest den Overview-Controller, der auch ohne
/// geöffneten Chat im Hintergrund aktuelle Zähler hält, sobald
/// eine Session existiert.
class _ChatEntryButton extends ConsumerWidget {
  const _ChatEntryButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(chatOverviewProvider).totalUnread;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: AppSpacing.touchTargetPlanning,
          height: AppSpacing.touchTargetPlanning,
          decoration: BoxDecoration(
            color: AppColors.bgSurfaceDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderHairlineDark),
          ),
          child: const Icon(Icons.forum_outlined, color: AppColors.textPrimaryDark),
        ),
        if (unread > 0)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.statusDanger,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.bgBaseDark, width: 2),
              ),
              constraints: const BoxConstraints(minWidth: 18),
              child: Text(
                unread > 99 ? '99+' : '$unread',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimaryDark,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Fahrzeugtyp-Segment-Control - schreibt in den globalen
/// vehicleTypeProvider, aus dem der Routing-Flow liest.
class _VehicleSwitcher extends ConsumerWidget {
  final VehicleType current;

  const _VehicleSwitcher({required this.current});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: AppSpacing.touchTargetPlanning,
      decoration: BoxDecoration(
        color: AppColors.bgSurfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderHairlineDark),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final type in VehicleType.values)
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                ref.read(vehicleTypeProvider.notifier).state = type;
                persistVehicleType(type);
              },
              child: Container(
                width: AppSpacing.touchTargetPlanning,
                height: AppSpacing.touchTargetPlanning,
                decoration: BoxDecoration(
                  color: type == current
                      ? AppColors.accentPrimaryDark.withValues(alpha: 0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  switch (type) {
                    VehicleType.motorcycle => Icons.two_wheeler,
                    VehicleType.car => Icons.directions_car,
                    VehicleType.bicycle => Icons.pedal_bike,
                  },
                  color: type == current
                      ? AppColors.accentPrimaryDark
                      : AppColors.textSecondaryDark,
                  size: 22,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

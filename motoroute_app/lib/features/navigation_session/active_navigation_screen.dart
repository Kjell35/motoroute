import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:motoroute_app/core/i18n/i18n.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';
import 'package:motoroute_app/core/utils/formatters.dart';
import 'package:motoroute_app/features/map/data/map_style.dart';
import 'package:motoroute_app/features/navigation_session/navigation_providers.dart';
import 'package:motoroute_app/features/navigation_session/speed_camera_warner.dart';
import 'package:motoroute_app/features/ride_history/ride_history_sync.dart';
import 'package:motoroute_app/features/tour_diary/domain/tour_entities.dart';
import 'package:motoroute_app/features/tour_diary/tour_diary_providers.dart';
import 'package:motoroute_app/features/tour_diary/tour_recorder.dart';
import 'package:motoroute_app/features/traffic/traffic_providers.dart';
import 'package:motoroute_app/features/weather/route_weather_providers.dart';
import 'package:motoroute_app/features/weather/route_weather_widget.dart';

/// Screen 8: Aktive Navigation - der sicherheitskritischste Screen.
/// Echt verdrahtet: Start schreibt die aktive Route in den Navigation-
/// Controller (GPS-Stream, Off-Route-Erkennung, Rerouting), die untere
/// Zone zeigt live Restdistanz/ETA/Geschwindigkeit.
class ActiveNavigationScreen extends ConsumerStatefulWidget {
  const ActiveNavigationScreen({super.key});

  @override
  ConsumerState<ActiveNavigationScreen> createState() => _ActiveNavigationScreenState();
}

class _ActiveNavigationScreenState extends ConsumerState<ActiveNavigationScreen> {
  MaplibreMapController? _mapController;
  bool _routeDrawn = false;
  Set<String> _drawnIncidentIds = {};
  final List<Circle> _incidentCircles = [];
  String? _styleString;

  /// Karte-Objekte der AKTUELLEN Route (Linien + Marker). Bei Rerouting
  /// wird alles entfernt und neu gezeichnet - so zeigt die Karte immer
  /// die berechnete Route mit dem Fahrzeugprofil der Präferenz.
  final List<Line> _routeLines = [];
  final List<Symbol> _routeSymbols = [];
  Symbol? _gpsSymbol;

  /// Letzter GPS-Fix als LatLng (für den Standort-Marker).
  LatLng? _lastGps;

  /// Letzter gezeichneter Zustand, um unnötiges Neuzeichnen zu vermeiden
  /// (build läuft bei jedem GPS-Tick; gezeichnet wird nur bei
  /// Routenwechsel oder signifikantem Fortschritt).
  ComputedRoute? _lastDrawnRoute;
  int _lastDrawnIdx = -1;

  @override
  void initState() {
    super.initState();
    _loadStyle();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final route = ref.read(activeRouteProvider);
      if (route != null) {
        ref.read(navigationControllerProvider.notifier).start(route);
      }
      // Tour-Aufzeichnung läuft parallel zur Navigation - jede Fahrt
      // wird aufgezeichnet und landet nach dem Beenden im Tagebuch.
      ref.read(tourRecorderProvider.notifier).start();
    });
  }

  /// Gleicher Stil wie die Hauptkarte (geteilter Loader) - die Navigation
  /// hatte zuvor einen eigenen, nie gesetzten Stil-Eingang (MAP_STYLE_URL)
  /// und fuhr deshalb mit leerem Stil auf (schwarzer Hintergrund). Die
  /// Hell/Dunkel-Wahl aus den Einstellungen gilt auch hier.
  Future<void> _loadStyle() async {
    final choice = ref.read(mapStyleChoiceProvider);
    final style = await loadMapStyle(choice);
    if (mounted) setState(() => _styleString = style);
  }

  @override
  void dispose() {
    // Wichtig: GPS-Stream stoppen, wenn der Screen verlassen wird -
    // sonst läuft Standort-Abfrage im Hintergrund weiter (Akkueffizienz).
    ref.read(navigationControllerProvider.notifier).stop();
    ref.read(routeWeatherControllerProvider.notifier).stop();
    super.dispose();
  }

  /// Vorfälle als Kreise auf der Karte (rot = blocking/HIGH, orange =
  /// sonst). Kreise statt Linien: für "wo ist es kritisch" ist der
  /// Punkt entscheidend, und Circles sind ohne Layer-DSL robust.
  Future<void> _drawIncidents(List<TrafficIncident> incidents) async {
    final controller = _mapController;
    if (controller == null) return;

    final currentIds = incidents.map((i) => i.id).toSet();
    if (currentIds == _drawnIncidentIds) return;
    _drawnIncidentIds = currentIds;

    for (final c in _incidentCircles) {
      try {
        await controller.removeCircle(c);
      } catch (_) {}
    }
    _incidentCircles.clear();

    for (final incident in incidents.take(50)) {
      if (incident.geometry.isEmpty) continue;
      final point = incident.geometry.first;
      try {
        final circle = await controller.addCircle(
          CircleOptions(
            geometry: LatLng(point[1], point[0]),
            circleRadius: incident.isBlocking ? 10 : 7,
            circleColor: incident.isBlocking ? '#E5484D' : '#F5A623',
            circleStrokeWidth: 2,
            circleStrokeColor: '#0B0E11',
            circleOpacity: 0.85,
          ),
          {'incidentId': incident.id},
        );
        _incidentCircles.add(circle);
      } catch (_) {}
    }
  }

  Future<void> _drawRoute(ComputedRoute route) async {
    final controller = _mapController;
    if (controller == null) return;

    // Neu berechnete Route (Rerouting): alte Linien/Marker entfernen,
    // damit die Karte die AKTUELLE Route zeigt - neu berechnet mit dem
    // Fahrzeugprofil der ursprünglichen Präferenz.
    for (final line in _routeLines) {
      try {
        await controller.removeLine(line);
      } catch (_) {}
    }
    _routeLines.clear();
    for (final sym in _routeSymbols) {
      try {
        await controller.removeSymbol(sym);
      } catch (_) {}
    }
    _routeSymbols.clear();
    _gpsSymbol = null;

    final geometry = route.geometry;
    if (geometry.isEmpty) return;

    // Gefahrene vs. verbleibende Strecke: am Fortschritt geteilt. Der
    // Index kommt aus der kumulierten Distanz (identisch zur Off-Route-
    // Erkennung im NavigationController).
    final navState = ref.read(navigationControllerProvider);
    final isCurrentRoute = identical(navState.route, route);
    final traveledIdx = isCurrentRoute
        ? _indexForDistance(route, navState.traveledMeters)
        : 0;

    // Verbleibende Strecke (kräftiges Orange, gut sichtbar).
    final remaining = geometry
        .sublist(traveledIdx.clamp(0, geometry.length - 1))
        .map((p) => LatLng(p[1], p[0]))
        .toList();
    if (remaining.length >= 2) {
      try {
        final line = await controller.addLine(
          LineOptions(
            geometry: remaining,
            lineColor: '#FF5A1F',
            lineWidth: 6.0,
            lineOpacity: 0.95,
          ),
        );
        _routeLines.add(line);
      } catch (_) {}
    }

    // Bereits gefahrene Strecke (grau-transparent) - nur, wenn Fortschritt.
    if (traveledIdx > 0) {
      final traveled = geometry
          .sublist(0, traveledIdx + 1)
          .map((p) => LatLng(p[1], p[0]))
          .toList();
      if (traveled.length >= 2) {
        try {
          final line = await controller.addLine(
            LineOptions(
              geometry: traveled,
              lineColor: '#6B7280',
              lineWidth: 4.0,
              lineOpacity: 0.55,
            ),
          );
          _routeLines.add(line);
        } catch (_) {}
      }
    }

    // Marker: Start (grün), Ziel (rot), Wegpunkte/Stopps (orange).
    final waypoints = route.waypoints;
    for (var i = 0; i < waypoints.length; i++) {
      final wp = waypoints[i];
      final isFirst = i == 0;
      final isLast = i == waypoints.length - 1;
      try {
        final sym = await controller.addSymbol(
          SymbolOptions(
            geometry: LatLng(wp.lat, wp.lng),
            iconImage: 'circle-15',
            iconSize: isFirst || isLast ? 1.4 : 1.1,
            iconColor: isFirst
                ? '#3DD68C'
                : isLast
                    ? '#E5484D'
                    : '#FF5A1F',
            textField: wp.label ??
                (isFirst
                    ? 'Start'
                    : isLast
                        ? 'Ziel'
                        : '${i + 1}'),
            textOffset: const Offset(0, 1.2),
            textSize: 12,
            textColor: '#FFFFFF',
            textHaloColor: '#0B0E11',
            textHaloWidth: 1.2,
          ),
        );
        _routeSymbols.add(sym);
      } catch (_) {}
    }

    // Aktueller GPS-Standort (blau). myLocationEnabled zeigt ihn auch,
    // aber als Karten-Objekt bleibt er über Stil-Reloads hinweg sichtbar.
    final pos = _lastGps;
    if (pos != null) {
      try {
        final sym = await controller.addSymbol(
          SymbolOptions(
            geometry: pos,
            iconImage: 'circle-15',
            iconSize: 1.2,
            iconColor: '#3B82F6',
          ),
        );
        _routeSymbols.add(sym);
        _gpsSymbol = sym;
      } catch (_) {}
    }
  }

  /// Geometrie-Index zur kumulierten Distanz (für die Aufteilung
  /// gefahren/verbleibend). Nutzt dieselbe Kumulativ-Logik wie der
  /// NavigationController, ohne seinen internen Zustand zu brauchen.
  int _indexForDistance(ComputedRoute route, double traveledMeters) {
    final cumulative = route.cumulativeDistances();
    var best = 0;
    for (var i = 0; i < cumulative.length; i++) {
      if (cumulative[i] <= traveledMeters) best = i;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(navigationControllerProvider);
    final traffic = ref.watch(trafficControllerProvider);
    final unit = ref.watch(distanceUnitProvider);
    final route = state.route;

    // GPS-Position für den Marker mitschreiben.
    final pos = state.position;
    if (pos != null) {
      _lastGps = LatLng(pos.latitude, pos.longitude);
    }

    // Neu zeichnen nur bei Routenwechsel (auch Rerouting) oder wenn der
    // Fortschritt-Index springt (>= 5 Geometrie-Punkte) - nicht bei jedem
    // GPS-Tick (Karte würde flackern).
    if (route != null) {
      final idx = route == state.route
          ? _indexForDistance(route, state.traveledMeters)
          : 0;
      final needsRedraw = !identical(_lastDrawnRoute, route) ||
          (idx - _lastDrawnIdx).abs() >= 5;
      if (needsRedraw) {
        _lastDrawnRoute = route;
        _lastDrawnIdx = idx;
        _drawRoute(route);
      }
    }
    _drawIncidents(traffic.incidents);

    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopZone(route, state),
            const RouteWeatherWidget(),
            if (state.energySaverCritical) _buildEnergySaverWarning(),
            if (state.isRerouting || state.error != null || state.rerouteReason != null)
              _buildReroutingBanner(state),
            _buildSpeedCameraBanner(),
            Expanded(
              child: _styleString == null
                  // Stil lädt (Millisekunden, gebündelt): Ladeanzeige statt
                  // schwarzer Karte - gleiche Logik wie die Hauptkarte.
                  ? const Center(child: CircularProgressIndicator())
                  : Stack(
                      children: [
                        MaplibreMap(
                          // Gleicher Stil wie Hauptkarte (geteilter
                          // Loader); leerer Stil nur als Fallback, wenn
                          // das Asset fehlt.
                          styleString: isPlaceholderStyle(_styleString!)
                              ? emptyMapStyle
                              : _styleString!,
                          initialCameraPosition: CameraPosition(
                            target: route == null || route.geometry.isEmpty
                                ? const LatLng(48.1351, 11.5820)
                                : LatLng(route.geometry.first[1], route.geometry.first[0]),
                            zoom: 14,
                          ),
                          myLocationEnabled: true,
                          myLocationTrackingMode: MyLocationTrackingMode.tracking,
                          onMapCreated: (controller) {
                            _mapController = controller;
                            if (route != null) _drawRoute(route);
                          },
                        ),
                        if (state.isOffRoute)
                          const Positioned(
                            top: AppSpacing.md,
                            left: AppSpacing.lg,
                            right: AppSpacing.lg,
                            child: _OffRouteBadge(),
                          ),
                      ],
                    ),
            ),
            _buildBottomZone(state, unit),
            _buildControlButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTopZone(ComputedRoute? route, NavigationState state) {
    final i18n = ref.watch(i18nProvider);
    if (route == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        decoration: const BoxDecoration(
          color: AppColors.bgSurfaceDark,
          border: Border(bottom: BorderSide(color: AppColors.borderHairlineDark)),
        ),
        child: Text(i18n.navFollowRoute, style: AppTypography.navInstruction),
      );
    }

    // Dynamischer Hinweis: das nächste Manöver aus der ROUTE (nicht
    // immer das erste Segment) + Distanz dahin. "Danach"-Vorschau gibt
    // dem Fahrer Planungssicherheit (z. B. "Danach links auf B123").
    final next = route.nextTurn(state.traveledMeters);
    final segments = route.segments;
    String? afterwards;
    if (next != null && segments.isNotEmpty) {
      var segStart = 0.0;
      var found = false;
      for (var i = 0; i < segments.length; i++) {
        final seg = segments[i];
        if (!found) {
          if (segStart + 5 >= state.traveledMeters &&
              seg.instruction == next.text) {
            found = true;
            // Nächster Nicht-Ziel-Hinweis danach.
            for (var j = i + 1; j < segments.length; j++) {
              final s2 = segments[j];
              if (!s2.instruction.toLowerCase().contains('ziel')) {
                afterwards = s2.instruction;
                break;
              }
            }
            break;
          }
          segStart += seg.distanceMeters;
        }
      }
    }

    final distanceText = next == null
        ? null
        : (next.distanceMeters < 1000
            ? '${next.distanceMeters.round()} m'
            : '${(next.distanceMeters / 1000).toStringAsFixed(next.distanceMeters < 10000 ? 1 : 0)} km');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: const BoxDecoration(
        color: AppColors.bgSurfaceDark,
        border: Border(bottom: BorderSide(color: AppColors.borderHairlineDark)),
      ),
      child: Row(
        children: [
          const Icon(Icons.turn_left, color: AppColors.accentPrimaryDark, size: 32),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  next == null
                      ? i18n.navFollowRoute
                      : distanceText == '0 m'
                          ? next.text
                          : 'In $distanceText: ${next.text}',
                  style: AppTypography.navInstruction,
                ),
                if (afterwards != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Danach: $afterwards',
                      style: AppTypography.caption,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Sicherheitshinweis bei kritischem Akku: GPS ist dann so weit
  /// gedrosselt, dass Off-Route-Erkennung deutlich später (oder gar
  /// nicht) greift - das muss der Fahrer wissen, nicht überraschen
  /// werden (Phase 3 Teil B.10: keine stillen Verschlechterungen).
  Widget _buildEnergySaverWarning() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      color: AppColors.statusDanger.withValues(alpha: 0.2),
      child: const Row(
        children: [
          Icon(Icons.battery_alert, color: AppColors.statusDanger, size: 16),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Kritischer Akku - GPS gedrosselt, Off-Route-Warnung verzögert',
              style: AppTypography.caption,
            ),
          ),
        ],
      ),
    );
  }

  /// Blitzer-Fahrtwarnung: schmaler roter Banner über der Karte, mit
  /// Entfernungsangabe. Verschwindet automatisch nach dem Passieren
  /// (Controller räumt auf). Kein Modal - der Fahrer braucht die Straße.
  Widget _buildSpeedCameraBanner() {
    final warning = ref.watch(speedCameraWarnerProvider).activeWarning;
    if (warning == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      color: AppColors.statusDanger,
      child: Row(
        children: [
          const Icon(Icons.speed, color: Colors.white, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Text(
            speedCameraBannerText(warning),
            style: AppTypography.body.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReroutingBanner(NavigationState state) {
    // Drei Zustände: laufende Anpassung (orange), abgeschlossene
    // proaktive Umleitung mit Grund (grünlich, auto-vergehend), Fehler
    // (rot). Phase 3 B.10: nie modal, immer als schmaler Banner.
    final Color bg;
    final Color fg;
    final IconData icon;
    final String text;
    if (state.isRerouting) {
      bg = AppColors.statusWarning.withValues(alpha: 0.15);
      fg = AppColors.statusWarning;
      icon = Icons.refresh;
      text = ref.watch(i18nProvider).navRerouting;
    } else if (state.rerouteReason != null) {
      bg = AppColors.accentSecondary.withValues(alpha: 0.15);
      fg = AppColors.accentSecondary;
      icon = Icons.alt_route;
      text = 'Umleitung: ${state.rerouteReason}';
    } else {
      bg = AppColors.statusDanger.withValues(alpha: 0.15);
      fg = AppColors.statusDanger;
      icon = Icons.error_outline;
      text = state.error ?? '';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      color: bg,
      child: Row(
        children: [
          Icon(icon, color: fg, size: 16),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: AppTypography.caption)),
        ],
      ),
    );
  }

  Widget _buildBottomZone(NavigationState state, dynamic unit) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: const BoxDecoration(
        color: AppColors.bgSurfaceDark,
        border: Border(top: BorderSide(color: AppColors.borderHairlineDark)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ValueItem(
              icon: Icons.speed,
              value: formatSpeedMps(state.speedMps, unit: unit),
            ),
          ),
          Expanded(
            child: _ValueItem(
              icon: Icons.straighten,
              value: formatDistanceMeters(state.remainingMeters, unit: unit),
            ),
          ),
          Expanded(
            child: _ValueItem(
              icon: Icons.access_time,
              value: formatEta(DateTime.now(), state.remainingSeconds),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: _CircleButton(
              icon: Icons.stop,
              label: ref.watch(i18nProvider).navEnd,
              onTap: () => _endNavigation(context),
            ),
          ),
        ],
      ),
    );
  }

  /// Navigation beenden + aufgezeichnete Tour ins Tagebuch speichern.
  /// Fehler beim Speichern dürfen das Beenden NICHT blockieren - die
  /// Fahrt ist vorbei, der Fahrer will raus.
  Future<void> _endNavigation(BuildContext context) async {
    final recorder = ref.read(tourRecorderProvider.notifier);
    ref.read(navigationControllerProvider.notifier).stop();

    RecordedTour? tour;
    try {
      tour = await recorder.stop();
    } catch (_) {
      tour = null;
    }
    ref.read(routeWeatherControllerProvider.notifier).stop();

    if (!context.mounted) return;
    Navigator.of(context).popUntil((r) => r.settings.name == '/map' || r.isFirst);

    if (tour != null && context.mounted) {
      // Name abfragen (leer = Standardtitel), dann im Tagebuch auffrischen.
      final i18n = ref.read(i18nProvider);
      final controller = TextEditingController(text: tour.title);
      final name = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppColors.bgSurfaceDark,
          title: Text(i18n.tr('tour.saveTitle'), style: AppTypography.title),
          content: TextField(
            controller: controller,
            maxLength: 80,
            autofocus: true,
            style: AppTypography.body,
            decoration: InputDecoration(
              hintText: i18n.tr('tour.saveHint'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: Text(i18n.tr('tour.discard')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
              style: FilledButton.styleFrom(backgroundColor: AppColors.accentPrimaryDark),
              child: Text(i18n.save),
            ),
          ],
        ),
      );
      if (name == null) {
        // Verwerfen: Tour aus der DB löschen.
        if (tour.id != null) {
          try {
            await ref.read(tourDatabaseProvider).deleteTour(tour.id!);
          } catch (_) {}
        }
        return;
      }
      if (name.isNotEmpty && name != tour.title) {
        try {
          await ref
              .read(tourDatabaseProvider)
              .updateTour(tour.copyWith(title: name));
        } catch (_) {}
      }
      ref.read(tourDiaryProvider.notifier).refresh();
      // Auto-Sync der beendeten Fahrt ins Profil (best-effort, nur mit
      // Anmeldung; Sichtbarkeit regelt serverseitig die Privatsphäre).
      await ref
          .read(rideHistorySyncProvider)
          .syncFinishedTour(tour, description: name);
    }
  }
}

class _OffRouteBadge extends ConsumerWidget {
  const _OffRouteBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.statusWarning.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.route, color: AppColors.textPrimaryDark, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Text(ref.watch(i18nProvider).navOffRoute, style: AppTypography.caption),
        ],
      ),
    );
  }
}

class _ValueItem extends StatelessWidget {
  final IconData icon;
  final String value;

  const _ValueItem({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.textSecondaryDark, size: 18),
        Text(value, style: AppTypography.bodyStrong),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgSurfaceRaisedDark.withValues(alpha: 0.7),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: AppSpacing.touchTargetDriving,
          height: AppSpacing.touchTargetDriving,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.textPrimaryDark, size: 24),
              Text(label, style: AppTypography.caption),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../chat/chat_providers.dart';
import '../chat/data/chat_realtime.dart';
import '../map/data/location_repository.dart';
import '../settings/energy_saver.dart' show LocationAccuracyPreset, LocationTuning;
import 'group_ride_repository.dart';

/// Zustand der Live-Gruppenfahrt aus Sicht des aktuellen Nutzers.
class GroupRideState {
  /// Fahrer, die gerade teilen (inkl. eigenem Eintrag, falls geteilt).
  final List<LiveRider> riders;

  /// Teile ich gerade meine Position? (striktes OPT-IN, Default: NEIN)
  final bool isSharing;

  final bool isLoading;
  final String? error;

  const GroupRideState({
    this.riders = const [],
    this.isSharing = false,
    this.isLoading = false,
    this.error,
  });

  /// Wer ist unterwegs (gestartet, nicht fertig)?
  List<LiveRider> get onTheRoad => riders.where((r) => r.started && !r.finished).toList();

  /// Wer hat noch nicht gestartet (aber teilt bereits)?
  List<LiveRider> get notStartedYet => riders.where((r) => !r.started).toList();

  /// Wer ist fertig?
  List<LiveRider> get finishedRiders => riders.where((r) => r.finished).toList();

  GroupRideState copyWith({
    List<LiveRider>? riders,
    bool? isSharing,
    bool? isLoading,
    String? error,
  }) =>
      GroupRideState(
        riders: riders ?? this.riders,
        isSharing: isSharing ?? this.isSharing,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

///
/// Controller der Live-Gruppenfahrt.
///
/// Datenschutz-Architektur (Vorgabe Abschnitt 18): Der GPS-Stream läuft
/// NUR, wenn der Nutzer die Freigabe explizit aktiviert hat. Der Stream
/// wird beim Deaktivieren sofort gestoppt und serverseitig die Zeile
/// gelöscht. Es gibt keine Passiv-Erfassung.
///
/// Herzfrequenz: 15 s Heartbeat (Position im Gruppenkontext braucht keine
/// Navigations-Präzision) - bewusst sparsamer als der 3-s-Loop der
/// Navigation. Bei Verbindungsverlust läuft der GPS-Stream weiter, aber
/// nur maximal 3 fehlgeschlagene Beats in Folge, dann pausiert der
/// Controller die Übertragung bis zum nächsten erfolgreichen Refresh.
class GroupRideController extends StateNotifier<GroupRideState> {
  final GroupRideRepository _repo;
  final Ref _ref;
  final ChatRealtimeClient _realtime;
  final String routeId;

  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<GroupRouteWsEvent>? _eventSub;
  StreamSubscription<RadarEvent>? _radarSub;
  Timer? _refreshTimer;
  int _failedBeats = 0;
  bool _disposed = false;

  GroupRideController(this._repo, ChatRealtimeClient realtime, this._ref, this.routeId)
      : _realtime = realtime,
        super(const GroupRideState()) {
    // Realtime: Andere Fahrer gestartet/fertig -> Live-Liste nachziehen.
    _eventSub = realtime.grouprouteEvents
        .where((e) => e.routeId == routeId)
        .listen((_) => refresh(silent: true));

    // Ride-Radar (Live-Gruppenfahrt + Radar): Positionen der eigenen
    // Route UNABHÄNGIG vom Umkreis. Abonnement nur mit Token (server-
    // seitige Membership-Prüfung im BFF); bei Reconnect neu abonnieren.
    final token = _ref.read(chatSessionTokenProvider);
    if (token != null) {
      _realtime.subscribeRide(routeId);
    }
    _radarSub = _realtime.radarEvents
        .where((e) => e.routeId == routeId)
        .listen(_applyRadarEvent);

    // Lazy-Refresh alle 20 s als Fallback (WS kann weg sein).
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) => refresh(silent: true));
  }

  /// Radar-Event anwenden: vollständige Mitgliederliste (serverseitig
  /// verifiziert) sofort in den State - ohne REST-Refresh. Leave entfernt
  /// den Fahrer lokal.
  void _applyRadarEvent(RadarEvent event) {
    if (_disposed) return;
    if (event.isLeave) {
      state = state.copyWith(
        riders: state.riders.where((r) => r.userId != event.leftUserId).toList(growable: false),
      );
      return;
    }
    if (event.members.isEmpty) return;
    // Merge: Positionen/lastSeen aus dem Radar-Event in die Live-Liste
    // (Profil/Status-Felder bleiben aus dem REST-Stand erhalten).
    final byId = {for (final r in state.riders) r.userId: r};
    for (final m in event.members) {
      final existing = byId[m.userId];
      byId[m.userId] = existing == null
          ? LiveRider(
              userId: m.userId,
              lat: m.lat,
              lng: m.lng,
              started: true,
              finished: false,
              lastBeatAt: m.lastSeen,
            )
          : LiveRider(
              userId: existing.userId,
              lat: m.lat,
              lng: m.lng,
              started: existing.started,
              finished: existing.finished,
              lastBeatAt: m.lastSeen ?? existing.lastBeatAt,
              user: existing.user,
            );
    }
    state = state.copyWith(riders: byId.values.toList(growable: false));
  }

  String? get _token => _ref.read(chatSessionTokenProvider);

  Future<void> load() async {
    await refresh();
  }

  Future<void> refresh({bool silent = false}) async {
    final token = _token;
    if (token == null) return;
    if (!silent) state = state.copyWith(isLoading: true);
    try {
      final riders = await _repo.liveState(token, routeId);
      if (_disposed) return;
      final me = _ref.read(chatMeProvider).value?.id;
      state = state.copyWith(
        riders: riders,
        isSharing: me != null && riders.any((r) => r.userId == me),
        isLoading: false,
        error: null,
      );
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(isLoading: false, error: rideFailureMessage(e));
    }
  }

  /// OPT-IN: Nutzer aktiviert die Freigabe -> GPS-Stream + erster Beat.
  Future<void> enableSharing() async {
    final token = _token;
    if (token == null) return;
    final hasPermission = await LocationRepository().ensurePermission();
    if (!hasPermission) {
      state = state.copyWith(error: 'Standortberechtigung erforderlich');
      return;
    }
    try {
      final position = await LocationRepository().getCurrentPosition();
      await _repo.startSharing(token, routeId, lat: position.latitude, lng: position.longitude);
      if (_disposed) return;
      state = state.copyWith(isSharing: true, error: null);
      _startGpsLoop();
      await refresh(silent: true);
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(error: rideFailureMessage(e));
    }
  }

  /// OPT-OUT: Freigabe beenden -> GPS-Stream stoppen, serverseitig löschen.
  Future<void> disableSharing() async {
    final token = _token;
    if (token == null) return;
    _gpsSub?.cancel();
    _gpsSub = null;
    try {
      await _repo.stopSharing(token, routeId);
    } catch (_) {
      // Auch bei Fehler lokal deaktivieren - der Server räumt den
      // verwaisten Heartbeat per last_beat_at-Stale-Logik später weg.
    }
    if (_disposed) return;
    state = state.copyWith(isSharing: false);
    await refresh(silent: true);
  }

  /// Sich selbst als fertig markieren (Teilen läuft weiter).
  Future<void> markFinished() async {
    final token = _token;
    if (token == null) return;
    try {
      await _repo.finish(token, routeId);
      await refresh(silent: true);
    } catch (e) {
      state = state.copyWith(error: rideFailureMessage(e));
    }
  }

  /// GPS-Stream mit großzügiger Distanz-Filterung (30 m) und 15-s-Beats.
  /// Bewusst LOW-Accuracy-Preset: Gruppenkontext braucht keine
  /// Navigationsgenauigkeit, Akku geht vor.
  void _startGpsLoop() {
    _gpsSub?.cancel();
    _gpsSub = LocationRepository()
        .watchPosition(
          tuning: LocationTuning(
            accuracy: LocationAccuracyPreset.low,
            distanceFilterMeters: 30,
          ),
        )
        .listen(
          (position) => _sendBeat(position.latitude, position.longitude),
          onError: (_) {}, // Funkloch: letzter Beat bleibt stehen.
        );
  }

  Future<void> _sendBeat(double lat, double lng) async {
    final token = _token;
    if (token == null || _disposed) return;
    if (!state.isSharing) return; // Sicherheitsnetz neben abonniertem Stream.
    try {
      await _repo.heartbeat(token, routeId, lat: lat, lng: lng);
      _failedBeats = 0;
    } catch (_) {
      _failedBeats += 1;
      if (_failedBeats >= 3) {
        // 3 Fehlschläge: GPS stoppen, Nutzer sieht Status in der UI
        // (error-Feld wird beim nächsten Refresh gesetzt).
        await _gpsSub?.cancel();
        _gpsSub = null;
        state = state.copyWith(error: 'Übertragung unterbrochen - Freigabe erneut aktivieren');
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _gpsSub?.cancel();
    _eventSub?.cancel();
    _radarSub?.cancel();
    _refreshTimer?.cancel();
    // Ride-Radar-Abonnement sauber beenden (kein Empfang nach Dispose).
    // Bewusst über das gespeicherte Feld statt _ref.read: während des
    // Dispose ist kein Provider-Zugriff mehr erlaubt.
    _realtime.unsubscribeRide(routeId);
    super.dispose();
  }
}

final groupRideProvider = StateNotifierProvider.family<GroupRideController, GroupRideState, String>(
  (ref, routeId) => GroupRideController(
    ref.watch(groupRideRepositoryProvider),
    ref.watch(chatRealtimeProvider),
    ref,
    routeId,
  ),
);

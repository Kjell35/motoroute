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

  /// Server sagt "du teilst", lokal läuft aber kein Stream - typisch nach
  /// einem App-Abbruch. Die Zeile muss aufgeräumt oder neu gestartet werden,
  /// sonst sehen andere Fahrer eine eingefrorene Position.
  final bool isStaleSharing;

  const GroupRideState({
    this.riders = const [],
    this.isSharing = false,
    this.isLoading = false,
    this.error,
    this.isStaleSharing = false,
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
    bool? isStaleSharing,
  }) =>
      GroupRideState(
        riders: riders ?? this.riders,
        isSharing: isSharing ?? this.isSharing,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        isStaleSharing: isStaleSharing ?? this.isStaleSharing,
      );
}

/// Zustand der Positions-Freigabe selbst.
///
/// Lebt in [groupRideSharingProvider] und damit länger als der Screen: Die
/// Freigabe soll weiterlaufen, wenn der Fahrer die Gruppenfahrt-Ansicht
/// schließt - nur die UI-Abos (Refresh-Timer, WebSocket) sollen enden.
class GroupRideSharingState {
  final String? routeId;
  final bool active;
  final String? error;

  const GroupRideSharingState({this.routeId, this.active = false, this.error});
}

/// Besitzt den GPS-Stream und die Beats. Genau EINE Freigabe zur Zeit:
/// Startet der Fahrer auf einer anderen Route, wird die vorherige serverseitig
/// beendet, sonst liefen zwei Uploads parallel.
class GroupRideSharingController extends StateNotifier<GroupRideSharingState> {
  final GroupRideRepository _repo;
  final LocationRepository _location;
  final Ref _ref;

  StreamSubscription<Position>? _gpsSub;
  int _failedBeats = 0;
  bool _disposed = false;

  GroupRideSharingController(this._repo, this._location, this._ref)
      : super(const GroupRideSharingState());

  bool isActiveFor(String routeId) => state.active && state.routeId == routeId;

  String? get _token => _ref.read(chatSessionTokenProvider);

  /// OPT-IN: Freigabe starten. `false` heisst: nicht gestartet, Grund im State.
  Future<bool> start(String routeId) async {
    final token = _token;
    if (token == null) return false;
    if (isActiveFor(routeId)) return true;
    if (state.active) await stop();

    final hasPermission = await _location.ensurePermission();
    if (!hasPermission) {
      _publish(error: 'Standortberechtigung erforderlich');
      return false;
    }
    try {
      final position = await _location.getCurrentPosition();
      await _repo.startSharing(token, routeId,
          lat: position.latitude, lng: position.longitude);
      if (_disposed) return false;
      state = GroupRideSharingState(routeId: routeId, active: true);
      _startGpsLoop(routeId);
      return true;
    } catch (e) {
      _publish(error: rideFailureMessage(e));
      return false;
    }
  }

  /// OPT-OUT: Stream stoppen, serverseitig die Zeile löschen.
  Future<void> stop({String? routeId}) async {
    final token = _token;
    // Route explizit: eine verwaiste Server-Zeile existiert gerade dann,
    // wenn der Service selbst (noch) keine Route kennt.
    final target = routeId ?? state.routeId;
    _gpsSub?.cancel();
    _gpsSub = null;
    _failedBeats = 0;
    if (target != null && token != null) {
      try {
        await _repo.stopSharing(token, target);
      } catch (_) {
        // Server räumt den verwaisten Eintrag über last_beat_at auf.
      }
    }
    if (_disposed) return;
    state = const GroupRideSharingState();
  }

  void _publish({required String error}) {
    if (_disposed) return;
    state = GroupRideSharingState(routeId: state.routeId, error: error);
  }

  /// GPS-Stream mit großzügiger Distanz-Filterung (30 m) und 15-s-Beats.
  /// Bewusst LOW-Accuracy-Preset: Gruppenkontext braucht keine
  /// Navigationsgenauigkeit, Akku geht vor.
  void _startGpsLoop(String routeId) {
    _gpsSub?.cancel();
    // Neustart nach einem Funkloch beginnt wieder bei null Fehlschlaegen,
    // sonst reisst der erste Beat danach die frische Freigabe sofort ab.
    _failedBeats = 0;
    // Über den Provider statt `new LocationRepository()`: so laufen Tests
    // gegen den Mock, und der Foreground-Service hält die Beats am Leben,
    // wenn das Handy in der Tasche steckt - sonst endet die Gruppenfahrt
    // genau dann, wenn sie gebraucht wird.
    _gpsSub = _location
        .watchPosition(
          tuning: const LocationTuning(
            accuracy: LocationAccuracyPreset.low,
            distanceFilterMeters: 30,
          ),
          backgroundNavigation: true,
          notificationTitle: 'MotoRoute Gruppenfahrt',
          notificationText: 'Dein Standort wird mit der Gruppe geteilt.',
        )
        .listen(
          (position) => _sendBeat(routeId, position.latitude, position.longitude),
          onError: (_) {}, // Funkloch: letzter Beat bleibt stehen.
        );
  }

  Future<void> _sendBeat(String routeId, double lat, double lng) async {
    final token = _token;
    if (token == null || _disposed) return;
    if (!isActiveFor(routeId)) return;
    try {
      await _repo.heartbeat(token, routeId, lat: lat, lng: lng);
      _failedBeats = 0;
    } catch (_) {
      _failedBeats += 1;
      if (_failedBeats >= 3) {
        // 3 Fehlschläge: der Stream ist tot, also ist es die Freigabe auch.
        // Serverseitig aufräumen (best effort) und den Fehler am State
        // festhalten, statt ihn vom nächsten Refresh löschen zu lassen.
        await _gpsSub?.cancel();
        _gpsSub = null;
        // Ein toter Stream darf nicht als "teilt" angezeigt werden.
        state = GroupRideSharingState(
          routeId: routeId,
          active: false,
          error: 'Übertragung unterbrochen - Freigabe erneut aktivieren',
        );
        try {
          await _repo.stopSharing(token, routeId);
        } catch (_) {
          // Server räumt den verwaisten Eintrag über last_beat_at auf.
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // Nur den Stream abklemmen: die serverseitige Freigabe endet bewusst
    // nicht beim App-/Container-Ende, das erledigt die Stale-Logik.
    _gpsSub?.cancel();
    super.dispose();
  }
}

///
/// Controller der Live-Gruppenfahrt (Ansicht).
///
/// Datenschutz-Architektur (Vorgabe Abschnitt 18): Der GPS-Stream läuft
/// NUR, wenn der Nutzer die Freigabe explizit aktiviert hat. Er wird vom
/// [GroupRideSharingController] gehalten und beim Deaktivieren sofort
/// gestoppt, dazu serverseitig die Zeile gelöscht. Es gibt keine
/// Passiv-Erfassung.
///
/// Dieser Controller ist `autoDispose`: Verlässt der Fahrer den Screen,
/// enden Refresh-Timer und WebSocket-Abos. Die Freigabe selbst läuft weiter
/// (eigener Provider), damit die Gruppe den Fahrer nicht verliert.
///
/// Herzfrequenz: 15 s Heartbeat (Position im Gruppenkontext braucht keine
/// Navigations-Präzision) - bewusst sparsamer als der 3-s-Loop der
/// Navigation.
class GroupRideController extends StateNotifier<GroupRideState> {
  final GroupRideRepository _repo;
  final Ref _ref;
  final ChatRealtimeClient _realtime;
  final String routeId;

  StreamSubscription<GroupRouteWsEvent>? _eventSub;
  StreamSubscription<RadarEvent>? _radarSub;
  ProviderSubscription<GroupRideSharingState>? _shareSub;
  Timer? _refreshTimer;
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

    // Freigabe-Zustand kommt aus dem langlebigen Sharing-Provider: so weiss
    // die Ansicht auch nach einem Wiedereintritt, dass noch geteilt wird.
    _shareSub = _ref.listen<GroupRideSharingState>(
      groupRideSharingProvider,
      (_, next) {
        if (_disposed) return;
        final activeHere = next.active && next.routeId == routeId;
        state = state.copyWith(
          isSharing: activeHere,
          // Ein frisch gestarteter Stream macht die verwaiste Zeile gültig.
          isStaleSharing: activeHere ? false : state.isStaleSharing,
          error: next.routeId == routeId ? next.error : null,
        );
      },
      fireImmediately: true,
    );

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
    final sharing = _ref.read(groupRideSharingProvider);
    final sharingError = sharing.routeId == routeId ? sharing.error : null;
    try {
      final riders = await _repo.liveState(token, routeId);
      if (_disposed) return;
      // .future statt .value: beim ersten Oeffnen ist das Profil noch im
      // Ladezustand - dann wuerde die verwaiste Server-Zeile nicht erkannt.
      final me = (await _ref.read(chatMeProvider.future))?.id;
      if (_disposed) return;
      final mine = me != null && riders.any((r) => r.userId == me);
      final activeHere = sharing.active && sharing.routeId == routeId;
      state = state.copyWith(
        riders: riders,
        // Laufender Stream zaehlt auch dann, wenn das eigene Profil noch
        // nicht geladen ist - sonst springt der Schalter nach dem
        // Einschalten zurueck und ein zweiter Tipp startet einen zweiten
        // Upload.
        isSharing: activeHere || mine,
        // Serverzeile ohne laufenden Stream: nach App-Abbruch übrig.
        isStaleSharing: mine && !activeHere,
        isLoading: false,
        error: sharingError,
      );
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(
        isLoading: false,
        error: sharingError ?? rideFailureMessage(e),
      );
    }
  }

  /// OPT-IN: Nutzer aktiviert die Freigabe -> GPS-Stream + erster Beat.
  Future<void> enableSharing() async {
    final token = _token;
    if (token == null) return;
    if (state.isSharing) return; // Doppeltipp startet keinen zweiten Loop.
    final ok = await _ref.read(groupRideSharingProvider.notifier).start(routeId);
    if (_disposed) return;
    if (!ok) {
      final error = _ref.read(groupRideSharingProvider).error;
      state = state.copyWith(
        isSharing: false,
        error: error ?? 'Freigabe konnte nicht gestartet werden',
      );
      return;
    }
    state = state.copyWith(isSharing: true, error: null);
    await refresh(silent: true);
  }

  /// Verwaiste Freigabe neu aufsetzen: erst die alte Server-Zeile löschen,
  /// dann regulär starten - so ist der Ablauf derselbe wie beim Opt-in.
  Future<void> restartSharing() async {
    await disableSharing();
    if (_disposed) return;
    await enableSharing();
  }

  /// OPT-OUT: Freigabe beenden -> GPS-Stream stoppen, serverseitig löschen.
  Future<void> disableSharing() async {
    await _ref.read(groupRideSharingProvider.notifier).stop(routeId: routeId);
    if (_disposed) return;
    state = state.copyWith(isSharing: false, error: null);
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

  @override
  void dispose() {
    _disposed = true;
    // Wichtig: Hier wird der GPS-Stream NICHT gestoppt - das macht allein
    // der Sharing-Provider. Sonst endet die Gruppenfahrt beim Schließen
    // des Screens.
    _eventSub?.cancel();
    _radarSub?.cancel();
    _shareSub?.close();
    _refreshTimer?.cancel();
    // Ride-Radar-Abonnement sauber beenden (kein Empfang nach Dispose).
    // Bewusst über das gespeicherte Feld statt _ref.read: während des
    // Dispose ist kein Provider-Zugriff mehr erlaubt.
    _realtime.unsubscribeRide(routeId);
    super.dispose();
  }
}

/// Einzige Instanz der Positions-Freigabe: lebt so lange wie die App.
final groupRideSharingProvider =
    StateNotifierProvider<GroupRideSharingController, GroupRideSharingState>((ref) {
  return GroupRideSharingController(
    ref.watch(groupRideRepositoryProvider),
    ref.watch(locationRepositoryProvider),
    ref,
  );
});

/// Ansicht-Zustand pro Route. `autoDispose`: Beim Verlassen des Screens
/// enden Timer und WebSocket-Abos, die Freigabe läuft im Sharing-Provider
/// weiter.
final groupRideProvider =
    StateNotifierProvider.autoDispose.family<GroupRideController, GroupRideState, String>(
  (ref, routeId) => GroupRideController(
    ref.watch(groupRideRepositoryProvider),
    ref.watch(chatRealtimeProvider),
    ref,
    routeId,
  ),
);

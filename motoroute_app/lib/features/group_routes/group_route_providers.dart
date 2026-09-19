import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/chat_providers.dart';
import '../chat/data/chat_realtime.dart';
import '../chat/data/chat_repository.dart' show ChatMessage;
import 'group_route_repository.dart';

/// Lädt die Detailansicht einer gemeinsamen Route und hält sie aktuell:
/// WS-Events der anderen Mitglieder + dediziertes Nachladen der Metriken
/// nach Recalc (Abschnitt 12/27). Optimistische Updates für Stopps mit
/// serverseitigem Rollback bei Verweigerung (Abschnitt 14).
class GroupRouteDetailController extends StateNotifier<AsyncValue<GroupRouteDetail>> {
  final GroupRouteRepository _repo;
  final Ref _ref;
  final String routeId;

  StreamSubscription<ChatMessage>? _msgSub;
  bool _loaded = false;

  GroupRouteDetailController(this._repo, ChatRealtimeClient realtime, this._ref, this.routeId)
      : super(const AsyncValue.loading()) {
    // Echtzeit (Abschnitt 12/27): WS-Events zu dieser Route -> Nachladen.
    realtime.grouprouteEvents.listen((event) {
      if (event.routeId == routeId && !_disposed) refreshFromRealtime();
    });
  }

  bool _disposed = false;

  String? get _token => _ref.read(chatSessionTokenProvider);

  Future<void> load({bool force = false}) async {
    final token = _token;
    if (token == null) {
      state = AsyncValue.error('Nicht angemeldet', StackTrace.current);
      return;
    }
    if (_loaded && !force) return;
    _loaded = true;
    try {
      final detail = await _repo.get(token, routeId);
      state = AsyncValue.data(detail);
    } catch (e) {
      state = AsyncValue.error(_repo.mapError(e).message, StackTrace.current);
    }
  }

  /// WS-Ereignisse anderer Mitglieder -> Nachladen (throttled). Wird vom
  /// Screen per ref.listen an das connection/messages-Stream gehängt;
  /// hier zentral: die Deletion/Reorder/Add-Events erreichen uns über den
  /// Chat-WS-Strom (grouproute.*-Events) - der Client filtert auf routeId.
  Future<void> refreshFromRealtime() async {
    if (state.isLoading) return;
    await load(force: true);
  }

  // ------------------------------------------------------------- Stopps

  /// Optimistisch einfügen, serverseitig bestätigen, dann Metriken
  /// nachziehen (Backend recalculated asynchron).
  Future<String?> addStop(RouteStop candidate) async {
    final token = _token;
    if (token == null) return null;
    try {
      final stopId = await _repo.addStop(
        token,
        routeId,
        lat: candidate.lat,
        lng: candidate.lng,
        name: candidate.name,
        category: candidate.category,
        description: candidate.description,
        address: candidate.address,
      );
      await load(force: true);
      return stopId;
    } catch (e) {
      state = AsyncValue.error(_repo.mapError(e).message, StackTrace.current);
      return null;
    }
  }

  Future<void> deleteStop(String stopId) async {
    final token = _token;
    if (token == null) return;
    // Optimistisch entfernen (Abschnitt 14: optimistic updates).
    final previous = state.valueOrNull;
    if (previous != null) {
      state = AsyncValue.data(GroupRouteDetail(
        route: previous.route,
        stops: previous.stops.where((s) => s.id != stopId).toList(growable: false),
        history: previous.history,
      ));
    }
    try {
      await _repo.deleteStop(token, stopId);
      await load(force: true);
    } catch (e) {
      if (previous != null) state = AsyncValue.data(previous); // Rollback
      state = AsyncValue.error(_repo.mapError(e).message, StackTrace.current);
    }
  }

  /// Reihenfolge serverseitig setzen (Abschnitt 9) - das Backend validiert
  /// die Vollständigkeit der Liste (STOP_LIST_MISMATCH bei Konflikt).
  Future<void> reorder(List<RouteStop> reordered) async {
    final token = _token;
    if (token == null) return;
    final previous = state.valueOrNull;
    if (previous != null) {
      state = AsyncValue.data(GroupRouteDetail(
        route: previous.route,
        stops: reordered,
        history: previous.history,
      ));
    }
    try {
      await _repo.reorder(token, routeId, reordered.map((s) => s.id).toList());
      await load(force: true);
    } catch (e) {
      if (previous != null) state = AsyncValue.data(previous);
      state = AsyncValue.error(_repo.mapError(e).message, StackTrace.current);
    }
  }

  // -------------------------------------------------- Status/Rechte/Sperre

  Future<void> setStatus(GroupRouteStatus status) async {
    final token = _token;
    if (token == null) return;
    try {
      await _repo.setStatus(token, routeId, status);
      await load(force: true);
    } catch (e) {
      state = AsyncValue.error(_repo.mapError(e).message, StackTrace.current);
    }
  }

  Future<void> setPermission(EditingPermission permission) async {
    final token = _token;
    if (token == null) return;
    try {
      await _repo.setPermission(token, routeId, permission);
      await load(force: true);
    } catch (e) {
      state = AsyncValue.error(_repo.mapError(e).message, StackTrace.current);
    }
  }

  Future<void> lock() async {
    final token = _token;
    if (token == null) return;
    try {
      await _repo.lock(token, routeId);
      await load(force: true);
    } catch (e) {
      state = AsyncValue.error(_repo.mapError(e).message, StackTrace.current);
    }
  }

  Future<void> unlock() async {
    final token = _token;
    if (token == null) return;
    try {
      await _repo.unlock(token, routeId);
      await load(force: true);
    } catch (e) {
      state = AsyncValue.error(_repo.mapError(e).message, StackTrace.current);
    }
  }

  Future<void> duplicate(String? newName) async {
    final token = _token;
    if (token == null) return;
    try {
      await _repo.duplicate(token, routeId, newName: newName);
    } catch (e) {
      state = AsyncValue.error(_repo.mapError(e).message, StackTrace.current);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _msgSub?.cancel();
    super.dispose();
  }
}

final groupRouteDetailProvider = StateNotifierProvider.family<
    GroupRouteDetailController, AsyncValue<GroupRouteDetail>, String>(
  (ref, routeId) => GroupRouteDetailController(
    ref.watch(groupRouteRepositoryProvider),
    ref.watch(chatRealtimeProvider),
    ref,
    routeId,
  ),
);

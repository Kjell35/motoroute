import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_providers.dart';
import 'ride_history_repository.dart';

/// Privatsphäre-Einstellungen der Fahrhistorie.
///
/// Server ist die Wahrheit (PUT /v1/ride-history/privacy); der lokale
/// Spiegel (shared_preferences) dient nur der sofortigen UI-Rückmeldung
/// und dem Fall "Server gerade nicht erreichbar" - beim nächsten
/// App-Start wird vom Server geladen und der Spiegel korrigiert.
///
/// DEFAULTS = ALLES PRIVAT (authPrivacy 'private', share*-Flags aus,
/// hideStartEnd an): Ohne aktives Zutun verlässt kein Standort-Datum
/// das Gerät. rideHistoryEnabled betrifft nur die SERVERSEITige
/// Speicherung; das lokale Tagebuch bleibt davon unberührt.
class RideHistorySettings {
  final bool rideHistoryEnabled;
  final String authPrivacy; // 'private' | 'public'
  final bool shareRides;
  final bool sharePlaces;
  final bool hideStartEnd;
  final bool isLoading;
  final String? error;

  const RideHistorySettings({
    this.rideHistoryEnabled = true,
    this.authPrivacy = 'private',
    this.shareRides = false,
    this.sharePlaces = false,
    this.hideStartEnd = true,
    this.isLoading = false,
    this.error,
  });

  bool get isPublic => authPrivacy == 'public';

  RideHistorySettings copyWith({
    bool? rideHistoryEnabled,
    String? authPrivacy,
    bool? shareRides,
    bool? sharePlaces,
    bool? hideStartEnd,
    bool? isLoading,
    String? error,
  }) =>
      RideHistorySettings(
        rideHistoryEnabled: rideHistoryEnabled ?? this.rideHistoryEnabled,
        authPrivacy: authPrivacy ?? this.authPrivacy,
        shareRides: shareRides ?? this.shareRides,
        sharePlaces: sharePlaces ?? this.sharePlaces,
        hideStartEnd: hideStartEnd ?? this.hideStartEnd,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class RideHistorySettingsController extends StateNotifier<RideHistorySettings> {
  RideHistorySettingsController(this._ref) : super(const RideHistorySettings());

  final Ref _ref;

  static const _kPrefsKey = 'rideHistory.privacy';

  /// Beim App-Start: lokalen Spiegel laden, dann Server-Stand holen
  /// (best-effort - ohne Netz bleiben die lokalen Werte).
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsKey);
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        state = RideHistorySettings(
          rideHistoryEnabled: j['rideHistoryEnabled'] as bool? ?? true,
          authPrivacy: j['authPrivacy'] as String? ?? 'private',
          shareRides: j['shareRides'] as bool? ?? false,
          sharePlaces: j['sharePlaces'] as bool? ?? false,
          hideStartEnd: j['hideStartEnd'] as bool? ?? true,
        );
      } catch (_) {}
    }

    final token = _ref.read(authControllerProvider.notifier).accessToken;
    if (token == null) return;
    try {
      final server = await _ref.read(rideHistoryRepositoryProvider).fetchMySettings(token);
      state = RideHistorySettings(
        rideHistoryEnabled: server.rideHistoryEnabled,
        authPrivacy: server.authPrivacy,
        shareRides: server.shareRides,
        sharePlaces: server.sharePlaces,
        hideStartEnd: server.hideStartEnd,
      );
      await _mirror(prefs);
    } catch (_) {
      // Offline: lokaler Spimmel bleibt.
    }
  }

  Future<void> _mirror(SharedPreferences prefs) async {
    await prefs.setString(
      _kPrefsKey,
      jsonEncode({
        'rideHistoryEnabled': state.rideHistoryEnabled,
        'authPrivacy': state.authPrivacy,
        'shareRides': state.shareRides,
        'sharePlaces': state.sharePlaces,
        'hideStartEnd': state.hideStartEnd,
      }),
    );
  }

  /// Einen Schalter ändern: optimistisch lokal setzen, dann an den
  /// Server; bei Fehlschlag zurückrollen und Fehler melden.
  Future<bool> update({
    bool? rideHistoryEnabled,
    String? authPrivacy,
    bool? shareRides,
    bool? sharePlaces,
    bool? hideStartEnd,
  }) async {
    final prev = state;
    state = state.copyWith(
      rideHistoryEnabled: rideHistoryEnabled,
      authPrivacy: authPrivacy,
      shareRides: shareRides,
      sharePlaces: sharePlaces,
      hideStartEnd: hideStartEnd,
      error: null,
    );
    await _mirror(await SharedPreferences.getInstance());

    final token = _ref.read(authControllerProvider.notifier).accessToken;
    if (token == null) {
      // Nicht angemeldet: nur lokal (wirkt erst nach Anmeldung serverseitig).
      return true;
    }
    try {
      await _ref.read(rideHistoryRepositoryProvider).updatePrivacy(
            token,
            rideHistoryEnabled: rideHistoryEnabled,
            authPrivacy: authPrivacy,
            shareRides: shareRides,
            sharePlaces: sharePlaces,
            hideStartEnd: hideStartEnd,
          );
      return true;
    } on DioException catch (e) {
      state = prev.copyWith(error: 'Server: ${e.response?.statusCode ?? 'offline'}');
      return false;
    } catch (_) {
      state = prev.copyWith(error: 'offline');
      return false;
    }
  }
}

final rideHistorySettingsProvider =
    StateNotifierProvider<RideHistorySettingsController, RideHistorySettings>((ref) {
  return RideHistorySettingsController(ref);
});

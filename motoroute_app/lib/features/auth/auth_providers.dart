import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../chat/chat_providers.dart';

/// App-weite Anmeldung (E-Mail/Passwort) gegen das eigene Backend
/// (POST /v1/auth/*). Sitzung entweder DAUERHAFT ("Gerät merken" -
/// shared_preferences, überlebt App-Neustarts) oder nur für die
/// laufende Session (In-Memory, beim nächsten Start wieder raus).
/// Die Merken-Frage wird BEI JEDER Anmeldung neu gestellt - nie
/// stillschweigend gespeichert.
///
/// Kopplung: Der gültige Access-Token wird in chatSessionTokenProvider
/// gespiegelt - der Chat (WS + REST) läuft dadurch automatisch mit,
/// ohne dass der Settings-Token-Kleber noch nötig ist.
enum AuthStep { idle, busy }

enum RememberAnswer { unspecified, remember, forget }

class AuthUser {
  final String id;
  final String email;
  final String? displayName;

  const AuthUser({required this.id, required this.email, this.displayName});

  String get name => (displayName?.isNotEmpty ?? false)
      ? displayName!
      : (email.split('@').first);

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: (json['id'] as String?) ?? '',
        email: (json['email'] as String?) ?? '',
        displayName: json['displayName'] as String?,
      );
}

class AuthState {
  final AuthUser? user;
  final AuthStep step;
  final String? error;

  const AuthState({this.user, this.step = AuthStep.idle, this.error});

  bool get isAuthenticated => user != null;
  bool get isBusy => step == AuthStep.busy;

  AuthState copyWith({AuthUser? user, AuthStep? step, String? error}) =>
      AuthState(user: user ?? this.user, step: step ?? this.step, error: error);
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

class AuthController extends StateNotifier<AuthState> {
  AuthController() : super(const AuthState());

  static const _kAccessToken = 'auth.accessToken';
  static const _kRefreshToken = 'auth.refreshToken';
  static const _kUser = 'auth.user';
  static const _kRemembered = 'auth.remembered';

  String? _accessToken;
  String? _refreshToken;
  Timer? _refreshTimer;

  String? get accessToken => _accessToken;

  /// Beim App-Start: gespeicherte DAUER-Sitzung wiederherstellen.
  /// Eine nur-sitzungsweite Anmeldung (ohne "Gerät merken") hinterlässt
  /// bewusst keine Persistenz und ist nach Neustart weg.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final remembered = prefs.getBool(_kRemembered) ?? false;
    if (!remembered) return;
    final access = prefs.getString(_kAccessToken);
    final refresh = prefs.getString(_kRefreshToken);
    final userJson = prefs.getString(_kUser);
    if (access == null || refresh == null || userJson == null) return;

    try {
      final user = AuthUser.fromJson(
        Map<String, dynamic>.from(jsonDecode(userJson) as Map),
      );
      _accessToken = access;
      _refreshToken = refresh;
      state = AuthState(user: user);
      _scheduleRefresh();
    } catch (_) {
      await _clearPersisted(prefs);
    }
  }

  /// Login ODER Registrierung. [remember] entscheidet über Persistenz -
  /// der Aufrufer (Login-Screen) fragt bei jeder Anmeldung frisch.
  Future<void> authenticate({
    required String email,
    required String password,
    required bool remember,
    bool register = false,
    String? displayName,
  }) async {
    state = const AuthState(step: AuthStep.busy);
    final dio = ApiClient.create();
    try {
      final response = await dio.post<Map<String, dynamic>>(
        register ? '/v1/auth/register' : '/v1/auth/login',
        data: {
          'email': email,
          'password': password,
          if (register && displayName != null && displayName.isNotEmpty)
            'displayName': displayName,
        },
      );
      final data = response.data;
      if (data == null) throw AuthException('Ungültige Serverantwort');

      final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>? ?? {});
      _accessToken = data['accessToken'] as String?;
      _refreshToken = data['refreshToken'] as String?;
      if (_accessToken == null || _refreshToken == null) {
        throw AuthException('Ungültige Serverantwort');
      }

      final prefs = await SharedPreferences.getInstance();
      if (remember) {
        await prefs.setBool(_kRemembered, true);
        await prefs.setString(_kAccessToken, _accessToken!);
        await prefs.setString(_kRefreshToken, _refreshToken!);
        await prefs.setString(_kUser, jsonEncode({
          'id': user.id,
          'email': user.email,
          'displayName': user.displayName,
        }));
      } else {
        await _clearPersisted(prefs);
      }

      state = AuthState(user: user);
      _scheduleRefresh();
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final data = e.response?.data;
      String message;
      if (code == 401) {
        message = register
            ? 'Registrierung abgelehnt - prüfe die Angaben'
            : 'E-Mail oder Passwort falsch';
      } else if (code == 409) {
        message = 'Diese E-Mail ist bereits registriert';
      } else if (code == 503) {
        message = 'Anmeldung auf diesem Server nicht verfügbar';
      } else if (data is Map && data['message'] is String) {
        message = data['message'] as String;
      } else {
        message = 'Server nicht erreichbar - Verbindung prüfen';
      }
      state = AuthState(error: message);
      throw AuthException(message);
    } on AuthException {
      rethrow;
    } catch (_) {
      state = const AuthState(error: 'Anmeldung fehlgeschlagen');
      throw AuthException('Anmeldung fehlgeschlagen');
    }
  }

  /// Silent-Refresh: kurz vor Ablauf den Access-Token erneuern. Scheitert
  /// es (Server weg, Refresh abgelaufen), bleibt die lokale Sitzung
  /// bestehen - der nächste Request läuft in einen 401 und der Nutzer
  /// meldet sich ggf. neu an.
  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(minutes: 50), _refreshSilently);
  }

  Future<void> _refreshSilently() async {
    final refresh = _refreshToken;
    if (refresh == null || !state.isAuthenticated) return;
    try {
      final dio = ApiClient.create();
      final response = await dio.post<Map<String, dynamic>>(
        '/v1/auth/refresh',
        data: {'refreshToken': refresh},
      );
      final data = response.data;
      if (data != null) {
        _accessToken = data['accessToken'] as String?;
        _refreshToken = data['refreshToken'] as String?;
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool(_kRemembered) ?? false) {
          await prefs.setString(_kAccessToken, _accessToken!);
          await prefs.setString(_kRefreshToken, _refreshToken!);
        }
      }
      _scheduleRefresh();
    } catch (_) {
      _scheduleRefresh();
    }
  }

  /// Persistiert die LAUFENDE Sitzung - aufgerufen, wenn der Nutzer im
  /// Dialog "Gerät merken?" (nach dem Login) mit Ja antwortet. Kein
  /// zweiter Server-Call nötig; ohne Antwort bleibt die Sitzung rein
  /// In-Memory und endet mit dem App-Neustart.
  Future<void> persistCurrentSession() async {
    final access = _accessToken;
    final refresh = _refreshToken;
    final user = state.user;
    if (access == null || refresh == null || user == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRemembered, true);
    await prefs.setString(_kAccessToken, access);
    await prefs.setString(_kRefreshToken, refresh);
    await prefs.setString(
      _kUser,
      jsonEncode({'id': user.id, 'email': user.email, 'displayName': user.displayName}),
    );
  }

  /// Anzeigename serverseitig ändern (PUT /v1/users/me). Das Backend
  /// validiert den JWT - die User-ID kommt nie aus dem Body.
  Future<void> updateDisplayName(String displayName) async {
    final token = _accessToken;
    if (token == null) throw AuthException('Nicht angemeldet');
    await ApiClient.create().put(
      '/v1/users/me',
      data: {'displayName': displayName},
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final user = state.user;
    if (user != null) {
      state = state.copyWith(user: AuthUser(id: user.id, email: user.email, displayName: displayName));
    }
  }

  /// Passwort ändern. Das Backend verifiziert das aktuelle Passwort per
  /// echtem GoTrue-Login (401 bei falsch) und ändert dann per Admin-API.
  Future<void> changePassword(String currentPassword, String newPassword) async {
    final token = _accessToken;
    if (token == null) throw AuthException('Nicht angemeldet');
    try {
      await ApiClient.create().post(
        '/v1/users/me/password',
        data: {'currentPassword': currentPassword, 'newPassword': newPassword},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401) throw AuthException('Aktuelles Passwort ist falsch');
      if (status == 400) {
        throw AuthException('Das neue Passwort muss mindestens 8 Zeichen lang sein');
      }
      throw AuthException('Server nicht erreichbar - bitte später erneut versuchen');
    }
  }

  /// Konto ENDGÜLTIG löschen (auth.users + alle Profil-/Chat-/Gruppen-
  /// Zeilen per Cascade) und lokal abmelden. Rückfragen macht die UI.
  Future<void> deleteAccount() async {
    final token = _accessToken;
    if (token == null) throw AuthException('Nicht angemeldet');
    try {
      await ApiClient.create().delete(
        '/v1/users/me',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      throw AuthException(
          e.response?.statusCode == 503
              ? 'Server nicht konfiguriert - Konto konnte nicht gelöscht werden'
              : 'Löschen fehlgeschlagen - bitte später erneut versuchen');
    }
    await logout();
  }

  /// Abmelden: Server informieren (best-effort), lokale Persistenz
  /// UND In-Memory-Sitzung verwerfen.
  Future<void> logout() async {
    _refreshTimer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await _clearPersisted(prefs);
    final token = _accessToken;
    _accessToken = null;
    _refreshToken = null;
    state = const AuthState();
    if (token != null) {
      try {
        await ApiClient.create().post('/v1/auth/logout');
      } catch (_) {
        // Server-Weg ist best-effort - lokal ist die Sitzung weg.
      }
    }
  }

  Future<void> _clearPersisted(SharedPreferences prefs) async {
    await prefs.remove(_kRemembered);
    await prefs.remove(_kAccessToken);
    await prefs.remove(_kRefreshToken);
    await prefs.remove(_kUser);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController();
});

/// Brücke Auth -> Chat: spiegelt den Access-Token in den Chat-Session-
/// Provider (WS + REST laufen automatisch mit) und meldet den Chat beim
/// Logout ab. Die Chat-Schicht bleibt nichtswissend - der Token kommt
/// aus EINEM Store (Architekturregel). In der HomeShell beobachtet.
final authChatBridgeProvider = Provider<void>((ref) {
  ref.listen<AuthState>(authControllerProvider, (prev, next) {
    ref.read(chatSessionTokenProvider.notifier).state =
        next.user != null
            ? ref.read(authControllerProvider.notifier).accessToken
            : null;
  });
});

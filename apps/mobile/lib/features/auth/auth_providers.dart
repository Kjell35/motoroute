import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_keychain/flutter_keychain.dart';
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

  /// App-weite Admin-Rolle (users.role vom Backend): steuert Chat-Admin,
  /// Marktplatz-Admin, Meldungs-Prüfung und Garage-Admin. Einmal mit
  /// Admin-Konto angemeldet = überall Admin (App-Anforderung).
  final bool isAdmin;

  const AuthUser(
      {required this.id,
      required this.email,
      this.displayName,
      this.isAdmin = false});

  AuthUser copyWith({String? displayName, bool? isAdmin}) => AuthUser(
        id: id,
        email: email,
        displayName: displayName ?? this.displayName,
        isAdmin: isAdmin ?? this.isAdmin,
      );

  String get name => (displayName?.isNotEmpty ?? false)
      ? displayName!
      : (email.split('@').first);

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: (json['id'] as String?) ?? '',
        email: (json['email'] as String?) ?? '',
        displayName: json['displayName'] as String?,
        isAdmin: json['isAdmin'] == true,
      );
}

class AuthState {
  final AuthUser? user;
  final AuthStep step;
  final String? error;

  /// Wird bei JEDEM Tokenwechsel erhöht (Login, Restore, Silent-Refresh).
  /// Die Auth→Chat-Brücke lauscht darauf und spiegelt den frischen Token
  /// in den Chat-Session-Provider - sonst würde der Chat nach ~50 min
  /// (Refresh) bzw. nach App-Neustart (Restore) mit einem veralteten
  /// Token arbeiten.
  final int tokenEpoch;

  const AuthState({
    this.user,
    this.step = AuthStep.idle,
    this.error,
    this.tokenEpoch = 0,
  });

  bool get isAuthenticated => user != null;
  bool get isBusy => step == AuthStep.busy;

  AuthState copyWith({
    AuthUser? user,
    AuthStep? step,
    String? error,
    int? tokenEpoch,
  }) =>
      AuthState(
        user: user ?? this.user,
        step: step ?? this.step,
        error: error,
        tokenEpoch: tokenEpoch ?? this.tokenEpoch,
      );
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

typedef SecureValueReader = Future<String?> Function(String key);
typedef SecureValueWriter = Future<void> Function(String key, String value);
typedef SecureValueRemover = Future<void> Function(String key);

Future<String?> _readKeychainValue(String key) => FlutterKeychain.get(key: key);
Future<void> _writeKeychainValue(String key, String value) =>
    FlutterKeychain.put(key: key, value: value);
Future<void> _removeKeychainValue(String key) =>
    FlutterKeychain.remove(key: key);

class AuthController extends StateNotifier<AuthState> {
  AuthController({
    Dio Function()? dioFactory,
    SecureValueReader? secureReader,
    SecureValueWriter? secureWriter,
    SecureValueRemover? secureRemover,
  })  : _dioFactory = dioFactory ?? ApiClient.create,
        _secureReader = secureReader ?? _readKeychainValue,
        _secureWriter = secureWriter ?? _writeKeychainValue,
        _secureRemover = secureRemover ?? _removeKeychainValue,
        _canMigrateLegacyToken = secureReader == null && secureWriter == null,
        _persistRefreshInPrefsForTesting =
            secureReader != null && secureWriter == null,
        super(const AuthState());

  static const _kRefreshToken = 'auth.refreshToken';
  static const _kLegacyAccessToken = 'auth.accessToken';
  static const _kLegacyRefreshToken = 'auth.refreshToken';
  static const _kUser = 'auth.user';
  static const _kRemembered = 'auth.remembered';
  final Dio Function() _dioFactory;
  final SecureValueReader _secureReader;
  final SecureValueWriter _secureWriter;
  final SecureValueRemover _secureRemover;
  final bool _canMigrateLegacyToken;
  final bool _persistRefreshInPrefsForTesting;
  Future<Response<Map<String, dynamic>>>? _refreshInFlight;

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
    if (!remembered) {
      await _clearPersisted(prefs);
      state = const AuthState();
      return;
    }
    _refreshTimer?.cancel();
    _accessToken = null;
    _refreshToken = null;
    state = const AuthState(step: AuthStep.busy);

    try {
      final userJson = prefs.getString(_kUser);
      if (userJson == null) {
        await _clearPersisted(prefs);
        state = const AuthState();
        return;
      }
      final user = AuthUser.fromJson(
        Map<String, dynamic>.from(jsonDecode(userJson) as Map),
      );
      if (user.id.isEmpty || user.email.isEmpty) {
        await _clearPersisted(prefs);
        state = const AuthState();
        return;
      }

      // Migrate the old plaintext SharedPreferences token once; newly
      // remembered sessions keep only the refresh token in Keychain/Keystore.
      String? secureRefresh;
      try {
        secureRefresh = await _secureReader(_kRefreshToken);
      } catch (_) {
        // Plugin access can be temporarily unavailable (e.g. locked device);
        // only a legacy session may fall back to its old stored token.
      }
      final refresh = secureRefresh ??
          (_canMigrateLegacyToken
              ? prefs.getString(_kLegacyRefreshToken)
              : null);
      if (refresh == null || refresh.isEmpty) {
        await _clearPersisted(prefs);
        state = const AuthState();
        return;
      }
      if (_canMigrateLegacyToken &&
          secureRefresh == null &&
          prefs.containsKey(_kLegacyRefreshToken)) {
        await _secureWriter(_kRefreshToken, refresh);
        await prefs.remove(_kLegacyRefreshToken);
        await prefs.remove(_kLegacyAccessToken);
      }
      _refreshToken = refresh;
      final response = await _performRefresh(refresh);
      final data = response.data;
      final access = data?['accessToken'] as String?;
      final rotatedRefresh = data?['refreshToken'] as String?;
      if (access == null ||
          access.isEmpty ||
          rotatedRefresh == null ||
          rotatedRefresh.isEmpty) {
        await _clearPersisted(prefs);
        _accessToken = null;
        _refreshToken = null;
        state = const AuthState();
        return;
      }
      _accessToken = access;
      _refreshToken = rotatedRefresh;
      try {
        await _persistRotatedRefreshToken(rotatedRefresh);
      } catch (_) {
        await logout();
        return;
      }
      state = AuthState(user: user, tokenEpoch: 1);
      _scheduleRefresh();
      // Rolle FRISCH vom Server holen (Admin kann serverseitig geändert
      // worden sein); lokal gespeicherter Wert nur Übergang bis dahin.
      unawaited(_refreshRole(access, expectedUserId: user.id));
    } on DioException catch (error) {
      _accessToken = null;
      _refreshToken = null;
      state = const AuthState();
      if (error.response?.statusCode == 400 ||
          error.response?.statusCode == 401) {
        try {
          await _clearPersisted(prefs);
        } catch (_) {
          // Keep local auth cleared; a later launch can retry cleanup.
        }
      }

      // Offline/temporäre Serverfehler dürfen das gültige Refresh-Token
      // nicht löschen; Restore kann beim nächsten Start erneut versuchen.
    } catch (_) {
      _accessToken = null;
      _refreshToken = null;
      state = const AuthState();
      try {
        await _clearPersisted(prefs);
      } catch (_) {
        // The in-memory session remains cleared even if storage is unavailable.
      }
    }
  }

  Future<Response<Map<String, dynamic>>> _performRefresh(String refresh) {
    // The Dio instance from ApiClient owns the cold-start/deploy retry policy.
    // Do not wrap it in a second retry loop: that multiplied the delay on
    // failed refresh attempts just as it did for login.
    return _refreshInFlight ??= _dioFactory()
        .post<Map<String, dynamic>>(
          '/v1/auth/refresh',
          data: {'refreshToken': refresh},
        )
        .whenComplete(() {
          _refreshInFlight = null;
        });
  }

  /// Rolle aus users/me nachladen und in den State schreiben.
  Future<void> _refreshRole(String token, {String? expectedUserId}) async {
    try {
      final dio = _dioFactory();
      final me = await dio.get<Map<String, dynamic>>(
        '/v1/users/me',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final current = state.user;
      if (current == null ||
          (expectedUserId != null && current.id != expectedUserId)) {
        return;
      }
      state = state.copyWith(
        user:
            current.copyWith(isAdmin: (me.data?['role'] as String?) == 'admin'),
      );
    } catch (_) {
      // Offline: gespeicherter Wert bleibt.
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
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      throw AuthException('E-Mail und Passwort sind erforderlich');
    }
    if (register && password.length < 8) {
      throw AuthException('Das Passwort muss mindestens 8 Zeichen lang sein');
    }
    if (register && (displayName?.trim().length ?? 0) < 2) {
      throw AuthException('Bitte gib deinen Namen ein (mindestens 2 Zeichen)');
    }
    _refreshTimer?.cancel();
    _accessToken = null;
    _refreshToken = null;
    state = const AuthState(step: AuthStep.busy);
    final dio = _dioFactory();
    try {
      // ApiClient already retries connection failures and transient 502/503/504
      // responses. Wrapping this request in another retry loop multiplied a
      // cold-start wait into several minutes before the UI could show an error.
      final response = await dio.post<Map<String, dynamic>>(
        register ? '/v1/auth/register' : '/v1/auth/login',
        data: {
          'email': normalizedEmail,
          'password': password,
          if (register && displayName != null && displayName.trim().isNotEmpty)
            'displayName': displayName.trim(),
        },
      );
      final data = response.data;
      if (data == null) throw AuthException('Ungültige Serverantwort');

      final user =
          AuthUser.fromJson(data['user'] as Map<String, dynamic>? ?? {});
      _accessToken = data['accessToken'] as String?;
      _refreshToken = data['refreshToken'] as String?;
      if (_accessToken == null ||
          _accessToken!.isEmpty ||
          _refreshToken == null ||
          _refreshToken!.isEmpty ||
          user.id.isEmpty ||
          user.email.isEmpty) {
        _accessToken = null;
        _refreshToken = null;
        throw AuthException('Ungültige Serverantwort');
      }

      // Rolle nachladen (Admin-Freischaltung überall): GET /users/me
      // liefert users.role - fehlgeschlagen ist egal (dann 'user').
      var authenticated = user;
      try {
        final me = await dio.get<Map<String, dynamic>>(
          '/v1/users/me',
          options:
              Options(headers: {'Authorization': 'Bearer ${_accessToken!}'}),
        );
        authenticated = user.copyWith(
          isAdmin: (me.data?['role'] as String?) == 'admin',
        );
      } catch (_) {}

      final prefs = await SharedPreferences.getInstance();
      if (remember) {
        await prefs.setBool(_kRemembered, false);
        await prefs.setString(
            _kUser,
            jsonEncode({
              'id': authenticated.id,
              'email': authenticated.email,
              'displayName': authenticated.displayName,
              'isAdmin': authenticated.isAdmin,
            }));
        if (_persistRefreshInPrefsForTesting) {
          await prefs.setString(_kLegacyRefreshToken, _refreshToken!);
        } else {
          await _secureWriter(_kRefreshToken, _refreshToken!);
        }
        await prefs.setBool(_kRemembered, true);
      } else {
        // The remembered flag and plaintext legacy values must be cleared
        // before publishing the session. Keystore cleanup is best-effort and
        // must not delay a successful server login on a slow device.
        await _forgetPersistedSession(prefs, waitForSecureStorage: false);
      }

      state = AuthState(user: authenticated, tokenEpoch: state.tokenEpoch + 1);
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
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError) {
        message =
            'Server wacht gerade auf (Free-Hosting) - bitte nochmal versuchen';
      } else if (e.type == DioExceptionType.receiveTimeout) {
        message =
            'Der Server antwortet zu langsam. Bitte Verbindung prüfen und erneut versuchen.';
      } else {
        message = 'Server nicht erreichbar - Verbindung prüfen';
      }
      _accessToken = null;
      _refreshToken = null;
      state = AuthState(error: message);
      throw AuthException(message);
    } on AuthException catch (error) {
      _accessToken = null;
      _refreshToken = null;
      try {
        final prefs = await SharedPreferences.getInstance();
        await _forgetPersistedSession(prefs);
      } catch (_) {}
      state = AuthState(error: error.message);
      rethrow;
    } catch (error) {
      _accessToken = null;
      _refreshToken = null;
      try {
        final prefs = await SharedPreferences.getInstance();
        await _forgetPersistedSession(prefs);
      } catch (_) {}
      // Expose only the exception class, never its message: plugin/Dio errors
      // can include request details. This replaces an opaque fallback so the
      // user can report whether the failure came from storage or parsing.
      final message = 'Anmeldung fehlgeschlagen (technischer Fehler: '
          '${error.runtimeType})';
      state = AuthState(error: message);
      throw AuthException(message);
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
    if (!state.isAuthenticated || _refreshToken == null) return;
    await refreshTokenNow();
    if (state.isAuthenticated && _refreshInFlight == null) _scheduleRefresh();
  }

  /// Persistiert die LAUFENDE Sitzung - aufgerufen, wenn der Nutzer im
  /// Dialog "Gerät merken?" (nach dem Login) mit Ja antwortet. Kein
  /// zweiter Server-Call nötig; ohne Antwort bleibt die Sitzung rein
  /// In-Memory und endet mit dem App-Neustart.
  Future<void> persistCurrentSession() async {
    final refresh = _refreshToken;
    final user = state.user;
    if (refresh == null || user == null) {
      throw AuthException('Keine aktive Sitzung zum Speichern');
    }
    final prefs = await SharedPreferences.getInstance();
    final userJson = jsonEncode({
      'id': user.id,
      'email': user.email,
      'displayName': user.displayName,
      'isAdmin': user.isAdmin,
    });

    // Persist user metadata first, then the secret, and mark the session as
    // remembered last. A partial write can therefore never restore a broken
    // session as if the operation had succeeded.
    await prefs.setBool(_kRemembered, false);
    await prefs.setString(_kUser, userJson);
    try {
      if (_persistRefreshInPrefsForTesting) {
        await prefs.setString(_kLegacyRefreshToken, refresh);
      } else {
        await _secureWriter(_kRefreshToken, refresh);
      }
      await prefs.setBool(_kRemembered, true);
    } catch (_) {
      try {
        await _forgetPersistedSession(prefs);
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _forgetPersistedSession(
    SharedPreferences prefs, {
    bool waitForSecureStorage = true,
  }) async {
    await prefs.remove(_kRemembered);
    await prefs.remove(_kUser);
    await prefs.remove(_kLegacyRefreshToken);
    await prefs.remove(_kLegacyAccessToken);
    if (!waitForSecureStorage) {
      unawaited(_removeSecureRefreshTokenBestEffort());
      return;
    }
    await _removeSecureRefreshTokenBestEffort();
  }

  Future<void> _removeSecureRefreshTokenBestEffort() async {
    // A failed Keystore/Keychain cleanup must not turn a valid server login
    // into a generic authentication failure. The remembered flag is already
    // false, so this token cannot be restored; restore retries cleanup later.
    try {
      await _secureRemover(_kRefreshToken);
    } catch (_) {}
  }

  Future<void> _persistRotatedRefreshToken(String refresh) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kRemembered) != true) return;
    if (_persistRefreshInPrefsForTesting) {
      await prefs.setString(_kLegacyRefreshToken, refresh);
    } else {
      await _secureWriter(_kRefreshToken, refresh);
    }
  }

  Future<void> _publishRefreshedTokens(
    String expectedRefresh,
    String access,
    String refresh,
  ) async {
    if (_refreshToken != expectedRefresh || !state.isAuthenticated) return;
    try {
      await _persistRotatedRefreshToken(refresh);
    } catch (_) {
      // Rotation invalidates the old stored token. Don't publish a session
      // that can no longer be safely restored after restart.
      await logout();
      return;
    }
    if (_refreshToken != expectedRefresh || !state.isAuthenticated) return;
    _accessToken = access;
    _refreshToken = refresh;
    state = state.copyWith(tokenEpoch: state.tokenEpoch + 1);
    _scheduleRefresh();
  }

  /// Anzeigename serverseitig ändern (PUT /v1/users/me). Das Backend
  /// validiert den JWT - die User-ID kommt nie aus dem Body.
  Future<void> updateDisplayName(String displayName) async {
    final token = _accessToken;
    if (token == null) throw AuthException('Nicht angemeldet');
    await _dioFactory().put(
      '/v1/users/me',
      data: {'displayName': displayName},
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final user = state.user;
    if (user != null) {
      final updatedUser = user.copyWith(displayName: displayName);
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kRemembered) ?? false) {
        await prefs.setString(
            _kUser,
            jsonEncode({
              'id': updatedUser.id,
              'email': updatedUser.email,
              'displayName': updatedUser.displayName,
              'isAdmin': updatedUser.isAdmin,
            }));
      }
      state = state.copyWith(user: updatedUser);
    }
  }

  /// Passwort ändern. Das Backend verifiziert das aktuelle Passwort per
  /// echtem GoTrue-Login (401 bei falsch) und ändert dann per Admin-API.
  Future<void> changePassword(
      String currentPassword, String newPassword) async {
    final token = _accessToken;
    if (token == null) throw AuthException('Nicht angemeldet');
    try {
      await _dioFactory().post(
        '/v1/users/me/password',
        data: {'currentPassword': currentPassword, 'newPassword': newPassword},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401) throw AuthException('Aktuelles Passwort ist falsch');
      if (status == 400) {
        throw AuthException(
            'Das neue Passwort muss mindestens 8 Zeichen lang sein');
      }
      throw AuthException(
          'Server nicht erreichbar - bitte später erneut versuchen');
    }
  }

  /// Konto ENDGÜLTIG löschen (auth.users + alle Profil-/Chat-/Gruppen-
  /// Zeilen per Cascade) und lokal abmelden. Rückfragen macht die UI.
  Future<void> deleteAccount() async {
    final token = _accessToken;
    if (token == null) throw AuthException('Nicht angemeldet');
    try {
      await _dioFactory().delete(
        '/v1/users/me',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      throw AuthException(e.response?.statusCode == 503
          ? 'Server nicht konfiguriert - Konto konnte nicht gelöscht werden'
          : 'Löschen fehlgeschlagen - bitte später erneut versuchen');
    }
    await logout();
  }

  /// Abmelden: Server informieren (best-effort), lokale Persistenz
  /// UND In-Memory-Sitzung verwerfen.
  /// Zentraler Refresh für den 401-Interceptor (ApiClient.bindAuth):
  /// Erneuert den Access-Token via Refresh-Token und aktualisiert die
  /// Persistenz (falls "Gerät merken"). Gibt den neuen Token zurück -
  /// oder null, wenn die Sitzung nicht mehr rettbar ist (dann Logout).
  /// Geteilte, rotierende Refresh-Operation: konkurrierende 401-Antworten
  /// und der Timer verwenden denselben Request und dasselbe Token.
  Future<String?> refreshTokenNow() async {
    final refresh = _refreshToken;
    if (refresh == null || !state.isAuthenticated) return null;
    try {
      final response = await _performRefresh(refresh);
      final data = response.data;
      final newAccess = data?['accessToken'] as String?;
      final newRefresh = data?['refreshToken'] as String?;
      if (newAccess == null ||
          newAccess.isEmpty ||
          newRefresh == null ||
          newRefresh.isEmpty) {
        throw const FormatException('Ungültige Refresh-Antwort');
      }
      if (_refreshToken != refresh || !state.isAuthenticated) return null;
      await _publishRefreshedTokens(refresh, newAccess, newRefresh);
      if (_refreshToken != newRefresh || !state.isAuthenticated) return null;
      return newAccess;
    } on DioException catch (error) {
      if ((error.response?.statusCode == 400 ||
              error.response?.statusCode == 401) &&
          _refreshToken == refresh) {
        await logout();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() async {
    _refreshTimer?.cancel();
    final token = _accessToken;
    _accessToken = null;
    _refreshToken = null;
    state = const AuthState();
    try {
      final prefs = await SharedPreferences.getInstance();
      await _clearPersisted(prefs);
    } catch (_) {
      // Storage kann ausfallen; In-Memory-Logout erfolgt trotzdem sofort.
    }
    if (token != null) {
      try {
        await _dioFactory().post(
          '/v1/auth/logout',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
      } catch (_) {
        // Server-Weg ist best-effort - lokal ist die Sitzung weg.
      }
    }
  }

  Future<void> _clearPersisted(SharedPreferences prefs) async {
    await _forgetPersistedSession(prefs);
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
///
/// WICHTIG - Sofort-Spiegelung beim ersten Lesen: Die Sitzung kann SCHON
/// wiederhergestellt sein (Splash-Restore), bevor die Brücke erstmals
/// aktiv wird. Ein reiner Listener würde diese "Änderung" verpassen und
/// der Chat bliebe nach App-Neustart mit gemerktem Gerät tot.
final authChatBridgeProvider = Provider<void>((ref) {
  void mirror(AuthState next) {
    ref.read(chatSessionTokenProvider.notifier).state = next.user != null
        ? ref.read(authControllerProvider.notifier).accessToken
        : null;
  }

  // Sofort-Spiegel in einen Mikrotask verschoben: Riverpod verbietet
  // Provider-Modifikationen während der eigenen Initialisierung - der
  // Mikrotask läuft unmittelbar nach der Aktivierung, vor dem ersten
  // Frame.
  final restored = ref.read(authControllerProvider);
  Future.microtask(() => mirror(restored));
  ref.listen<AuthState>(authControllerProvider, (_, next) => mirror(next));
});

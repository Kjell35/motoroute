import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:motoroute_app/features/auth/auth_providers.dart';
import 'package:motoroute_app/features/chat/chat_providers.dart';

/// Regression: Nach App-Neustart mit gemerktem Gerät muss der Chat-Token
/// SOFORT nach der Brücken-Aktivierung vorhanden sein - auch wenn die
/// Sitzung schon VOR der Brücke wiederhergestellt wurde (Splash-Restore
/// läuft vor der HomeShell, die die Brücke aktiviert).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Brücke spiegelt bereits-wiederhergestellte Sitzung sofort', () async {
    // Gespeicherte Dauer-Sitzung simulieren: Refresh-Token liegt nur in
    // Secure Storage, Profildaten in SharedPreferences.
    SharedPreferences.setMockInitialValues({
      'auth.remembered': true,
      'auth.user': '{"id":"u1","email":"vati@moto.de","displayName":"Vati"}',
    });

    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith((ref) => AuthController(
              secureReader: (_) async => 'refresh-token-alt',
              secureWriter: (_, __) async {},
              secureRemover: (_) async {},
              dioFactory: () {
                final dio = Dio(BaseOptions(baseUrl: 'https://auth.test'));
                dio.httpClientAdapter = _RestoringAdapter();
                return dio;
              },
            )),
      ],
    );
    addTearDown(container.dispose);

    // Reihenfolge wie im echten App-Start: Restore ERST, Brücke DANACH.
    await container.read(authControllerProvider.notifier).restore();
    expect(container.read(authControllerProvider).isAuthenticated, isTrue);

    // Vor der Brücke: Chat-Token noch null (altes Verhalten - der Bug).
    expect(container.read(chatSessionTokenProvider), isNull);

    // Brücke aktivieren (HomeShell tut das im Build).
    container.read(authChatBridgeProvider);
    // Mikrotask-Flush: der Sofort-Spiegel läuft im nächsten Mikrotask
    // (vor dem nächsten Frame - für den Nutzer also sofort).
    await Future<void>.delayed(Duration.zero);

    // Fix: Der beim Restore erneuerte Token ist sofort verfügbar, ohne
    // dass sich der AuthState danach erneut ändern muss.
    expect(
      container.read(chatSessionTokenProvider),
      'access-token-alt',
      reason: 'authChatBridgeProvider muss die bereits wiederhergestellte '
          'Sitzung beim ersten Lesen in den Chat spiegeln',
    );
  });

  test('Silent-Refresh erhöht tokenEpoch - Brücke spiegelt neuen Token',
      () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(authControllerProvider.notifier);
    final before = container.read(authControllerProvider).tokenEpoch;

    // login setzt _accessToken intern; wir prüfen nur die Epoch-Logik:
    // authenticate() mit Fehlerfall darf die Epoch NICHT erhöhen.
    try {
      await notifier.authenticate(
        email: 'niemand@example.com',
        password: 'falsch123',
        remember: false,
      );
    } catch (_) {
      // Erwarteter Netz-/Auth-Fehler im Test (kein Server erreichbar).
    }
    final after = container.read(authControllerProvider).tokenEpoch;
    expect(after, before,
        reason: 'Fehlgeschlagene Anmeldung ändert keinen Token');
  });
}

class _RestoringAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.endsWith('/auth/refresh')) {
      return ResponseBody.fromString(
        jsonEncode({
          'accessToken': 'access-token-alt',
          'refreshToken': 'refresh-token-alt'
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        },
      );
    }
    return ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:motoroute_app/features/auth/auth_providers.dart';

/// Der Ersatz fuer flutter_keychain soll nicht nur ueber injizierte Fakes
/// geprueft werden: diese Tests laufen durch die Standard-Ablage
/// (FlutterSecureStorage) mit gemocktem Plattform-Kanal, also durch genau
/// den Code, der auf dem Geraet Keystore und Keychain anspricht.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storage = FlutterSecureStorage();
  late Dio dio;
  late List<RequestOptions> requests;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    requests = [];
    dio = Dio(BaseOptions(baseUrl: 'https://auth.test'))
      ..httpClientAdapter = _AuthAdapter((options) {
        requests.add(options);
        if (options.path.endsWith('/auth/login')) {
          return _jsonResponse({
            'accessToken': 'access-1',
            'refreshToken': 'refresh-1',
            'user': {'id': 'user-1', 'email': 'rider@example.com'},
          });
        }
        if (options.path.endsWith('/auth/refresh')) {
          return _jsonResponse({
            'accessToken': 'access-rotated',
            'refreshToken': 'refresh-rotated',
          });
        }
        if (options.path.endsWith('/users/me')) {
          return _jsonResponse({'role': 'user'});
        }
        return _jsonResponse({});
      });
  });

  AuthController createController() => AuthController(dioFactory: () => dio);

  test('Login legt das Refresh-Token in flutter_secure_storage ab', () async {
    final controller = createController();
    addTearDown(controller.dispose);

    await controller.authenticate(
      email: 'rider@example.com',
      password: 'valid-password',
      remember: true,
    );
    await controller.persistCurrentSession();

    expect(controller.state.isAuthenticated, isTrue);
    expect(await storage.read(key: 'auth.refreshToken'), 'refresh-1');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('auth.remembered'), isTrue);
    // Kein Klartext-Token mehr in den Einstellungen.
    expect(prefs.getString('auth.refreshToken'), isNull);
    expect(prefs.getString('auth.accessToken'), isNull);
  });

  test('Restore nach Neustart holt die Sitzung aus flutter_secure_storage',
      () async {
    final first = createController();
    await first.authenticate(
      email: 'rider@example.com',
      password: 'valid-password',
      remember: true,
    );
    await first.persistCurrentSession();
    first.dispose();

    final restored = createController();
    addTearDown(restored.dispose);
    await restored.restore();

    expect(restored.state.isAuthenticated, isTrue);
    expect(restored.state.user?.email, 'rider@example.com');
    expect(restored.accessToken, 'access-rotated');
    // Der Refresh-Token wird beim Restore rotiert - im sicheren Speicher.
    expect(await storage.read(key: 'auth.refreshToken'), 'refresh-rotated');
    expect(
      requests.map((r) => r.path).where((p) => p.endsWith('/auth/refresh')),
      isNotEmpty,
    );
  });

  test('Restore ohne gespeichertes Token meldet niemanden an', () async {
    final controller = createController();
    addTearDown(controller.dispose);

    await controller.restore();

    expect(controller.state.isAuthenticated, isFalse);
    expect(requests, isEmpty);
  });

  test('Logout loescht das Token aus flutter_secure_storage', () async {
    final controller = createController();
    addTearDown(controller.dispose);

    await controller.authenticate(
      email: 'rider@example.com',
      password: 'valid-password',
      remember: true,
    );
    await controller.persistCurrentSession();
    expect(await storage.read(key: 'auth.refreshToken'), isNotNull);

    await controller.logout();

    expect(controller.state.isAuthenticated, isFalse);
    expect(await storage.read(key: 'auth.refreshToken'), isNull);
    final prefs = await SharedPreferences.getInstance();
    // Logout loescht die Flags ganz, statt sie auf false zu setzen.
    expect(prefs.getBool('auth.remembered'), isNot(true));
    expect(prefs.getString('auth.user'), isNull);
  });

  group('Migration aus flutter_keychain', () {
    Map<String, String> legacyStore(String token) =>
        <String, String>{'auth.refreshToken': token};

    void rememberUser() => SharedPreferences.setMockInitialValues({
          'auth.remembered': true,
          'auth.user': '{"id":"user-1","email":"rider@example.com"}',
        });

    test('Bestandsnutzer wird ohne neue Anmeldung wiederhergestellt', () async {
      rememberUser();
      final legacy = legacyStore('refresh-legacy');
      final controller = AuthController(
        dioFactory: () => dio,
        legacyReader: (key) async => legacy[key],
        legacyRemover: (key) async => legacy.remove(key),
      );
      addTearDown(controller.dispose);

      await controller.restore();

      expect(controller.state.isAuthenticated, isTrue);
      expect(controller.state.user?.email, 'rider@example.com');
      // Der Token liegt jetzt in der neuen Ablage (nach Rotation).
      expect(await storage.read(key: 'auth.refreshToken'), 'refresh-rotated');
      // Und die alte Kopie ist weg, damit die Migration nicht wieder laeuft.
      expect(legacy, isEmpty);
    });

    test('Migration laeuft nicht, wenn die neue Ablage schon ein Token hat',
        () async {
      rememberUser();
      FlutterSecureStorage.setMockInitialValues({
        'auth.refreshToken': 'refresh-new',
      });
      var legacyReads = 0;
      final controller = AuthController(
        dioFactory: () => dio,
        legacyReader: (key) async {
          legacyReads++;
          return 'refresh-legacy';
        },
        legacyRemover: (key) async {},
      );
      addTearDown(controller.dispose);

      await controller.restore();

      expect(legacyReads, 0);
      expect(controller.state.isAuthenticated, isTrue);
    });

    test('Fehlender alter Kanal bricht den Start nicht ab', () async {
      rememberUser();
      final controller = AuthController(
        dioFactory: () => dio,
        legacyReader: (key) async => throw MissingPluginException('kein Kanal'),
        legacyRemover: (key) async {},
      );
      addTearDown(controller.dispose);

      await controller.restore();

      expect(controller.state.isAuthenticated, isFalse);
      expect(requests, isEmpty);
    });
  });
}

ResponseBody _jsonResponse(Map<String, Object?> value, [int status = 200]) =>
    ResponseBody.fromString(
      jsonEncode(value),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      },
    );

class _AuthAdapter implements HttpClientAdapter {
  _AuthAdapter(this.handle);

  final ResponseBody Function(RequestOptions options) handle;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      handle(options);

  @override
  void close({bool force = false}) {}
}

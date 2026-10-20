import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:motoroute_app/features/auth/auth_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> secureValues;
  late List<RequestOptions> requests;
  late int refreshStatus;
  late Completer<void>? secureRemoveGate;
  late bool secureRemoveFails;
  late Dio dio;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureValues = {};
    requests = [];
    refreshStatus = 200;
    secureRemoveGate = null;
    secureRemoveFails = false;
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
          if (refreshStatus != 200) {
            return _jsonResponse({'detail': 'expired'}, refreshStatus);
          }
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

  AuthController createController() => AuthController(
        dioFactory: () => dio,
        secureReader: (key) async => secureValues[key],
        secureWriter: (key, value) async => secureValues[key] = value,
        secureRemover: (key) async {
          await secureRemoveGate?.future;
          if (secureRemoveFails) throw StateError('Keystore unavailable');
          secureValues.remove(key);
        },
      );

  test('login then remember stores only refresh token in secure storage',
      () async {
    final controller = createController();
    addTearDown(controller.dispose);

    await controller.authenticate(
      email: ' rider@example.com ',
      password: 'valid-password',
      remember: false,
    );
    expect(controller.state.isAuthenticated, isTrue);
    expect(requests.first.data, containsPair('email', 'rider@example.com'));

    await controller.persistCurrentSession();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('auth.remembered'), isTrue);
    expect(prefs.getString('auth.accessToken'), isNull);
    expect(prefs.getString('auth.refreshToken'), isNull);
    expect(secureValues['auth.refreshToken'], 'refresh-1');
    expect(jsonDecode(prefs.getString('auth.user')!)['id'], 'user-1');
  });

  test('slow secure cleanup does not hold a successful login open', () async {
    final gate = Completer<void>();
    secureRemoveGate = gate;
    final controller = createController();
    addTearDown(controller.dispose);

    await controller
        .authenticate(
          email: 'rider@example.com',
          password: 'valid-password',
          remember: false,
        )
        .timeout(const Duration(seconds: 1));

    expect(controller.state.isAuthenticated, isTrue);
    gate.complete();
  });

  test('secure-store cleanup failure does not reject valid login', () async {
    secureRemoveFails = true;
    final controller = createController();
    addTearDown(controller.dispose);

    await controller.authenticate(
      email: 'rider@example.com',
      password: 'valid-password',
      remember: false,
    );

    expect(controller.state.isAuthenticated, isTrue);
  });

  test('session-only restore clears stale remembered credentials', () async {
    secureValues['auth.refreshToken'] = 'stale-token';
    SharedPreferences.setMockInitialValues({
      'auth.accessToken': 'legacy-access',
      'auth.refreshToken': 'legacy-refresh',
      'auth.user': '{"id":"old-user","email":"old@example.com"}',
    });
    final controller = createController();
    addTearDown(controller.dispose);

    await controller.restore();

    final prefs = await SharedPreferences.getInstance();
    expect(controller.state.isAuthenticated, isFalse);
    expect(prefs.getString('auth.accessToken'), isNull);
    expect(prefs.getString('auth.refreshToken'), isNull);
    expect(prefs.getString('auth.user'), isNull);
    expect(secureValues, isEmpty);
    expect(requests, isEmpty);
  });

  test('restore rotates the secure refresh token before publishing session',
      () async {
    secureValues['auth.refreshToken'] = 'refresh-old';
    SharedPreferences.setMockInitialValues({
      'auth.remembered': true,
      'auth.user': '{"id":"user-1","email":"rider@example.com"}',
    });
    final controller = createController();
    addTearDown(controller.dispose);

    await controller.restore();

    expect(controller.state.isAuthenticated, isTrue);
    expect(controller.accessToken, 'access-rotated');
    expect(secureValues['auth.refreshToken'], 'refresh-rotated');
    expect(requests.where((request) => request.path.endsWith('/auth/refresh')),
        hasLength(1));
  });

  test('rejected restore token clears remembered session and secret', () async {
    secureValues['auth.refreshToken'] = 'refresh-expired';
    SharedPreferences.setMockInitialValues({
      'auth.remembered': true,
      'auth.user': '{"id":"user-1","email":"rider@example.com"}',
    });
    refreshStatus = 401;
    final controller = createController();
    addTearDown(controller.dispose);

    await controller.restore();

    final prefs = await SharedPreferences.getInstance();
    expect(controller.state.isAuthenticated, isFalse);
    expect(prefs.getBool('auth.remembered'), isNull);
    expect(secureValues, isEmpty);
  });

  test('logout clears a remembered secure session and server token', () async {
    secureValues['auth.refreshToken'] = 'refresh-1';
    SharedPreferences.setMockInitialValues({
      'auth.remembered': true,
      'auth.user': '{"id":"user-1","email":"rider@example.com"}',
    });
    final controller = createController();
    addTearDown(controller.dispose);
    await controller.restore();

    await controller.logout();

    final prefs = await SharedPreferences.getInstance();
    expect(controller.state.isAuthenticated, isFalse);
    expect(prefs.getBool('auth.remembered'), isNull);
    expect(secureValues, isEmpty);
    expect(requests.any((request) => request.path.endsWith('/auth/logout')),
        isTrue);
  });

  test('empty credentials are rejected before making a network request',
      () async {
    final controller = createController();
    addTearDown(controller.dispose);

    await expectLater(
      controller.authenticate(email: ' ', password: '', remember: false),
      throwsA(isA<AuthException>()),
    );
    expect(requests, isEmpty);
    expect(controller.state.isAuthenticated, isFalse);
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

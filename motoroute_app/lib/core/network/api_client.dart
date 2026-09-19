import 'package:dio/dio.dart';

/// Zentraler HTTP-Client für alle Repositories. Die Basis-URL zeigt
/// AUSSCHLIESSLICH auf das eigene Backend (motoroute_api) - kein
/// Drittanbieter-Key liegt jemals im App-Bundle, siehe
/// Systemarchitektur Phase 1/2 Teil C ("Kommunikationsprinzip").
///
/// `baseUrl` kommt bewusst nicht hartcodiert, sondern über
/// `--dart-define=API_BASE_URL=...` beim Build - siehe
/// docs/BUILD.md (folgt) für dev/staging/prod-Werte.
class ApiClient {
  ApiClient._();

  static Dio create() {
    const baseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:3000', // Android-Emulator -> localhost
    );

    return Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
  }
}

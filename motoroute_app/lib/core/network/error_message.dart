import 'package:dio/dio.dart';

import '../i18n/i18n.dart';

/// Technische Ursache eines Fehlers für die Anzeige in der UI.
/// Ziel: NIEMALS nur "Etwas ist schiefgelaufen" - der Screen zeigt die
/// echte Ursache (Timeout, HTTP 401/403, Server-Hinweis), damit der
/// Nutzer und der Support sofort wissen, welcher Bereich hakt.
String technicalCause(Object error) {
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
        // Render-Free-Tier: Der haeufigste Grund fuer einen Verbindungs-
        // Timeout ist der Kaltstart - der Server wacht gerade auf.
        return 'Server wacht gerade auf (Kaltstart) - Timeout beim Aufbau';
      case DioExceptionType.receiveTimeout:
        return 'Server wacht gerade auf (Kaltstart) - Timeout bei der Antwort';
      case DioExceptionType.connectionError:
        return 'Server wacht gerade auf (Kaltstart) - Server nicht erreichbar';
      case DioExceptionType.badCertificate:
        return 'Verbindung unsicher (Zertifikat abgelehnt)';
      case DioExceptionType.cancel:
        return 'Anfrage abgebrochen';
      default:
        break;
    }
    final status = error.response?.statusCode;
    final data = error.response?.data;
    String serverHint = '';
    if (data is Map) {
      final msg = (data['message'] ?? data['error'])?.toString() ?? '';
      if (msg.isNotEmpty && msg.length <= 80) serverHint = ' - $msg';
    }
    return switch (status) {
      400 => 'Ungültige Anfrage (HTTP 400)$serverHint',
      401 => 'HTTP 401 - Sitzung abgelaufen, bitte neu anmelden',
      403 => 'HTTP 403 - kein Zugriff für dieses Konto',
      404 => 'HTTP 404 - Endpunkt nicht gefunden',
      429 => 'HTTP 429 - zu viele Anfragen, kurz warten',
      // Render-Deploy-Fenster: Der Proxy antwortet mit Gateway-Fehlern,
      // waehrend die neue Version startet - kein echter Serverfehler.
      502 => 'Server startet gerade neu (HTTP 502) - gleich erneut versuchen',
      503 => 'Server startet gerade neu (HTTP 503) - gleich erneut versuchen',
      504 => 'Server startet gerade neu (HTTP 504) - gleich erneut versuchen',
      null => 'Keine Antwort vom Server',
      _ => 'HTTP $status - Serverfehler$serverHint',
    };
  }
  return 'Unerwarteter Fehler (${error.runtimeType})';
}

/// Zentrale Übersetzung technischer Fehler in kurze, verständliche
/// Meldungen (i18n). Ersetzt rohe DioException-Dumps in der UI.
String friendlyErrorMessage(Object error, I18n i18n) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    final data = error.response?.data;
    String code = '';
    if (data is Map) code = (data['error'] ?? data['message'] ?? '') as String;

    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return i18n.errNetwork;
      default:
        break;
    }
    if (status == 401) return i18n.errUnauthorized;
    if (status == 403) return i18n.errForbidden;
    if (status == 404) return i18n.errNotFound;
    if (status == 429) return i18n.errRateLimited;
    if (status != null && status >= 500) return i18n.errServer;
    if (code.isNotEmpty) return code;
    // Statt Pauschalmeldung immer die echte Ursache nennen.
    return technicalCause(error);
  }
  if (error is Exception) return i18n.errUnknown;
  return i18n.errUnknown;
}

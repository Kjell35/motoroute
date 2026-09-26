import 'package:dio/dio.dart';

import '../i18n/i18n.dart';

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
    return i18n.errUnknown;
  }
  if (error is Exception) return i18n.errUnknown;
  return i18n.errUnknown;
}

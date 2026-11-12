/// Eingabe-Helfer der Garage.
///
/// Bewusst frei von Flutter-Widgets und von `ref`: die Dialoge in
/// `garage_screen` und `garage_vehicle_screen` pruefen ihre Felder damit,
/// bevor eine Anfrage rausgeht. `null` heisst immer "keine Angabe" ODER
/// "nicht lesbar" - der Aufrufer unterscheidet das ueber den Feldtext,
/// damit ein leeres optionales Feld erlaubt bleibt.
library;

/// Einheitliche Garage-Fehlermeldung fuer Liste, Anlegen-Dialog und
/// Fahrzeug-Detail.
///
/// 401/AUTH heisst "Anmeldung abgelaufen"; sonst traegt der erste
/// Zeilen-Text der Server-Meldung die Ursache - Stacktraces und
/// DioException-Header sind fuer Nutzer unlesbar.
String garageMessageFor(
  Object? e, {
  required String loginFailed,
  required String unreachable,
}) {
  final msg = e.toString();
  if (msg.contains('GarageApiException') &&
      (msg.contains('401') || msg.contains('AUTH'))) {
    return loginFailed;
  }
  return '$unreachable: ${msg.split('\n').first}';
}

/// Liest den Kilometerstand (Tausenderpunkte und Leerzeichen erlaubt).
int? parseOdometerKm(String raw) {
  final cleaned = raw.trim().replaceAll('.', '').replaceAll(' ', '');
  if (cleaned.isEmpty) return null;
  final value = int.tryParse(cleaned);
  if (value == null || value < 0) return null;
  return value;
}

/// Liest das Baujahr; erlaubt ist 1900 bis [maxYear].
int? parseModelYear(String raw, {required int maxYear}) {
  final cleaned = raw.trim();
  if (cleaned.isEmpty) return null;
  final value = int.tryParse(cleaned);
  if (value == null) return null;
  if (value < 1900 || value > maxYear) return null;
  return value;
}

/// Liest ein Datum als `yyyy-MM-dd` oder `dd.MM.yyyy`.
///
/// Nicht existierende Tage wie der 31.02. werden abgelehnt statt von
/// `DateTime` still in den Folgemonat geschoben.
DateTime? parseGarageDate(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  int? year;
  int? month;
  int? day;
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
  if (iso != null) {
    year = int.parse(iso[1]!);
    month = int.parse(iso[2]!);
    day = int.parse(iso[3]!);
  } else {
    final german = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$').firstMatch(text);
    if (german == null) return null;
    day = int.parse(german[1]!);
    month = int.parse(german[2]!);
    year = int.parse(german[3]!);
  }

  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}

/// Formatiert ein Datum fuer die API (`yyyy-MM-dd`).
String isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Liest eine Dezimalzahl (Komma oder Punkt) - fuer Liter und Euro-Betraege.
double? parseDecimal(String raw) {
  final text = raw.trim().replaceAll(' ', '');
  if (text.isEmpty) return null;
  final value = double.tryParse(text.replaceAll(',', '.'));
  if (value == null || value < 0) return null;
  return value;
}

/// Prueft einen neuen Kilometerstand gegen den bisherigen Stand.
///
/// `null` = in Ordnung, sonst der Hinweistext fuer den Dialog. Ein
/// Rueckschritt wird abgelehnt: er wuerde Wartungsintervalle und den
/// Verbrauch verfaelschen.
String? odometerProblem(int? value, {required int currentKm}) {
  if (value == null) return 'Kilometerstand bitte als Zahl angeben.';
  if (value > 999999) {
    return 'Kilometerstand ist zu hoch (höchstens 999.999 km).';
  }
  if (value < currentKm) {
    return 'Der neue Stand darf nicht unter dem bisherigen ($currentKm km) liegen.';
  }
  return null;
}

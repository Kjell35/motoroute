/// Erlaubte Kategorien für `POST /v1/telemetry/errors`.
///
/// Der Server prüft die Kategorie gegen diese Liste und antwortet bei einem
/// unbekannten Wert mit 400. [ErrorReporter] verwirft 4xx-Berichte endgültig
/// (kein Retry, keine Warteschlange) – ein Tippfehler kostet damit still die
/// Diagnose genau des Features, das man gerade untersuchen will.
///
/// Deshalb ist die Server-Whitelist hier gespiegelt, und
/// `test/core/network/telemetry_categories_test.dart` prüft jeden
/// `ErrorReporter.report(...)`-Aufruf dagegen.
///
/// Stand: 24.11.2026, abgefragt über die Ablehnungsmeldung des Endpunkts.
/// Neue Kategorie? Zuerst serverseitig ergänzen, dann hier und im Aufruf –
/// sonst bricht der Test.
const Set<String> kTelemetryCategories = <String>{
  'crash',
  'chat.load',
  'chat.send',
  'chat.search',
  'chat.group',
  'chat.admin',
  'chat.other',
  'mp.load',
  'mp.create',
  'mp.other',
  'garage.connect',
  'garage.load',
  'garage.write',
  'garage.other',
  'routes.load',
  'map.style',
  'auth.cleanup',
  'auth.role',
  'bikerpoi.sync',
  'chat.mark_read',
  'garage.restore',
  'group_ride.load',
  'group_route.load',
  'group_route.poll',
  'location.permission',
  'mp.notifications',
  'navigation.session',
  'ride_history.settings',
  'settings.privacy',
  'tour_diary.load',
  'tour_diary.write',
  'tour_recorder.start',
  'voice.tts',
  'other',
};

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-weite Sprachwahl (DE/EN) mit Persistenz. Der Katalog deckt alle
/// nutzersichtbaren Strings der Haupt-Screens ab; die Screens holen
/// ihre Texte über [tr] mit dem aktuellen Locale.
///
/// Persistierung: shared_preferences (überlebt App-Neustarts) - die
/// Auswahl gilt GERÄTEWEIT, nicht nur pro Session.
enum AppLanguage { de, en }

AppLanguage _languageFromCode(String? code) =>
    code == 'en' ? AppLanguage.en : AppLanguage.de;

class I18n {
  final AppLanguage language;

  const I18n(this.language);

  Locale get locale =>
      language == AppLanguage.en ? const Locale('en') : const Locale('de');

  bool get isEnglish => language == AppLanguage.en;

  String get _k => isEnglish ? 'en' : 'de';

  /// Übersetzung mit Platzhalter-Support: tr('routeOf', {'a': 'X', 'b': 'Y'})
  String tr(String key, [Map<String, String>? params]) {
    var s = _catalog[_k]?[key] ?? _catalog['de']?[key] ?? key;
    params?.forEach((k, v) => s = s.replaceAll('{$k}', v));
    return s;
  }

  // ------------------------------------------------------------------
  // Bequeme Getter für häufige Texte (tippfehlerfrei gegen den Katalog).
  // ------------------------------------------------------------------
  String get mapTab => tr('tab.map');
  String get toursTab => tr('tab.tours');
  String get chatTab => tr('tab.chat');
  String get settingsTab => tr('tab.settings');
  String get languageLabel => tr('settings.language');
  String get themeModeTitle => tr('settings.themeMode');
  String get themeModeSystem => tr('settings.themeMode.system');
  String get themeModeLight => tr('settings.themeMode.light');
  String get themeModeDark => tr('settings.themeMode.dark');
  String get german => tr('settings.language.de');
  String get english => tr('settings.language.en');
  String get appearance => tr('settings.appearance');
  String get light => tr('settings.mapStyle.light');
  String get dark => tr('settings.mapStyle.dark');
  String get mapStyleTitle => tr('settings.mapStyle');
  String get testConnection => tr('settings.testConnection');
  String get serverSection => tr('settings.server');
  String get serverFixedNote => tr('settings.serverNote');
  String get account => tr('settings.account');
  String get profile => tr('settings.profile');
  String get changePassword => tr('settings.changePassword');
  String get deleteAccount => tr('settings.deleteAccount');
  String get logout => tr('settings.logout');
  String get privacy => tr('settings.privacy');
  String get imprint => tr('settings.imprint');
  String get about => tr('settings.about');
  String get appVersion => tr('settings.appVersion');
  String get chatAccount => tr('settings.chatAccount');
  String get chatAccountConnected => tr('settings.chatAccount.connected');
  String get chatAccountNotConnected => tr('settings.chatAccount.notConnected');
  String get showOnlineStatus => tr('settings.showOnline');
  String get chatNameSection => tr('settings.chatName');
  String get chatNameMode => tr('settings.chatName.mode');
  String get chatNameUsername => tr('settings.chatName.username');
  String get chatNameFirstName => tr('settings.chatName.firstName');
  String get chatNameCustom => tr('settings.chatName.custom');
  String get chatNameCustomLabel => tr('settings.chatName.customLabel');
  String get firstName => tr('settings.firstName');
  String get navigation => tr('settings.navigation');
  String get tabSettings => tr('tab.settings');
  String get save => tr('common.save');
  String get cancel => tr('common.cancel');
  String get ok => tr('common.ok');
  String get retry => tr('common.retry');
  String get loading => tr('common.loading');
  String get error => tr('common.error');

  // Suche & Routing
  String get searchHint => tr('search.hint');
  String get searchTitle => tr('search.title');
  String get searchWaypointTitle => tr('search.waypointTitle');
  String get routeStyleTitle => tr('route.styleTitle');
  String get avoid => tr('route.avoid');
  String get avoidHighway => tr('route.avoid.highway');
  String get avoidFerry => tr('route.avoid.ferry');
  String get avoidToll => tr('route.avoid.toll');
  String get distance => tr('route.distance');
  String get duration => tr('route.duration');
  String get eta => tr('route.eta');
  String get startNavigation => tr('route.startNavigation');
  String get overview => tr('route.overview');
  String get chooseStartTitle => tr('route.chooseStart.title');
  String get chooseStartGps => tr('route.chooseStart.gps');
  String get chooseStartGpsSub => tr('route.chooseStart.gpsSub');
  String get chooseStartAddress => tr('route.chooseStart.address');
  String get chooseStartAddressSub => tr('route.chooseStart.addressSub');
  String get noGpsFix => tr('route.chooseStart.noFix');
  String get waypoints => tr('route.waypoints');

  // Navigation
  String get navFollowRoute => tr('nav.followRoute');
  String get navEnd => tr('nav.end');
  String get navOffRoute => tr('nav.offRoute');
  String get navRerouting => tr('nav.rerouting');
  String get navMapOffline => tr('nav.mapOffline');

  // Auth
  String get login => tr('auth.login');
  String get register => tr('auth.register');
  String get email => tr('auth.email');
  String get password => tr('auth.password');
  String get displayNameField => tr('auth.displayName');
  String get rememberDevice => tr('auth.rememberDevice');
  String get logoutAction => tr('auth.logoutAction');

  // Chat
  String get chatPublic => tr('chat.public');
  String get chatPrivate => tr('chat.private');
  String get chatGroups => tr('chat.groups');
  String get chatMessageHint => tr('chat.messageHint');
  String get chatLoginRequired => tr('chat.loginRequired');
  String get chatLoginRequiredSub => tr('chat.loginRequiredSub');

  // Karte
  String get attribution => tr('map.attribution');
  String get mapOfflineNote => tr('map.offlineNote');
}

/// Riverpod-State: aktuelle Sprache, asynchron persistiert.
class LanguageController extends StateNotifier<AppLanguage> {
  LanguageController() : super(AppLanguage.de) {
    _restore();
  }

  static const _kKey = 'app.language';

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = _languageFromCode(prefs.getString(_kKey));
  }

  Future<void> set(AppLanguage language) async {
    state = language;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, language == AppLanguage.en ? 'en' : 'de');
  }
}

final languageControllerProvider =
    StateNotifierProvider<LanguageController, AppLanguage>((ref) {
  return LanguageController();
});

/// Der I18n-Katalog als Provider - Screens lesen DIREKT daraus (statt
/// watch auf die Sprache + Konstruktion): ref.watch(i18nProvider) baut
/// bei jedem Sprachwechsel neu und UI-Subtrees reagieren automatisch.
final i18nProvider = Provider<I18n>((ref) {
  return I18n(ref.watch(languageControllerProvider));
});

const _catalog = <String, Map<String, String>>{
  'de': {
    // Tabs
    'settings.languageAndAppearance': 'Sprache & Erscheinungsbild',
    'settings.saved': 'Gespeichert',
    'errors.saveFailed': 'Speichern fehlgeschlagen - bitte später erneut versuchen',
    'settings.themeMode': 'Erscheinungsbild (UI)',
    'settings.themeMode.system': 'Auto',
    'settings.themeMode.light': 'Hell',
    'settings.themeMode.dark': 'Dunkel',
    'settings.offlineMaps': 'Offline-Karten',
    'settings.offlineMaps.add': 'Region herunterladen',
    'settings.offlineMaps.addHint': 'Kartenbereich für offline Navigation speichern',
    'settings.offlineMaps.dialogTitle': 'Offline-Karte herunterladen',
    'settings.offlineMaps.radius': 'Radius um die aktuelle Position',
    'tab.map': 'Karte',
    'tab.tours': 'Touren',
    'tab.chat': 'Chat',
    'tab.settings': 'Einstellungen',
    // Common
    'common.save': 'Speichern',
    'common.cancel': 'Abbrechen',
    'common.ok': 'OK',
    'common.retry': 'Erneut versuchen',
    'common.loading': 'Lädt…',
    'common.error': 'Fehler',
    // Settings
    'settings.language': 'Sprache',
    'settings.language.de': 'Deutsch',
    'settings.language.en': 'English',
    'settings.appearance': 'Erscheinungsbild',
    'settings.mapStyle': 'Kartenstil',
    'settings.mapStyle.light': 'Hell (Standard)',
    'settings.mapStyle.dark': 'Dunkel',
    'settings.testConnection': 'Verbindung testen',
    'settings.server': 'Server & Verbindung',
    'settings.serverNote':
        'Verbindung fest konfiguriert - kein API-Key und keine URL nötig.',
    'settings.account': 'Konto',
    'settings.profile': 'Profil bearbeiten',
    'settings.changePassword': 'Passwort ändern',
    'settings.deleteAccount': 'Konto löschen',
    'settings.logout': 'Abmelden',
    'settings.privacy': 'Datenschutz',
    'settings.imprint': 'Impressum',
    'settings.about': 'Über MotoRoute',
    'settings.appVersion': 'App-Version',
    'settings.chatAccount': 'Chat-Konto',
    'settings.chatAccount.connected': 'Verbunden',
    'settings.chatAccount.notConnected': 'Nicht verbunden',
    'settings.showOnline': 'Online-Status anzeigen',
    'settings.chatName': 'Chat-Anzeigename',
    'settings.chatName.mode': 'Name in Chats',
    'settings.chatName.username': 'Benutzername',
    'settings.chatName.firstName': 'Vorname',
    'settings.chatName.custom': 'Benutzerdefinierter Anzeigename',
    'settings.chatName.customLabel': 'Eigener Anzeigename',
    'settings.firstName': 'Vorname',
    'settings.navigation': 'Navigation',
    'settings.notifications': 'Benachrichtigungen',
    'settings.mapPoiSection': 'Karte - POI-Kategorien',
    'settings.chatCommunity': 'Chat & Community',
    'settings.legal': 'Datenschutz & Recht',
    // Suche & Routing
    'search.hint': 'Ort, PLZ oder POI suchen',
    'search.title': 'Zielsuche',
    'search.waypointTitle': 'Wegpunkt suchen',
    'route.styleTitle': 'Fahrstil wählen',
    'route.avoid': 'Vermeiden',
    'route.avoid.highway': 'Autobahn',
    'route.avoid.ferry': 'Fähre',
    'route.avoid.toll': 'Maut',
    'route.distance': 'Distanz',
    'route.duration': 'Fahrzeit',
    'route.eta': 'Ankunft',
    'route.startNavigation': 'Navigation starten',
    'route.overview': 'Routenübersicht',
    'route.chooseStart.title': 'Wo startest du?',
    'route.chooseStart.gps': 'Aktueller Standort',
    'route.chooseStart.gpsSub': 'GPS-Position des Geräts verwenden',
    'route.chooseStart.address': 'Adresse eingeben',
    'route.chooseStart.addressSub': 'Ort, PLZ oder POI als Startpunkt',
    'route.chooseStart.noFix': 'Kein GPS-Fix - bitte Adresse wählen oder später erneut',
    'route.waypoints': 'Wegpunkte',
    // Navigation
    'nav.followRoute': 'Route folgen',
    'nav.end': 'Beenden',
    'nav.offRoute': 'Von der Route abgewichen',
    'nav.rerouting': 'Route wird angepasst…',
    'nav.mapOffline': 'Karte offline',
    // Auth
    'auth.login': 'Anmelden',
    'auth.register': 'Konto erstellen',
    'auth.email': 'E-Mail',
    'auth.password': 'Passwort',
    'auth.displayName': 'Anzeigename',
    'auth.rememberDevice': 'Gerät merken',
    'auth.logoutAction': 'Abmelden',
    'auth.welcomeRegister': 'Willkommen an Bord!',
    'auth.welcomeLogin': 'Willkommen zurück!',
    'auth.welcomeRegisterSub': 'Erstelle dein MotoRoute-Konto',
    'auth.welcomeLoginSub': 'Schön, dass du wieder fährst.',
    'auth.yourName': 'Dein Name (optional)',
    'auth.hasAccount': 'Ich habe schon ein Konto - Anmelden',
    'auth.newHere': 'Neu hier? Konto erstellen',
    'auth.browseWithoutAccount': 'Erstmal ohne Konto ansehen',
    'auth.rememberQuestion': 'Gerät merken?',
    'auth.rememberExplanation':
        'Wenn du das Gerät merkst, bleibst du nach einem App-Neustart angemeldet. Andernfalls musst du dich beim nächsten Start erneut anmelden.\n\nWir fragen dich bei jeder Anmeldung neu.',
    'auth.sessionOnly': 'Nur diese Sitzung',
    // Chat
    'chat.public': 'Öffentlich',
    'chat.private': 'Privat',
    'chat.groups': 'Gruppen',
    'chat.messageHint': 'Nachricht schreiben…',
    'chat.loginRequired': 'Zum Chatten anmelden',
    'chat.loginRequiredSub': 'Nach dem Login ist der Chat sofort verfügbar.',
    // Karte
    'map.attribution': '© OpenStreetMap-Mitwirkende © CARTO',
    'map.offlineNote': 'Karte offline - POIs, Routing und Navigation funktionieren weiter',
    // Tour-Tagebuch
    'tour.saveTitle': 'Tour speichern',
    'tour.saveHint': 'z. B. Alpenrunde mit Vati',
    'tour.discard': 'Verwerfen',
    'tour.empty.title': 'Noch keine Touren',
    'tour.empty.sub': 'Jede Navigation wird automatisch aufgezeichnet. Oder importiere eine GPX-Route von Calimoto oder Kurviger.',
    'tour.import.title': 'GPX importieren',
    'tour.import.intro': 'Wähle eine GPX-Datei - z. B. eine geplante Tour aus Calimoto oder Kurviger.',
    'tour.import.pick': 'GPX-Datei wählen',
    'tour.import.points': 'Punkte',
    'tour.import.ride': 'Diese Tour fahren',
    'tour.import.failed': 'Datei konnte nicht gelesen werden',
    'tour.summary.tours': 'Touren',
    'tour.summary.km': 'km',
    'tour.summary.hours': 'h',
    'tour.summary.elevation': 'Höhenmeter',
    // Fahrhistorie (Profil)
    'settings.rideHistory': 'Fahrhistorie & Privatsphäre',
    'rideHistory.requiresLogin': 'Melde dich an, um die Fahrhistorie zu nutzen. Bis dahin bleiben alle Daten privat.',
    'rideHistory.enabled': 'Fahrhistorie aufzeichnen',
    'rideHistory.publicProfile': 'Fahrhistorie öffentlich anzeigen',
    'rideHistory.shareRides': 'Gefahrene Strecken öffentlich anzeigen',
    'rideHistory.sharePlaces': 'Besuchte Orte öffentlich anzeigen',
    'rideHistory.hideStartEnd': 'Genaue Start-/Zielposition verbergen',
    'rideHistory.hintPrivate': 'Privat: Niemand sieht deine Touren oder Orte. Freigabe erfolgt nur per Schalter.',
    'rideHistory.hintPublic': 'Öffentlich: Andere sehen nur, was du oben freigibst. Profil komplett privat = Hauptschalter aus.',
    'rideHistory.title': 'Fahrhistorie',
    'rideHistory.loadError': 'Historie konnte nicht geladen werden',
    'rideHistory.retry': 'Erneut versuchen',
    'rideHistory.private': 'Privates Profil',
    'rideHistory.privateHint': 'Diese Person teilt ihre Fahrhistorie nicht. Nur freigegebene Daten wären hier sichtbar.',
    'rideHistory.regions': 'Gefahrene Regionen',
    'rideHistory.rides': 'Gefahrene Strecken',
    'rideHistory.noRides': 'Noch keine Touren geteilt.',
    'rideHistory.places': 'Besuchte Orte',
    'rideHistory.noPlaces': 'Noch keine Orte geteilt.',
    'rideHistory.statRides': 'Touren',
    'rideHistory.statKm': 'km',
    'rideHistory.statTime': 'Zeit',
    'rideHistory.statElevation': 'Höhe',
    'tour.stats.elevation': 'Höhenmeter',
    'tour.stats.avg': 'Ø Tempo',
    'tour.pois': 'Stopps unterwegs',
    'tour.delete': 'Löschen',
    'tour.deleteConfirm': 'Diese Tour endgültig aus dem Tagebuch löschen?',
    'tour.export': 'Als GPX teilen',
    'tour.exportFailed': 'GPX-Export fehlgeschlagen',
  },
  'en': {
    'settings.themeMode': 'Appearance (UI)',
    'settings.themeMode.system': 'Auto',
    'settings.themeMode.light': 'Light',
    'settings.themeMode.dark': 'Dark',
    'settings.offlineMaps': 'Offline maps',
    'settings.offlineMaps.add': 'Download region',
    'settings.offlineMaps.addHint': 'Save a map area for offline navigation',
    'settings.offlineMaps.dialogTitle': 'Download offline map',
    'settings.offlineMaps.radius': 'Radius around the current position',
    // Tabs
    'settings.languageAndAppearance': 'Language & appearance',
    'settings.saved': 'Saved',
    'errors.saveFailed': 'Saving failed - please try again later',
    'tab.map': 'Map',
    'tab.tours': 'Tours',
    'tab.chat': 'Chat',
    'tab.settings': 'Settings',
    // Common
    'common.save': 'Save',
    'common.cancel': 'Cancel',
    'common.ok': 'OK',
    'common.retry': 'Try again',
    'common.loading': 'Loading…',
    'common.error': 'Error',
    // Settings
    'settings.language': 'Language',
    'settings.language.de': 'Deutsch',
    'settings.language.en': 'English',
    'settings.appearance': 'Appearance',
    'settings.mapStyle': 'Map style',
    'settings.mapStyle.light': 'Light (default)',
    'settings.mapStyle.dark': 'Dark',
    'settings.testConnection': 'Test connection',
    'settings.server': 'Server & connection',
    'settings.serverNote': 'Connection is fixed - no API key or URL needed.',
    'settings.account': 'Account',
    'settings.profile': 'Edit profile',
    'settings.changePassword': 'Change password',
    'settings.deleteAccount': 'Delete account',
    'settings.logout': 'Sign out',
    'settings.privacy': 'Privacy',
    'settings.imprint': 'Imprint',
    'settings.about': 'About MotoRoute',
    'settings.appVersion': 'App version',
    'settings.chatAccount': 'Chat account',
    'settings.chatAccount.connected': 'Connected',
    'settings.chatAccount.notConnected': 'Not connected',
    'settings.showOnline': 'Show online status',
    'settings.chatName': 'Chat display name',
    'settings.chatName.mode': 'Name in chats',
    'settings.chatName.username': 'Username',
    'settings.chatName.firstName': 'First name',
    'settings.chatName.custom': 'Custom display name',
    'settings.chatName.customLabel': 'Custom name',
    'settings.firstName': 'First name',
    'settings.navigation': 'Navigation',
    'settings.notifications': 'Notifications',
    'settings.mapPoiSection': 'Map - POI categories',
    'settings.chatCommunity': 'Chat & community',
    'settings.legal': 'Privacy & legal',
    // Suche & Routing
    'search.hint': 'Search place, postcode or POI',
    'search.title': 'Destination search',
    'search.waypointTitle': 'Search waypoint',
    'route.styleTitle': 'Choose riding style',
    'route.avoid': 'Avoid',
    'route.avoid.highway': 'Highways',
    'route.avoid.ferry': 'Ferries',
    'route.avoid.toll': 'Tolls',
    'route.distance': 'Distance',
    'route.duration': 'Riding time',
    'route.eta': 'Arrival',
    'route.startNavigation': 'Start navigation',
    'route.overview': 'Route overview',
    'route.chooseStart.title': 'Where do you start?',
    'route.chooseStart.gps': 'Current location',
    'route.chooseStart.gpsSub': 'Use the device GPS position',
    'route.chooseStart.address': 'Enter an address',
    'route.chooseStart.addressSub': 'Place, postcode or POI as start',
    'route.chooseStart.noFix': 'No GPS fix - pick an address or try again later',
    'route.waypoints': 'Waypoints',
    // Navigation
    'nav.followRoute': 'Follow the route',
    'nav.end': 'End',
    'nav.offRoute': 'Off route',
    'nav.rerouting': 'Recalculating…',
    'nav.mapOffline': 'Map offline',
    // Auth
    'auth.login': 'Sign in',
    'auth.register': 'Create account',
    'auth.email': 'E-mail',
    'auth.password': 'Password',
    'auth.displayName': 'Display name',
    'auth.rememberDevice': 'Remember this device',
    'auth.logoutAction': 'Sign out',
    'auth.welcomeRegister': 'Welcome aboard!',
    'auth.welcomeLogin': 'Welcome back!',
    'auth.welcomeRegisterSub': 'Create your MotoRoute account',
    'auth.welcomeLoginSub': 'Good to see you riding again.',
    'auth.yourName': 'Your name (optional)',
    'auth.hasAccount': 'I already have an account - Sign in',
    'auth.newHere': 'New here? Create an account',
    'auth.browseWithoutAccount': 'Look around without an account',
    'auth.rememberQuestion': 'Remember this device?',
    'auth.rememberExplanation':
        'If you remember this device, you stay signed in across app restarts. Otherwise you will need to sign in again next time.\n\nWe ask on every sign-in.',
    'auth.sessionOnly': 'This session only',
    // Chat
    'chat.public': 'Public',
    'chat.private': 'Private',
    'chat.groups': 'Groups',
    'chat.messageHint': 'Write a message…',
    'chat.loginRequired': 'Sign in to chat',
    'chat.loginRequiredSub': 'After signing in, chat is available instantly.',
    // Karte
    'map.attribution': '© OpenStreetMap contributors © CARTO',
    'map.offlineNote': 'Map offline - POIs, routing and navigation keep working',
    // Tour diary
    'tour.saveTitle': 'Save tour',
    'tour.saveHint': 'e.g. Alpine loop with dad',
    'tour.discard': 'Discard',
    'tour.empty.title': 'No tours yet',
    'tour.empty.sub': 'Every navigation is recorded automatically. Or import a GPX route from Calimoto or Kurviger.',
    'tour.import.title': 'Import GPX',
    'tour.import.intro': 'Pick a GPX file - e.g. a planned tour from Calimoto or Kurviger.',
    'tour.import.pick': 'Choose GPX file',
    'tour.import.points': 'points',
    'tour.import.ride': 'Ride this tour',
    'tour.import.failed': 'Could not read the file',
    'tour.summary.tours': 'Tours',
    'tour.summary.km': 'km',
    'tour.summary.hours': 'h',
    'tour.summary.elevation': 'Elevation',
    // Ride history (profile)
    'settings.rideHistory': 'Ride history & privacy',
    'rideHistory.requiresLogin': 'Sign in to use ride history. Until then all data stays private.',
    'rideHistory.enabled': 'Record ride history',
    'rideHistory.publicProfile': 'Show ride history publicly',
    'rideHistory.shareRides': 'Share ridden routes publicly',
    'rideHistory.sharePlaces': 'Share visited places publicly',
    'rideHistory.hideStartEnd': 'Hide exact start/destination position',
    'rideHistory.hintPrivate': 'Private: nobody sees your tours or places. Sharing only via the switches above.',
    'rideHistory.hintPublic': 'Public: others see only what you shared above. Fully private profile = main switch off.',
    'rideHistory.title': 'Ride history',
    'rideHistory.loadError': 'Could not load history',
    'rideHistory.retry': 'Retry',
    'rideHistory.private': 'Private profile',
    'rideHistory.privateHint': 'This person does not share their ride history. Only explicitly shared data would appear here.',
    'rideHistory.regions': 'Regions ridden',
    'rideHistory.rides': 'Ridden routes',
    'rideHistory.noRides': 'No shared tours yet.',
    'rideHistory.places': 'Visited places',
    'rideHistory.noPlaces': 'No shared places yet.',
    'rideHistory.statRides': 'Tours',
    'rideHistory.statKm': 'km',
    'rideHistory.statTime': 'Time',
    'rideHistory.statElevation': 'Elev.',
    'tour.stats.elevation': 'Elevation',
    'tour.stats.avg': 'Ø speed',
    'tour.pois': 'Stops along the way',
    'tour.delete': 'Delete',
    'tour.deleteConfirm': 'Permanently delete this tour from the diary?',
    'tour.export': 'Share as GPX',
    'tour.exportFailed': 'GPX export failed',
  },
};

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Geteilter Karten-Stil-Loader - genutzt von der Hauptkarte UND dem
/// aktiven Navigations-Screen. Zuvor hatte nur die Hauptkarte den
/// Vektor-Stil; die Navigation las die nie gesetzte MAP_STYLE_URL und
/// fuhr dadurch mit leerem Stil auf (schwarzer Hintergrund).
///
/// Stil: CARTO Vektor-Basemaps (Positron = hell als STANDARD, Dark
/// Matter = dunkel). Die Raster-Variante (moto-route-dark.json) ist
/// Stilllegungs-Kandidat: CARTO brennt dort ohne gültigen Key ein
/// "API KEY REQUIRED"-Wasserzeichen in die Kacheln. Vektor-Tiles
/// laufen (Stand Sep 2026) auch ohne Key.
///
/// Key: Wird beim Build via --dart-define=CARTO_BASEMAP_KEY=... übergeben
/// (GitHub-Secret, nie im Repo) und zur Laufzeit in die Stil-URLs
/// eingesetzt (Platzhalter __CARTO_KEY__).
enum MapStyleChoice { light, dark }

/// Persistierte Kartenstil-Wahl (Einstellungen). Standard: HELL -
/// Carto Positron, gut lesbar bei Sonne, gewünschter neuer Default.
class MapStyleController extends StateNotifier<MapStyleChoice> {
  MapStyleController() : super(MapStyleChoice.light) {
    _restore();
  }

  static const _kKey = 'map.style';

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(_kKey) == 'dark'
        ? MapStyleChoice.dark
        : MapStyleChoice.light;
  }

  Future<void> set(MapStyleChoice choice) async {
    state = choice;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, choice == MapStyleChoice.dark ? 'dark' : 'light');
  }
}

final mapStyleChoiceProvider =
    StateNotifierProvider<MapStyleController, MapStyleChoice>((ref) {
  return MapStyleController();
});

/// Legacy-Eingang: Ein per Build gesetzter MAP_STYLE_URL gewinnt weiter
/// (bewahrt lokale Experimente ohne Code-Änderung).
const mapStyleUrlOverride =
    String.fromEnvironment('MAP_STYLE_URL', defaultValue: '');

const _cartoBasemapKey = String.fromEnvironment('CARTO_BASEMAP_KEY');

const _styleAssets = {
  MapStyleChoice.light: 'assets/styles/carto-positron-gl-style.json',
  MapStyleChoice.dark: 'assets/styles/carto-dark-matter.json',
};

/// Fallback-Stil für den Fall, dass das Asset fehlt: maplibre_gl
/// verlangt einen nicht-leeren String. Die App bleibt nutzbar (Routing,
/// Chat), die Karte bleibt dann leer statt zu crashen.
const emptyMapStyle = '{"version":8,"sources":{},"layers":[]}';

/// Injiziert den Build-Key in einen Stil-String (Platzhalter entfernen,
/// wenn kein Key vorhanden - Vektor-Tiles laufen dann keyless weiter).
String injectCartoKey(String raw) {
  if (_cartoBasemapKey.isEmpty) {
    return raw
        .replaceAll('?key=__CARTO_KEY__', '')
        .replaceAll('&key=__CARTO_KEY__', '');
  }
  return raw.replaceAll('__CARTO_KEY__', _cartoBasemapKey);
}

/// Lädt den wirksamen Karten-Stil für die gewählte Helligkeit. Wirft
/// nichts: Im Fehlerfall kommt der leere Stil zurück, der Aufrufer
/// zeigt seinen Offline-Hinweis.
Future<String> loadMapStyle([MapStyleChoice choice = MapStyleChoice.light]) async {
  const override = mapStyleUrlOverride;
  if (override.isNotEmpty) return override;
  try {
    final raw = await rootBundle.loadString(_styleAssets[choice]!);
    return injectCartoKey(raw);
  } catch (_) {
    return emptyMapStyle;
  }
}

/// true, wenn der geladene Stil keine Kacheln enthält (Offline-Fall) -
/// Aufrufer zeigen dann den "Karte offline"-Hinweis.
bool isPlaceholderStyle(String style) => style == emptyMapStyle || style.isEmpty;

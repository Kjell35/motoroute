import 'package:flutter/services.dart' show rootBundle;

/// Geteilter Karten-Stil-Loader - genutzt von der Hauptkarte UND dem
/// aktiven Navigations-Screen. Zuvor hatte nur die Hauptkarte den
/// Vektor-Stil; die Navigation las die nie gesetzte MAP_STYLE_URL und
/// fuhr dadurch mit leerem Stil auf (schwarzer Hintergrund).
///
/// Stil: CARTO Dark Matter (Vektor, 93 Layer, scharf auf jedem Display).
/// Die Raster-Variante (moto-route-dark.json) ist Stilllegungs-Kandidat:
/// CARTO brennt dort ohne gültigen Key ein "API KEY REQUIRED"-
/// Wasserzeichen in die Kacheln. Vektor-Tiles laufen (Stand Sep 2026)
/// auch ohne Key.
///
/// Key: Wird beim Build via --dart-define=CARTO_BASEMAP_KEY=... übergeben
/// (GitHub-Secret, nie im Repo) und zur Laufzeit in die Stil-URLs
/// eingesetzt (Platzhalter __CARTO_KEY__).

/// Legacy-Eingang: Ein per Build gesetzter MAP_STYLE_URL gewinnt weiter
/// (bewahrt lokale Experimente ohne Code-Änderung).
const mapStyleUrlOverride = String.fromEnvironment('MAP_STYLE_URL', defaultValue: '');

const _cartoBasemapKey = String.fromEnvironment('CARTO_BASEMAP_KEY');

const _bundledStyleAsset = 'assets/styles/carto-dark-matter.json';

/// Fallback-Stil für den Fall, dass das Asset fehlt: maplibre_gl
/// verlangt einen nicht-leeren String. Die App bleibt nutzbar (Routing,
/// Chat), die Karte bleibt dann leer statt zu crashen.
const emptyMapStyle = '{"version":8,"sources":{},"layers":[]}';

/// Lädt den wirksamen Karten-Stil. Wirft nichts: Im Fehlerfall kommt der
/// leere Stil zurück, der Aufrufer zeigt seinen Offline-Hinweis.
Future<String> loadMapStyle() async {
  const override = mapStyleUrlOverride;
  if (override.isNotEmpty) return override;
  try {
    final raw = await rootBundle.loadString(_bundledStyleAsset);
    if (_cartoBasemapKey.isEmpty) {
      // Ohne Build-Key: Key-Parameter komplett entfernen (Vektor-Tiles
      // funktionieren auch ohne - nur ohne Quota-Absicherung).
      return raw
          .replaceAll('?key=__CARTO_KEY__', '')
          .replaceAll('&key=__CARTO_KEY__', '');
    }
    return raw.replaceAll('__CARTO_KEY__', _cartoBasemapKey);
  } catch (_) {
    return emptyMapStyle;
  }
}

/// true, wenn der geladene Stil keine Kacheln enthält (Offline-Fall) -
/// Aufrufer zeigen dann den "Karte offline"-Hinweis.
bool isPlaceholderStyle(String style) => style == emptyMapStyle || style.isEmpty;

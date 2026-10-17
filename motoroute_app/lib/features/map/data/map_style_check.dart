import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/network/error_message.dart';
import 'map_style.dart';

/// Karten-Style-Check (Einstellungen -> Diagnose).
///
/// Hintergrund: Auf einem Gerät blieb die Karte grau, obwohl serverseitig
/// alles erreichbar war. MapLibre lädt auf dem Gerät nacheinander
/// Stil-JSON -> TileJSON -> Kacheln -> Sprite -> Glyphen. Dieser Check
/// führt GENAU diese Requests vom Gerät aus und zeigt pro Schritt
/// Status, Größe und Dauer - dann sieht man, welche Stufe hakt.

/// Ergebnis eines Prüfschritts.
class MapStyleCheckItem {
  final String name;
  final bool ok;
  final String detail;
  const MapStyleCheckItem(this.name, this.ok, this.detail);
}

/// Die URLs, die das Gerät für einen Stil laden muss.
class MapStyleUrls {
  final List<String> tileJsonUrls;
  final List<String> tileTemplates;
  final String? sprite;
  final String? glyphs;
  final String fontStack;
  final int layerCount;

  const MapStyleUrls({
    required this.tileJsonUrls,
    required this.tileTemplates,
    required this.sprite,
    required this.glyphs,
    required this.fontStack,
    required this.layerCount,
  });
}

/// Liest aus dem Stil-JSON die zu ladenden URLs. Wirft FormatException
/// bei ungültigem JSON (der Aufrufer zeigt das als Fehlerzeile).
MapStyleUrls extractStyleUrls(String styleJson) {
  final decoded = jsonDecode(styleJson);
  if (decoded is! Map) {
    throw const FormatException('Stil ist kein JSON-Objekt');
  }
  final tileJson = <String>[];
  final templates = <String>[];
  final sources = decoded['sources'];
  if (sources is Map) {
    for (final source in sources.values) {
      if (source is! Map) continue;
      final url = source['url'];
      if (url is String && url.isNotEmpty) tileJson.add(url);
      final tiles = source['tiles'];
      if (tiles is List && tiles.isNotEmpty && tiles.first is String) {
        templates.add(tiles.first as String);
      }
    }
  }
  final sprite = decoded['sprite'];
  final glyphs = decoded['glyphs'];

  var fontStack = 'Open Sans Regular';
  var layerCount = 0;
  final layers = decoded['layers'];
  if (layers is List) {
    layerCount = layers.length;
    for (final layer in layers) {
      if (layer is! Map) continue;
      final layout = layer['layout'];
      if (layout is! Map) continue;
      final font = layout['text-font'];
      if (font is List) {
        final names = font.whereType<String>().toList();
        if (names.isNotEmpty && names.first != 'literal') {
          fontStack = names.join(',');
          break;
        }
      }
    }
  }

  return MapStyleUrls(
    tileJsonUrls: tileJson,
    tileTemplates: templates,
    sprite: sprite is String && sprite.isNotEmpty ? sprite : null,
    glyphs: glyphs is String && glyphs.isNotEmpty ? glyphs : null,
    fontStack: fontStack,
    layerCount: layerCount,
  );
}

/// Wie [extractStyleUrls], aber Fehler werden zur Ergebniszeile (null = abgebrochen).
MapStyleUrls? _safeExtract(String style, List<MapStyleCheckItem> items) {
  try {
    return extractStyleUrls(style);
  } catch (e) {
    items.add(MapStyleCheckItem('Stil lesen', false, e.toString()));
    return null;
  }
}

/// Kachel-Template -> konkrete URL (Europa-Kachel, Zoom 5).
String fillTileTemplate(String template, {int z = 5, int x = 16, int y = 10}) {
  return template
      .replaceAll('{z}', '$z')
      .replaceAll('{x}', '$x')
      .replaceAll('{y}', '$y')
      .replaceAll('{s}', 'a')
      .replaceAll('{ratio}', '');
}

/// Sprite-Basis -> URL der Sprite-JSON (MapLibre hängt ".json" vor den Query-String).
String spriteJsonUrl(String sprite) {
  final q = sprite.indexOf('?');
  if (q < 0) return '$sprite.json';
  return '${sprite.substring(0, q)}.json${sprite.substring(q)}';
}

/// Glyphen-Template -> URL des ersten Bereichs.
String glyphsUrl(String template, String fontStack) {
  return template
      .replaceAll('{fontstack}', Uri.encodeComponent(fontStack))
      .replaceAll('{range}', '0-255');
}

/// Führt den Check aus. Wirft NIE: jeder Fehler wird zur Zeile mit ok=false.
Future<List<MapStyleCheckItem>> runMapStyleCheck({
  Dio? dio,
  MapStyleChoice choice = MapStyleChoice.light,
}) async {
  final client = dio ??
      Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        responseType: ResponseType.bytes,
        // Auch 4xx/5xx als Antwort behandeln, damit der Status sichtbar wird.
        validateStatus: (_) => true,
      ));
  final items = <MapStyleCheckItem>[];

  Future<List<int>?> fetch(String name, String url) async {
    final sw = Stopwatch()..start();
    try {
      final res = await client.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes, validateStatus: (_) => true),
      );
      final code = res.statusCode ?? 0;
      final bytes = res.data ?? const <int>[];
      final ok = code == 200 && bytes.isNotEmpty;
      items.add(MapStyleCheckItem(
        name,
        ok,
        'HTTP $code · ${bytes.length} B · ${sw.elapsedMilliseconds} ms',
      ));
      return ok ? bytes : null;
    } catch (e) {
      items.add(MapStyleCheckItem(name, false, technicalCause(e)));
      return null;
    }
  }

  // 1) Stil laden wie die Karte (Asset bzw. MAP_STYLE_URL-Override).
  var style = '';
  try {
    style = await loadMapStyle(choice);
  } catch (e) {
    return [MapStyleCheckItem('Stil laden', false, technicalCause(e))];
  }
  if (isPlaceholderStyle(style)) {
    return const [
      MapStyleCheckItem(
        'Stil laden',
        false,
        'Stil-Datei fehlt/leer -> Karte bleibt grau (Asset nicht gebündelt?)',
      ),
    ];
  }
  // Ein per Build gesetzter MAP_STYLE_URL liefert eine URL statt JSON.
  if (style.startsWith('http')) {
    final bytes = await fetch('Stil-URL', style);
    if (bytes == null) return items;
    style = utf8.decode(bytes, allowMalformed: true);
  }

  final urls = _safeExtract(style, items);
  if (urls == null) return items;
  items.add(MapStyleCheckItem(
    'Stil geladen',
    urls.layerCount > 0,
    '${urls.layerCount} Layer · ${urls.tileJsonUrls.length + urls.tileTemplates.length} Kachel-Quelle(n)',
  ));

  // 2) TileJSON -> Kachel-Template.
  final templates = <String>[...urls.tileTemplates];
  for (final tj in urls.tileJsonUrls) {
    final bytes = await fetch('TileJSON', tj);
    if (bytes == null) continue;
    try {
      final json = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      final tiles = json is Map ? json['tiles'] : null;
      if (tiles is List && tiles.isNotEmpty && tiles.first is String) {
        templates.add(tiles.first as String);
      } else {
        items.add(const MapStyleCheckItem('TileJSON', false, 'enthält keine tiles-URL'));
      }
    } catch (e) {
      items.add(MapStyleCheckItem('TileJSON', false, 'ungültiges JSON: $e'));
    }
  }

  // 3) Eine echte Kachel laden.
  if (templates.isEmpty) {
    items.add(const MapStyleCheckItem('Kachel', false, 'keine Kachel-URL ermittelbar'));
  } else {
    await fetch('Kachel (Zoom 5)', fillTileTemplate(templates.first));
  }

  // 4) Sprite + 5) Glyphen (Symbole/Beschriftung; fehlen sie, bleibt die Karte oft leer).
  if (urls.sprite != null) {
    await fetch('Sprite', spriteJsonUrl(urls.sprite!));
  }
  if (urls.glyphs != null) {
    await fetch('Schrift (Glyphen)', glyphsUrl(urls.glyphs!, urls.fontStack));
  }
  return items;
}

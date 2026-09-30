import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/map/data/map_style_check.dart';

const _style = '''
{
  "version": 8,
  "sources": {
    "carto": {"type": "vector", "url": "https://tiles.example.com/tiles.json"},
    "raster": {"type": "raster", "tiles": ["https://a.example.com/{z}/{x}/{y}.png"]}
  },
  "sprite": "https://tiles.example.com/sprite?key=abc",
  "glyphs": "https://tiles.example.com/fonts/{fontstack}/{range}.pbf",
  "layers": [
    {"id": "bg", "type": "background"},
    {"id": "label", "type": "symbol", "layout": {"text-font": ["Montserrat Regular", "Open Sans Regular"]}}
  ]
}
''';

void main() {
  group('extractStyleUrls', () {
    test('findet TileJSON, direkte Kachel-Templates, Sprite, Glyphen, Schrift und Layer', () {
      final u = extractStyleUrls(_style);
      expect(u.tileJsonUrls, ['https://tiles.example.com/tiles.json']);
      expect(u.tileTemplates, ['https://a.example.com/{z}/{x}/{y}.png']);
      expect(u.sprite, 'https://tiles.example.com/sprite?key=abc');
      expect(u.glyphs, contains('{fontstack}'));
      expect(u.fontStack, 'Montserrat Regular,Open Sans Regular');
      expect(u.layerCount, 2);
    });

    test('ungültiges JSON wirft FormatException', () {
      expect(() => extractStyleUrls('kein json'), throwsFormatException);
      expect(() => extractStyleUrls('[]'), throwsFormatException);
    });

    test('Stil ohne Sprite/Glyphen liefert null statt Absturz', () {
      final u = extractStyleUrls('{"version":8,"sources":{},"layers":[]}');
      expect(u.sprite, isNull);
      expect(u.glyphs, isNull);
      expect(u.fontStack, 'Open Sans Regular');
      expect(u.layerCount, 0);
    });
  });

  group('URL-Helfer', () {
    test('fillTileTemplate ersetzt z/x/y', () {
      expect(fillTileTemplate('https://t/{z}/{x}/{y}.pbf'), 'https://t/5/16/10.pbf');
    });

    test('spriteJsonUrl setzt .json vor den Query-String', () {
      expect(spriteJsonUrl('https://t/sprite'), 'https://t/sprite.json');
      expect(spriteJsonUrl('https://t/sprite?key=k'), 'https://t/sprite.json?key=k');
    });

    test('glyphsUrl kodiert den Font-Stack und nutzt Bereich 0-255', () {
      expect(
        glyphsUrl('https://t/fonts/{fontstack}/{range}.pbf', 'Open Sans Regular'),
        'https://t/fonts/Open%20Sans%20Regular/0-255.pbf',
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:motoroute_app/features/poi/poi_map_layer.dart';

void main() {
  group('PoiMapLayer Zoom-Gate', () {
    test('Nahsicht: schmale Spanne gilt als nah', () {
      final bounds = LatLngBounds(
        southwest: const LatLng(48.10, 11.55),
        northeast: const LatLng(48.15, 11.63), // ~5.5 km breit
      );
      expect(PoiMapLayer.isCloseUpForTest(bounds), isTrue);
    });

    test('Weitsicht: Stadtdauer-View (> 12 km) ist nicht nah', () {
      final bounds = LatLngBounds(
        southwest: const LatLng(47.9, 10.9),
        northeast: const LatLng(48.5, 12.2), // ~100 km breit
      );
      expect(PoiMapLayer.isCloseUpForTest(bounds), isFalse);
    });

    test('Grenzfall: genau 0.12 Grad ist noch nah', () {
      final bounds = LatLngBounds(
        southwest: const LatLng(48.10, 11.50),
        northeast: const LatLng(48.10, 11.62),
      );
      expect(PoiMapLayer.isCloseUpForTest(bounds), isTrue);
    });
  });
}

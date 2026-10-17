import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute/presentation/screens/route/route_scan_screen.dart';

/// Token-Erkennung des QR-Scanners: Erkennt die MotoRoute-Plan-URL aus dem
/// Scan-Ergebnis und verwirft fremde Codes, statt versehentlich zu importieren.
void main() {
  test('erkennt Plan-Token aus gültiger Plan-URL', () {
    expect(
      RouteScanScreen.planTokenFromUrl('http://192.168.178.101:8000/plan/897D24'),
      '897D24',
    );
    // Whitespace- und Case-Toleranz (Scanner-Exporte variieren).
    expect(
      RouteScanScreen.planTokenFromUrl('  https://motoroute.example.com/plan/abc123  '),
      'ABC123',
    );
  });

  test('fremde URLs liefern null (kein versehentlicher Import)', () {
    expect(RouteScanScreen.planTokenFromUrl('https://maps.google.com/?q=xyz'), isNull);
    expect(RouteScanScreen.planTokenFromUrl('nicht einmal eine url'), isNull);
    expect(RouteScanScreen.planTokenFromUrl('http://x/plan/'), isNull);
  });
}

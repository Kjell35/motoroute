import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/garage/garage_input.dart';

/// Dokumente werden als Datei hochgeladen (das frühere Link-Feld ist weg).
/// Geprüft werden Titel, Dateiauswahl und das Größenlimit.
void main() {
  String? check({
    String title = 'Rechnung 2026',
    String fileName = 'rechnung.pdf',
    int sizeBytes = 2048,
  }) =>
      documentProblem(title: title, fileName: fileName, sizeBytes: sizeBytes);

  test('Titel und Datei sind in Ordnung', () {
    expect(check(), isNull);
    expect(check(fileName: 'fahrzeugschein.jpg', sizeBytes: 900000), isNull);
  });

  test('fehlender Titel wird benannt', () {
    expect(check(title: '   '), contains('Titel'));
  });

  test('fehlende Datei wird benannt', () {
    expect(check(fileName: ''), contains('Datei'));
    expect(check(sizeBytes: 0), contains('Datei'));
  });

  test('zu große Dateien werden abgelehnt', () {
    expect(check(sizeBytes: kMaxDocumentBytes + 1), contains('8 MB'));
  });
}

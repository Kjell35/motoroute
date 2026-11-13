import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/garage/garage_input.dart';

/// Der Dokument-Dialog arbeitet als Uebergangsloesung mit einem Link, bis
/// ein Upload-Endpunkt existiert. Geprueft werden Titel und die URL.
void main() {
  String? check({String title = 'Rechnung 2026', String url = 'https://ex.com/a.pdf'}) =>
      documentProblem(title: title, fileUrl: url);

  test('Titel und https-Link sind in Ordnung', () {
    expect(check(), isNull);
    expect(check(url: 'http://example.com/f.pdf'), isNull);
    expect(check(url: '  https://ex.com/a b.pdf  '), isNull);
  });

  test('fehlender Titel wird benannt', () {
    expect(check(title: '   '), contains('Titel'));
  });

  test('unvollstaendige Links werden abgelehnt', () {
    expect(check(url: ''), contains('Link'));
    expect(check(url: 'ex.com/a.pdf'), contains('Link'));
    expect(check(url: 'siehe Ordner'), contains('Link'));
  });

  test('fremde Schemata werden abgelehnt', () {
    expect(check(url: 'ftp://ex.com/a.pdf'), contains('http'));
    expect(check(url: 'file:///C:/a.pdf'), contains('http'));
    expect(check(url: 'javascript:alert(1)'), contains('http'));
  });
}

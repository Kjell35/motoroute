import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/garage/garage_input.dart';

/// Der Reifen-Dialog prueft seine Felder, bevor er schliesst: Pflichtangaben,
/// Datum, Kilometerstand und die optionale Profiltiefe.
void main() {
  String? check({
    String brand = 'Metzeler',
    String model = 'Roadtec 01',
    String size = '120/70 ZR 17',
    String mountedAt = '12.11.2026',
    String km = '12500',
    String tread = '',
  }) =>
      tireProblem(
        brand: brand,
        model: model,
        size: size,
        mountedAtRaw: mountedAt,
        mountedAtKmRaw: km,
        treadDepthRaw: tread,
      );

  test('vollstaendige Angaben sind in Ordnung', () {
    expect(check(), isNull);
    expect(check(tread: '4,2'), isNull);
  });

  test('Pflichtfelder werden benannt', () {
    expect(check(brand: ' '), contains('Reifenmarke'));
    expect(check(model: ''), contains('Reifenmodell'));
    expect(check(size: '  '), contains('Reifengröße'));
  });

  test('Datum muss lesbar und darf nicht in der Zukunft liegen', () {
    expect(check(mountedAt: 'gestern'), contains('Montagedatum'));
    expect(check(mountedAt: '2099-01-01'), contains('Zukunft'));
  });

  test('Kilometerstand muss eine Zahl sein', () {
    expect(check(km: 'viel'), contains('Kilometerstand'));
    expect(check(km: '1000000'), contains('zu hoch'));
  });

  test('Profiltiefe ist optional, aber plausibel', () {
    expect(check(tread: '0'), contains('Profiltiefe'));
    expect(check(tread: '25'), contains('Profiltiefe'));
    expect(check(tread: 'abc'), contains('Profiltiefe'));
  });
}

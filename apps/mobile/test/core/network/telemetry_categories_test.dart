import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:motoroute_app/core/network/telemetry_categories.dart';

/// Findet `ErrorReporter.instance.report(` – unabhängig von Zeilenumbrüchen
/// zwischen Empfänger und Methodenaufruf.
final _callPattern = RegExp(r'ErrorReporter(?:\.\w+)*\s*\.\s*report\(');

/// Erwartet direkt nach der Klammer das Kategorie-Literal.
final _literalPattern = RegExp(r'''\s*(['"])([^'"\n]+)\1''');

List<File> _dartFiles() {
  final lib = Directory('lib');
  if (!lib.existsSync()) {
    fail('lib/ nicht gefunden – der Test erwartet das Paketverzeichnis als '
        'Arbeitsverzeichnis (flutter test aus apps/mobile).');
  }
  return lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();
}

void main() {
  group('Telemetrie-Kategorien', () {
    test('Whitelist ist wohlgeformt', () {
      expect(kTelemetryCategories, isNotEmpty);
      expect(kTelemetryCategories.length, greaterThan(20),
          reason: 'Die Liste soll die Server-Whitelist spiegeln, kein Rest.');
      for (final category in kTelemetryCategories) {
        expect(category.trim(), category,
            reason: 'Kategorie "$category" enthält Leerraum');
        expect(category, isNot(contains(' ')));
        expect(category, isNotEmpty);
      }
    });

    test('jede Kategorie im Code steht auf der Server-Whitelist', () {
      final findings = <String>[];
      final used = <String>{};
      var callSites = 0;

      for (final file in _dartFiles()) {
        final text = file.readAsStringSync();
        for (final call in _callPattern.allMatches(text)) {
          callSites++;
          final literal = _literalPattern.firstMatch(text.substring(call.end));
          if (literal == null) {
            findings.add('${file.path}: Kategorie ist kein String-Literal');
            continue;
          }
          final category = literal.group(2)!;
          if (!kTelemetryCategories.contains(category)) {
            findings.add('${file.path}: "$category" fehlt auf der Whitelist');
          }
          used.add(category);
        }
      }

      // Schutz gegen einen still kaputten Suchausdruck: ohne Treffer würde
      // der Test sonst nichts prüfen und trotzdem grün sein.
      expect(callSites, greaterThan(0),
          reason: 'Kein ErrorReporter.report(...)-Aufruf gefunden.');
      expect(used, isNotEmpty,
          reason: 'Keine Kategorie ausgelesen – Suchmuster prüfen.');
      expect(findings, isEmpty,
          reason: 'Der Server lehnt unbekannte Kategorien mit 400 ab und '
              'ErrorReporter verwirft solche Berichte endgültig. Erst die '
              'Kategorie serverseitig ergänzen, dann hier eintragen.\n'
              '${findings.join('\n')}');
    });
  });
}

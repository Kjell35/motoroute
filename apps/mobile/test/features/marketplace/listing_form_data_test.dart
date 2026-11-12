import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/marketplace/marketplace_repository.dart';

/// Der Multipart-Aufbau ist die Stelle, an der ein einzelnes Foto scheitern
/// kann (Datei geloescht, kein Zugriff). Fortschritt und Fehler werden hier
/// ohne Netzwerk geprueft.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mp_form');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  File foto(String name) {
    final file = File('${dir.path}/$name');
    file.writeAsBytesSync(List<int>.filled(16, 7));
    return file;
  }

  test('meldet den Fortschritt pro Foto und behaelt die Felder', () async {
    final a = foto('a.jpg');
    final b = foto('b.jpg');
    final calls = <String>[];

    final form = await buildListingFormData(
      {'title': 'Auspuff', 'priceCents': 4999},
      [a.path, b.path],
      onPhotoProgress: (done, total) => calls.add('$done/$total'),
    );

    expect(calls, ['1/2', '2/2']);
    expect(form.files.length, 2);
    expect(form.files.every((f) => f.key == 'images'), isTrue);
    expect(form.fields.map((f) => f.key), containsAll(['title', 'priceCents']));
  });

  test('ohne Fotos gibt es keinen Fortschritt und keine Dateien', () async {
    final calls = <String>[];
    final form = await buildListingFormData(
      {'title': 'Ohne Bild'},
      const [],
      onPhotoProgress: (done, total) => calls.add('$done/$total'),
    );

    expect(calls, isEmpty);
    expect(form.files, isEmpty);
  });

  test('fehlende Datei nennt genau das betroffene Bild', () async {
    final a = foto('a.jpg');
    final missing = '${dir.path}/geloescht.jpg';
    final seen = <String>[];

    Object? error;
    try {
      await buildListingFormData(
        const {},
        [a.path, missing],
        onPhotoProgress: (done, total) => seen.add('$done/$total'),
      );
    } catch (e) {
      error = e;
    }

    expect(error, isA<MpPhotoUploadException>());
    final photoError = error as MpPhotoUploadException;
    expect(photoError.index, 2);
    expect(photoError.total, 2);
    expect(photoError.path, missing);
    expect(photoError.toString(), contains('2/2'));
    // Das erste Foto war schon fertig - der Fortschritt luegt nicht.
    expect(seen, ['1/2']);
  });
}

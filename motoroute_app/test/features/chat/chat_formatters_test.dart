import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/chat/presentation/widgets/chat_formatters.dart';

void main() {
  group('formatRelativeTime (Abschnitt 6: „Vor 5 Min.“)', () {
    final now = DateTime(2026, 9, 18, 15, 30);

    test('vor wenigen Sekunden', () {
      final t = now.subtract(const Duration(seconds: 30)).toIso8601String();
      expect(formatRelativeTime(t, now: now), 'Gerade eben');
    });

    test('vor 5 Minuten', () {
      final t = now.subtract(const Duration(minutes: 5)).toIso8601String();
      expect(formatRelativeTime(t, now: now), 'Vor 5 Min.');
    });

    test('vor 2 Stunden', () {
      final t = now.subtract(const Duration(hours: 2)).toIso8601String();
      expect(formatRelativeTime(t, now: now), 'Vor 2 Std.');
    });

    test('gestern', () {
      final t = now.subtract(const Duration(days: 1)).toIso8601String();
      expect(formatRelativeTime(t, now: now), 'Gestern');
    });

    test('älter als eine Woche: kurzes Datum', () {
      final t = now.subtract(const Duration(days: 9)).toIso8601String();
      expect(formatRelativeTime(t, now: now), '09.09.');
    });

    test('ungültiger Timestamp: leerer String statt Exception', () {
      expect(formatRelativeTime('kein-datum', now: now), '');
    });
  });

  group('formatClock', () {
    test('formatiert HH:MM zweistellig', () {
      final t = DateTime(2026, 9, 18, 9, 5).toIso8601String();
      expect(formatClock(t), '09:05');
    });
  });
}

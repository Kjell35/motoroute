/// Zeit-/Text-Formatierung für den Chat. Rein funktional und unit-testbar.
library;

/// Relative Zeitangabe wie in der Chat-Vorgabe („Vor 5 Min.“).
String formatRelativeTime(String isoTimestamp, {DateTime? now}) {
  final t = DateTime.tryParse(isoTimestamp);
  if (t == null) return '';
  final n = now ?? DateTime.now();
  final diff = n.difference(t);

  if (diff.inSeconds < 60) return 'Gerade eben';
  if (diff.inMinutes < 60) return 'Vor ${diff.inMinutes} Min.';
  if (diff.inHours < 24) return 'Vor ${diff.inHours} Std.';
  if (diff.inDays == 1) return 'Gestern';
  if (diff.inDays < 7) return 'Vor ${diff.inDays} Tagen';
  // Älter: Datum kurz (TT.MM.)
  return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.';
}

/// Zeitstempel in der Bubbles („14:32“).
String formatClock(String isoTimestamp) {
  final t = DateTime.tryParse(isoTimestamp);
  if (t == null) return '';
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

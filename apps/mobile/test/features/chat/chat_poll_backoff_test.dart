import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/chat/presentation/conversation_screen.dart';

/// Solange der WebSocket aus ist, pollt der Chat per REST. Im Funkloch darf
/// das nicht alle acht Sekunden ins Leere laufen: der Abstand waechst mit
/// jedem Fehlschlag und bleibt bei 60 s gedeckelt.
void main() {
  test('startet bei 8 Sekunden', () {
    expect(chatPollIntervalSeconds(0), 8);
  });

  test('verdoppelt sich pro Fehlschlag', () {
    expect(chatPollIntervalSeconds(1), 16);
    expect(chatPollIntervalSeconds(2), 32);
  });

  test('ist bei 60 Sekunden gedeckelt', () {
    expect(chatPollIntervalSeconds(3), 60);
    expect(chatPollIntervalSeconds(10), 60);
  });

  test('negative Werte werden wie 0 behandelt', () {
    expect(chatPollIntervalSeconds(-1), 8);
  });
}

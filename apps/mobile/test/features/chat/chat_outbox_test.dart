import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:motoroute_app/features/chat/data/chat_outbox.dart';
import 'package:motoroute_app/features/chat/data/chat_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RepoMock extends Mock implements ChatRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('offline getippte Nachricht ueberlebt einen Neustart', () async {
    final outbox = ChatOutbox();
    await outbox.load();
    await outbox.enqueue('conv-1', 'Bin gleich da');

    expect(outbox.state, hasLength(1));
    expect(outbox.forConversation('conv-1').single.text, 'Bin gleich da');
    expect(outbox.forConversation('conv-2'), isEmpty);

    // Neue Instanz = App-Neustart.
    final restored = ChatOutbox();
    await restored.load();
    expect(restored.state, hasLength(1));
    expect(restored.state.single.conversationId, 'conv-1');
  });

  test('leere Nachrichten landen nicht in der Warteschlange', () async {
    final outbox = ChatOutbox();
    await outbox.load();
    await outbox.enqueue('conv-1', '   ');
    expect(outbox.state, isEmpty);
  });

  test('flush sendet und entfernt bestaetigte Nachrichten', () async {
    final repo = _RepoMock();
    when(() => repo.send(any(), any(), any()))
        .thenAnswer((_) async => _message('m1'));

    final outbox = ChatOutbox();
    await outbox.load();
    await outbox.enqueue('conv-1', 'eins');
    await outbox.enqueue('conv-2', 'zwei');

    final sent = await outbox.flush(repo, 'token');

    expect(sent, 2);
    expect(outbox.state, isEmpty);
    verify(() => repo.send('token', 'conv-1', 'eins')).called(1);
    verify(() => repo.send('token', 'conv-2', 'zwei')).called(1);
  });

  test('Fehlschlag laesst die Nachricht in der Warteschlange', () async {
    final repo = _RepoMock();
    when(() => repo.send(any(), any(), any()))
        .thenAnswer((_) async => throw StateError('offline'));

    final outbox = ChatOutbox();
    await outbox.load();
    await outbox.enqueue('conv-1', 'haengt');

    final sent = await outbox.flush(repo, 'token');

    expect(sent, 0);
    expect(outbox.state, hasLength(1));
    expect(outbox.state.single.text, 'haengt');
  });

  test('nach dem Senden ist der Stand auch gespeichert', () async {
    final repo = _RepoMock();
    when(() => repo.send(any(), any(), any()))
        .thenAnswer((_) async => _message('m1'));

    final outbox = ChatOutbox();
    await outbox.load();
    await outbox.enqueue('conv-1', 'weg damit');
    await outbox.flush(repo, 'token');

    final restored = ChatOutbox();
    await restored.load();
    expect(restored.state, isEmpty);
  });
}

ChatMessage _message(String id) => ChatMessage(
      id: id,
      conversationId: 'conv-1',
      senderId: 'me',
      content: 'x',
      attachment: null,
      replyToId: null,
      createdAt: DateTime(2026, 1, 1).toIso8601String(),
      deletedAt: null,
    );

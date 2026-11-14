import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:motoroute_app/features/chat/data/chat_outbox.dart';
import 'package:motoroute_app/features/chat/data/chat_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RepoMock extends Mock implements ChatRepository {}

ChatMessage _message({
  String id = 'm1',
  String conversationId = 'conv-1',
  String senderId = 'me',
  String content = 'x',
  DateTime? createdAt,
}) =>
    ChatMessage(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      content: content,
      attachment: null,
      replyToId: null,
      createdAt: (createdAt ?? DateTime.now()).toIso8601String(),
      deletedAt: null,
    );

MessagePage _page(List<ChatMessage> messages) =>
    MessagePage(messages: messages, hasMore: false);

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
        .thenAnswer((_) async => _message());

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

  test('Fehlschlag zaehlt den Versuch, damit der naechste nicht blind sendet',
      () async {
    final repo = _RepoMock();
    when(() => repo.send(any(), any(), any()))
        .thenAnswer((_) async => throw StateError('offline'));

    final outbox = ChatOutbox();
    await outbox.load();
    await outbox.enqueue('conv-1', 'haengt');
    await outbox.flush(repo, 'token');

    expect(outbox.state.single.attempts, 1);

    // Auch der Neustart kennt den Versuch noch.
    final restored = ChatOutbox();
    await restored.load();
    expect(restored.state.single.attempts, 1);
  });

  test('nach dem Senden ist der Stand auch gespeichert', () async {
    final repo = _RepoMock();
    when(() => repo.send(any(), any(), any()))
        .thenAnswer((_) async => _message());

    final outbox = ChatOutbox();
    await outbox.load();
    await outbox.enqueue('conv-1', 'weg damit');
    await outbox.flush(repo, 'token');

    final restored = ChatOutbox();
    await restored.load();
    expect(restored.state, isEmpty);
  });

  test('schon angekommene Nachricht geht nach Funkloch nicht nochmal raus',
      () async {
    final repo = _RepoMock();
    when(() => repo.messages(any(), any(),
            before: any(named: 'before'), limit: any(named: 'limit')))
        .thenAnswer((_) async => _page([
              _message(
                  id: 'server-1',
                  content: 'Bin gleich da',
                  createdAt: DateTime.now()),
            ]));

    final outbox = ChatOutbox();
    await outbox.load();
    // Der Versuch ging raus, die Antwort kam nie an.
    await outbox.enqueue('conv-1', 'Bin gleich da', attempted: true);

    final sent = await outbox.flush(repo, 'token', myUserId: 'me');

    expect(sent, 0);
    expect(outbox.state, isEmpty);
    verifyNever(() => repo.send(any(), any(), any()));
  });

  test('frische Nachricht wird ohne Blick in die Historie gesendet', () async {
    final repo = _RepoMock();
    when(() => repo.send(any(), any(), any()))
        .thenAnswer((_) async => _message());
    when(() => repo.messages(any(), any(),
            before: any(named: 'before'), limit: any(named: 'limit')))
        .thenAnswer((_) async => _page([_message(content: 'dieselbe')]));

    final outbox = ChatOutbox();
    await outbox.load();
    await outbox.enqueue('conv-1', 'dieselbe');

    // Gleicher Text, gleicher Absender - aber ohne frueheren Versuch ist das
    // eine zweite, absichtliche Nachricht und muss rausgehen.
    final sent = await outbox.flush(repo, 'token', myUserId: 'me');

    expect(sent, 1);
    verify(() => repo.send('token', 'conv-1', 'dieselbe')).called(1);
    verifyNever(() => repo.messages(any(), any(),
        before: any(named: 'before'), limit: any(named: 'limit')));
  });

  test('eine Nachricht des Gegenuebers gilt nicht als gesendet', () async {
    final repo = _RepoMock();
    when(() => repo.send(any(), any(), any()))
        .thenAnswer((_) async => _message());
    when(() => repo.messages(any(), any(),
            before: any(named: 'before'), limit: any(named: 'limit')))
        .thenAnswer((_) async => _page([
              _message(content: 'ok', senderId: 'other'),
            ]));

    final outbox = ChatOutbox();
    await outbox.load();
    await outbox.enqueue('conv-1', 'ok', attempted: true);

    final sent = await outbox.flush(repo, 'token', myUserId: 'me');

    expect(sent, 1);
    verify(() => repo.send('token', 'conv-1', 'ok')).called(1);
  });

  test('alte gleiche Nachricht ausserhalb des Fensters zaehlt nicht', () async {
    final repo = _RepoMock();
    when(() => repo.send(any(), any(), any()))
        .thenAnswer((_) async => _message());
    when(() => repo.messages(any(), any(),
            before: any(named: 'before'), limit: any(named: 'limit')))
        .thenAnswer((_) async => _page([
              _message(
                  content: 'ok',
                  createdAt:
                      DateTime.now().subtract(const Duration(hours: 2))),
            ]));

    final outbox = ChatOutbox();
    await outbox.load();
    await outbox.enqueue('conv-1', 'ok', attempted: true);

    final sent = await outbox.flush(repo, 'token', myUserId: 'me');

    expect(sent, 1);
  });
}

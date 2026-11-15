import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:motoroute_app/core/network/network_status.dart';
import 'package:motoroute_app/core/theme/app_theme.dart';
import 'package:motoroute_app/features/chat/chat_providers.dart';
import 'package:motoroute_app/features/chat/data/chat_outbox.dart';
import 'package:motoroute_app/features/chat/data/chat_realtime.dart';
import 'package:motoroute_app/features/chat/data/chat_repository.dart';
import 'package:motoroute_app/features/chat/presentation/conversation_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RepoMock extends Mock implements ChatRepository {}

class _RealtimeMock extends Mock implements ChatRealtimeClient {}

const _conv = 'conv-1';

ChatMessage _message(String id, String content) => ChatMessage(
      id: id,
      conversationId: _conv,
      senderId: 'me',
      content: content,
      attachment: null,
      replyToId: null,
      createdAt: DateTime.now().toIso8601String(),
      deletedAt: null,
    );

/// Deckt den Weg ab, fuer den die letzten Aenderungen gebaut wurden:
/// offline tippen -> Nachricht wartet -> Verbindung kommt zurueck -> raus.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RepoMock repo;
  late _RealtimeMock realtime;
  late StreamController<bool> connection;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = _RepoMock();
    realtime = _RealtimeMock();
    connection = StreamController<bool>.broadcast();

    when(() => realtime.messages).thenAnswer((_) => const Stream.empty());
    when(() => realtime.deletions).thenAnswer((_) => const Stream.empty());
    when(() => realtime.typing).thenAnswer((_) => const Stream.empty());
    when(() => realtime.connection).thenAnswer((_) => connection.stream);
    when(() => realtime.isConnected).thenReturn(false);
    when(() => realtime.connect(any())).thenReturn(null);
    when(() => realtime.subscribe(any())).thenReturn(null);
    when(() => realtime.unsubscribe(any())).thenReturn(null);

    when(() => repo.me(any())).thenAnswer((_) async => const ChatUser(id: 'me'));
    when(() => repo.messages(any(), any(),
            before: any(named: 'before'), limit: any(named: 'limit')))
        .thenAnswer((_) async => const MessagePage(messages: [], hasMore: false));
    when(() => repo.markRead(any(), any())).thenAnswer((_) async {});
    when(() => repo.conversations(any()))
        .thenAnswer((_) async => const <ConversationSummary>[]);
  });

  tearDown(() async {
    await connection.close();
  });

  Future<ProviderContainer> pumpScreen(WidgetTester tester) async {
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(repo),
      chatRealtimeProvider.overrideWithValue(realtime),
      chatSessionTokenProvider.overrideWith((ref) => 'token'),
      networkOnlineProvider.overrideWith((ref) => Stream.value(true)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: ConversationScreen(
              conversationId: _conv,
              title: 'Testchat',
              embedded: true,
            ),
          ),
        ),
      ),
    );
    // Erstes Laden der Historie abwarten (keine pumpAndSettle: der Screen
    // haelt bewusst Dauer-Timer fuer Polling und Lesen-Markieren).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    return container;
  }

  testWidgets('offline getippte Nachricht wartet und geht bei Reconnect raus',
      (tester) async {
    var offline = true;
    when(() => repo.send(any(), any(), any())).thenAnswer((_) async {
      if (offline) throw StateError('kein Netz');
      return _message('server-1', 'Bin gleich da');
    });

    final container = await pumpScreen(tester);

    await tester.enterText(find.byType(TextField), 'Bin gleich da');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // Nachricht ist nicht verloren, sondern liegt in der Warteschlange.
    expect(container.read(chatOutboxProvider), hasLength(1));
    expect(find.text('1 Nachricht wartet auf Verbindung'), findsOneWidget);

    // Verbindung kommt zurueck.
    offline = false;
    connection.add(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 40));

    expect(container.read(chatOutboxProvider), isEmpty);
    expect(find.text('1 Nachricht wartet auf Verbindung'), findsNothing);
    verify(() => repo.send('token', _conv, 'Bin gleich da')).called(2);

    // Timer des Screens sauber beenden.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Banner zeigt die Warteschlange auch nach erneutem Oeffnen',
      (tester) async {
    when(() => repo.send(any(), any(), any()))
        .thenAnswer((_) async => throw StateError('kein Netz'));

    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField), 'haengt noch');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('1 Nachricht wartet auf Verbindung'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());

    // Neuer Screen, gleiche Warteschlange: der Hinweis steht sofort da.
    await pumpScreen(tester);
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('1 Nachricht wartet auf Verbindung'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}

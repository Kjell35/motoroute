import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:motoroute_app/features/chat/chat_providers.dart';
import 'package:motoroute_app/features/chat/data/chat_realtime.dart';
import 'package:motoroute_app/features/chat/data/chat_repository.dart'
    show ChatUser;
import 'package:motoroute_app/features/group_rides/group_ride_repository.dart';
import 'package:motoroute_app/features/group_rides/presentation/group_ride_screen.dart';

class _MockRepo extends Mock implements GroupRideRepository {}

Widget _app(GroupRideRepository repo) => ProviderScope(
      overrides: [
        groupRideRepositoryProvider.overrideWithValue(repo),
        chatRealtimeProvider.overrideWithValue(
            ChatRealtimeClient(wsBaseUrl: 'ws://localhost:0')),
        chatSessionTokenProvider.overrideWith((ref) => 'token-1'),
        chatMeProvider.overrideWith((ref) async => const ChatUser(id: 'u1')),
      ],
      child: const MaterialApp(home: GroupRideScreen(routeId: 'r1')),
    );

void main() {
  testWidgets('erst Ladezustand, nach leerer Antwort der Leerzustand',
      (tester) async {
    final repo = _MockRepo();
    final pending = Completer<List<LiveRider>>();
    when(() => repo.liveState(any(), any())).thenAnswer((_) => pending.future);

    await tester.pumpWidget(_app(repo));
    await tester.pump();
    expect(find.textContaining('werden geladen'), findsOneWidget,
        reason: 'vor der ersten Antwort darf kein Leerzustand erscheinen');

    pending.complete(const []);
    await tester.pump();
    await tester.pump();

    expect(find.text('Niemand teilt gerade'), findsOneWidget);
    expect(find.textContaining('werden geladen'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Fehler zeigt Hinweis mit Wiederholung', (tester) async {
    final repo = _MockRepo();
    when(() => repo.liveState(any(), any())).thenThrow(Exception('offline'));

    await tester.pumpWidget(_app(repo));
    await tester.pump();
    await tester.pump();

    expect(find.text('Erneut versuchen'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Teilen-Schalter hat ein Label fuer Screenreader', (tester) async {
    final repo = _MockRepo();
    when(() => repo.liveState(any(), any())).thenAnswer((_) async => []);
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_app(repo));
    await tester.pump();
    await tester.pump();

    final node = tester.getSemantics(find.byType(Switch));
    expect(node.label, 'Meine Position teilen',
        reason: 'ohne Label liest der Screenreader nur "Switch, aus"');

    handle.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}

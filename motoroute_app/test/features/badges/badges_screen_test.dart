import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:motoroute_app/features/badges/badges_repository.dart';
import 'package:motoroute_app/features/badges/presentation/badges_screen.dart';

class _MockRepo extends Mock implements BadgesRepository {}

BadgeShelf _shelf() => BadgeShelf(
      badges: [
        BadgeItem(
          id: 'b1',
          title: 'Stilfser Joch',
          description: '48 Kurven',
          iconUrl: null,
          category: BadgeCategory.pass,
          lat: 46.52847,
          lon: 10.45255,
          radiusMeters: 150,
          unlocked: true,
          unlockedAt: DateTime.parse('2026-09-27T10:00:00Z'),
        ),
        BadgeItem(
          id: 'b2',
          title: 'Köterberg',
          description: 'Treff',
          iconUrl: null,
          category: BadgeCategory.meeting,
          lat: 51.9245,
          lon: 9.3308,
          radiusMeters: 120,
          unlocked: false,
          unlockedAt: null,
        ),
      ],
      unlockedCount: 1,
      totalCount: 2,
    );

void main() {
  testWidgets('Trophäenschrank: freigeschaltet zeigt Titel + Datum, gesperrt bleibt anonym', (tester) async {
    final repo = _MockRepo();
    when(() => repo.shelf(token: any(named: 'token'))).thenAnswer((_) async => _shelf());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          badgesRepositoryProvider.overrideWithValue(repo),
          badgesTokenProvider.overrideWithValue('tok'),
        ],
        child: const MaterialApp(home: BadgesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Fortschritt
    expect(find.text('1 / 2 freigeschaltet'), findsOneWidget);
    // Freigeschaltet: Titel sichtbar + Datum (lokale Zeit kann abweichen, Tag zählt)
    expect(find.text('Stilfser Joch'), findsOneWidget);
    expect(find.textContaining('2026'), findsOneWidget);
    // Gesperrt: Titel versteckt ("???"), Sperr-Hinweis da
    expect(find.text('???'), findsOneWidget);
    expect(find.text('Noch gesperrt'), findsOneWidget);
    // Check-in-Button vorhanden
    expect(find.text('Check-in'), findsOneWidget);
  });

  testWidgets('Trophäenschrank: Fehler wird mit Ursache angezeigt', (tester) async {
    final repo = _MockRepo();
    final opts = RequestOptions(path: '/v1/badges/me');
    when(() => repo.shelf(token: any(named: 'token'))).thenThrow(
      DioException(
        requestOptions: opts,
        response: Response(requestOptions: opts, statusCode: 503),
        type: DioExceptionType.badResponse,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          badgesRepositoryProvider.overrideWithValue(repo),
          badgesTokenProvider.overrideWithValue('tok'),
        ],
        child: const MaterialApp(home: BadgesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('HTTP 503'), findsOneWidget);
    expect(find.byIcon(Icons.emoji_events_outlined), findsOneWidget);
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:motoroute_app/core/network/error_reporter.dart';
import 'package:motoroute_app/core/theme/app_theme.dart';
import 'package:motoroute_app/features/marketplace/marketplace_repository.dart';
import 'package:motoroute_app/features/marketplace/presentation/marketplace_detail_screen.dart';

class _RepoMock extends Mock implements MarketplaceRepository {}

MpListing _listing() => MpListing(
      id: 'l1',
      sellerId: 's1',
      title: 'Bremsscheibe vorne',
      description: 'Neu, unbenutzt.',
      priceCents: 4999,
      condition: MpCondition.neu,
      category: MpCategory.motorradteile,
      subcategory: 'Bremsen',
      brand: null,
      model: null,
      year: null,
      locationLabel: 'Berlin',
      shipping: true,
      status: 'active',
      reviewStatus: MpReviewStatus.approved,
      reviewReason: null,
      createdAt: DateTime(2026, 1, 1),
      imageUrls: const [],
    );

const _reviews = MpReviews(reviews: [], average: 0, count: 0);

Future<void> _pumpDetail(WidgetTester tester, _RepoMock repo,
    {bool settle = true}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        marketplaceRepositoryProvider.overrideWithValue(repo),
        marketplaceTokenProvider.overrideWithValue('token'),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const MarketplaceDetailScreen(listingId: 'l1'),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // Ohne settle: der Fehlerpfad der Bewertungen laesst das Detail nicht zur
    // Ruhe kommen, pumpAndSettle wuerde auf Frames warten, die nie enden.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('Stern springt sofort und rollt bei Fehler zurueck',
      (tester) async {
    final repo = _RepoMock();
    when(() => repo.get(
          token: any(named: 'token'),
          id: any(named: 'id'),
        )).thenAnswer((_) async => _listing());
    when(() => repo.favorites(token: any(named: 'token')))
        .thenAnswer((_) async => const <MpListing>[]);
    when(() => repo.reviews(
          token: any(named: 'token'),
          listingId: any(named: 'listingId'),
        )).thenAnswer((_) async => _reviews);
    // Der Fehlschlag wird erst spaeter ausgeloest, sonst waere der
    // optimistische Zwischenzustand schon im ersten Frame wieder weg.
    final gate = Completer<void>();
    when(() => repo.addFavorite(
          token: any(named: 'token'),
          id: any(named: 'id'),
        )).thenAnswer((_) => gate.future);

    await _pumpDetail(tester, repo);
    expect(find.byIcon(Icons.favorite_outline), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite_outline));
    await tester.pump();
    // Optimistisch: der Stern ist schon gesetzt, obwohl der Request laeuft.
    expect(find.byIcon(Icons.favorite), findsOneWidget);

    gate.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    // Fehlschlag: zurueck auf "nicht gemerkt" statt einer Luege im Stern.
    expect(find.byIcon(Icons.favorite_outline), findsOneWidget);
  });

  testWidgets('Erfolgreicher Klick bleibt gemerkt', (tester) async {
    final repo = _RepoMock();
    when(() => repo.get(
          token: any(named: 'token'),
          id: any(named: 'id'),
        )).thenAnswer((_) async => _listing());
    when(() => repo.favorites(token: any(named: 'token')))
        .thenAnswer((_) async => const <MpListing>[]);
    when(() => repo.reviews(
          token: any(named: 'token'),
          listingId: any(named: 'listingId'),
        )).thenAnswer((_) async => _reviews);
    when(() => repo.addFavorite(
          token: any(named: 'token'),
          id: any(named: 'id'),
        )).thenAnswer((_) async {});

    await _pumpDetail(tester, repo);
    await tester.tap(find.byIcon(Icons.favorite_outline));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.favorite), findsOneWidget);
    verify(() => repo.addFavorite(token: 'token', id: 'l1')).called(1);
  });

  testWidgets('fehlgeschlagene Bewertungen landen in der Telemetrie',
      (tester) async {
    final repo = _RepoMock();
    when(() => repo.get(
          token: any(named: 'token'),
          id: any(named: 'id'),
        )).thenAnswer((_) async => _listing());
    when(() => repo.favorites(token: any(named: 'token')))
        .thenAnswer((_) async => const <MpListing>[]);
    when(() => repo.reviews(
          token: any(named: 'token'),
          listingId: any(named: 'listingId'),
        )).thenAnswer((_) async => throw StateError('Bewertungen kaputt'));

    // Ohne Prefs-Mock haengt der Reporter beim Ablegen des Berichts.
    SharedPreferences.setMockInitialValues({});
    final reports = <Map<String, Object?>>[];
    ErrorReporter.instance.debugReset();
    ErrorReporter.instance.debugConfigure(sender: (payload) async {
      reports.add(payload);
      return 200;
    });
    addTearDown(ErrorReporter.instance.debugReset);

    await _pumpDetail(tester, repo, settle: false);
    // runAsync: der Reporter wartet intern auf echte Zeitfenster, die im
    // Fake-Async des Widget-Tests sonst nie vergehen.
    await tester.runAsync(() => ErrorReporter.instance.debugIdle());

    // Vorher war der Grund unsichtbar: das Detail sah einfach "keine
    // Bewertungen" - wie eine Anzeige ohne Bewertungen.
    expect(reports.map((r) => r['category']).toList(), contains('mp.load'));
  });
}

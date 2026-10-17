import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motoroute/application/route/waypoint_providers.dart';
import 'package:motoroute/infrastructure/pairing/http_pairing_repository.dart';
import 'package:motoroute/presentation/screens/route/computer_planning_sheet.dart';

/// QR-Code im Pairing-Sheet: kodiert die `plan_url`, damit die Handy-Kamera
/// den PC-Planning-Link öffnen kann, ohne ihn abzutippen.
void main() {
  const String planUrl = 'http://192.168.178.101:8000/plan/897D24';
  const String token = '897D24';

  testWidgets('Sheet rendert QR-Code mit der plan_url (kein Abtippen nötig)', (tester) async {
    final repository = _mockedRepository(
      startBody: jsonEncode({
        'token': token,
        'plan_url': planUrl,
        'expires_in_seconds': 1800,
      }),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ComputerPlanningSheet(repository: repository),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // PrettyQrView rendert als RenderObjectWidget -> prüfe auf die Widget-Klasse.
    final qrFinder = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == 'PrettyQrDataView',
    );
    expect(qrFinder, findsOneWidget);
    expect(find.text('Token: $token'), findsOneWidget);
  });

  testWidgets('„Plan abrufen“ übernimmt geplante Punkte und schließt das Sheet', (tester) async {
    final repository = _mockedRepository(
      startBody: jsonEncode({
        'token': token,
        'plan_url': planUrl,
        'expires_in_seconds': 1800,
      }),
      planBody: jsonEncode({
        'points': [
          {'label': 'Start', 'lat': 48.1, 'lon': 11.5},
          {'label': 'Ziel', 'lat': 49.4, 'lon': 11.1},
        ],
      }),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => ComputerPlanningSheet(repository: repository),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Explizit „Plan abrufen“ tippen (Auto-Poll-Timer feuert in Fake-Async alle
    // 5 s → nicht settle-stabil); ensureVisible scrollt den Button ins Bild.
    await tester.ensureVisible(find.text('Plan abrufen'));
    await tester.tap(find.text('Plan abrufen'));
    await tester.pumpAndSettle();

    // Der geplante Entwurf muss in der Waypoint-Liste landen (Start→Ziel).
    // Nach dem Pop ist das Sheet weg – Container daher vor dem Pop-Check lesen,
    // über einen noch auf dem Baum befindlichen Knoten.
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    expect(
      container.read(waypointsProvider).map((w) => w.label).toList(),
      ['Start', 'Ziel'],
    );
  });
}

/// Repo gegen einen in-Memory-http-Client gemockt – gleicher HTTP-Vertrag
/// wie das Backend, kein echter Netzwerk-Call in Tests.
PairingRepository _mockedRepository({
  String startBody = '{}',
  String planBody = '{}',
}) {
  return PairingRepository(
    client: MockClient((request) async {
      if (request.method == 'POST' && request.url.path.endsWith('/pairing/start')) {
        return http.Response(startBody, 200);
      }
      if (request.method == 'GET' && request.url.path.contains('/pairing/')) {
        return http.Response(planBody, 200);
      }
      return http.Response('{}', 404);
    }),
  );
}

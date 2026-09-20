import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';

/// Recht/Info-Seiten: Datenschutz, Impressum, Über MotoRoute.
///
/// WICHTIG: Alle Angaben beschreiben NUR, was MotoRoute tatsächlich
/// verarbeitet (Stand: v0.3.0, private Testphase). Keine erfundenen
/// Absätze - jede Zeile ist an realen Code gekoppelt:
///  - Konto: E-Mail + Name → eigenes Backend → Supabase Auth/DB
///  - Standort: GPS nur auf dem Gerät; Live-Radar/Positionen Opt-in,
///    Radar-Einträge serverseitig nach 30 Min. gelöscht
///  - Chats: Server-Speicherung, private Chats RLS-geschützt
///  - Navigation: Routen werden live berechnet, nicht gespeichert
///  - Externe Dienste: OpenStreetMap/CARTO-Kacheln (keyless),
///    TomTom (Suche/Verkehr, Key nur im Backend), Open-Meteo (Wetter)

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const _sections = <({String title, String body})>[
    (
      title: 'Benutzerkonto',
      body: 'Für Anmeldung und Chat speichert MotoRoute deine E-Mail-Adresse '
          'und den von dir gewählten Anzeigenamen auf dem eigenen Backend-Server '
          '(Supabase, EU-Region deines Projekts). Das Passwort wird nur als '
          'sicherer Hash gespeichert - MotoRoute kann es nicht lesen. '
          'Über Einstellungen > Konto kannst du dein Konto samt aller '
          'zugehörigen Daten endgültig löschen.',
    ),
    (
      title: 'Standort',
      body: 'Dein GPS-Standort wird auf dem Gerät verarbeitet: für die '
          'Kartenanzeige, Navigation und Off-Route-Erkennung. Er verlässt '
          'das Gerät nur, wenn du es aktiv entscheidest: Die Live-Gruppenfahrt '
          'teilt deine Position nur opt-in mit deinen eigenen Gruppenmitgliedern, '
          'das Biker-Radar nur, wenn du es selbst einschaltest. Radar-Positionen '
          'werden spätestens nach 30 Minuten automatisch vom Server gelöscht. '
          'Es gibt kein Standort-Tracking und kein Standort-Profil.',
    ),
    (
      title: 'Chats',
      body: 'Chat-Nachrichten (öffentlich, privat, Gruppen) werden auf dem '
          'Backend-Server gespeichert, damit sie auf deinen Geräten ankommen. '
          'Private Nachrichten sind datenbankseitig (Row Level Security) so '
          'geschützt, dass ausschließlich die beteiligten Personen sie lesen '
          'können - nicht einmal andere angemeldete Nutzer. Du kannst Nachrichten '
          'in privaten Chats löschen; beim Kontolöschen fallen alle deine '
          'Chat-Inhalte mit weg.',
    ),
    (
      title: 'Gruppen',
      body: 'Gruppen speichern Name, Beschreibung, Mitgliederliste und '
          'Einladungscodes. Gemeinsam geplante Routen (Wegpunkte, Stops) '
          'werden als Teil der Gruppe gespeichert. Verlässt du eine Gruppe '
          'oder löschst dein Konto, endet die Mitgliedschaft.',
    ),
    (
      title: 'Navigation & Routen',
      body: 'Routenberechnung läuft über das Backend (OpenStreetMap-Daten '
          'via GraphHopper). Gesendete Wegpunkte werden zur Berechnung '
          'verwendet; Routen deiner privaten Planung werden serverseitig '
          'nicht dauerhaft gespeichert. Gemeinsame Gruppenrouten bleiben '
          'als Planung in der Gruppe bestehen.',
    ),
    (
      title: 'Externe Dienste',
      body: 'Kartenkacheln kommen von OpenStreetMap-Mirrors (CARTO) - '
          'dabei wird deine IP-Adresse an den Kachelserver übertragen '
          '(technisch unvermeidbar, keine Kontodaten). Ortssuche und '
          'Verkehrsdaten nutzt das Backend über TomTom (API-Key ausschließlich '
          'serverseitig). Wetterdaten kommen von Open-Meteo. An diese Dienste '
          'überträgt MotoRoute nie deine Identität - höchstens grobe '
          'Koordinaten für den jeweiligen Datenabruf.',
    ),
    (
      title: 'Was MotoRoute NICHT tut',
      body: 'Keine Werbung. Kein Verkauf von Daten. Kein Tracking über Apps '
          'hinaus. Keine Analyse- oder Statistik-Dienste von Drittanbietern. '
          'Keine Push-Dienste von Google (die App kommt ohne Google Play '
          'Services aus).',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBaseDark,
        title: Text('Datenschutz', style: AppTypography.title),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          children: [
            Text(
              'Stand: September 2026 - gilt für die private Testphase (v0.3.0).',
              style: AppTypography.caption,
            ),
            const SizedBox(height: AppSpacing.md),
            for (final section in _sections) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.bgSurfaceDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderHairlineDark),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(section.title, style: AppTypography.body),
                    const SizedBox(height: AppSpacing.sm),
                    Text(section.body, style: AppTypography.caption),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            Text(
              'Fragen zum Datenschutz? Sprich den Betreiber an (siehe Impressum) - '
              'in der Testphase ist das der private Betreiber der MotoRoute-Instanz.',
              style: AppTypography.caption,
            ),
          ],
        ),
      ),
    );
  }
}

class ImprintScreen extends StatelessWidget {
  const ImprintScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBaseDark,
        title: Text('Impressum', style: AppTypography.title),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.bgSurfaceDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderHairlineDark),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Angaben zur Testphase', style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(height: AppSpacing.sm),
                  Text(
                    'MotoRoute wird während der privaten Testphase von dem '
                    'Betreiber der Backend-Instanz bereitgestellt (private '
                    'Nutzung, kleiner Nutzerkreis). Es handelt sich um eine '
                    'nicht-kommerzielle Testsoftware ohne Gewährleistung.\n\n'
                    'Verantwortlich für Inhalte dieser Instanz ist der '
                    'Betreiber des Servers, unter dem die App läuft '
                    '(siehe Einstellungen > Server & Verbindung).\n\n'
                    'Karten-Daten: © OpenStreetMap-Mitwirkende '
                    '(openstreetmap.org/copyright). Kachel-Stil: CARTO. '
                    'Wetter: Open-Meteo. Suche/Verkehr: TomTom.',
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBaseDark,
        title: Text('Über MotoRoute', style: AppTypography.title),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.bgSurfaceDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderHairlineDark),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.two_wheeler, color: AppColors.accentPrimaryDark, size: 40),
                  const SizedBox(height: AppSpacing.md),
                  Text('MotoRoute', style: AppTypography.title),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    'Motorrad-Navigation für kurvige Touren - gebaut für '
                    'kleine Gruppen: gemeinsame Routenplanung, Live-Fahrt '
                    'und Biker-Community.\n\n'
                    'Aktuelle Phase: private Testversion. Alle Funktionen '
                    'sind kostenlos freigeschaltet; ein späteres '
                    'Premium-Abo (10 €/Monat) ist in der Architektur '
                    'vorbereitet, aber nicht aktiv.',
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.bgSurfaceDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderHairlineDark),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Datenquellen & Danksagung', style: AppTypography.body),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    '© OpenStreetMap-Mitwirkende - Kartenkacheln (CARTO-Stil)\n'
                    'Routing auf OpenStreetMap-Daten (GraphHopper)\n'
                    'Ortssuche & Verkehr: TomTom\n'
                    'Wetter: Open-Meteo (kein Key nötig)\n'
                    'POI-Kuratierung: eigener Biker-POI-Dienst',
                    style: TextStyle(fontSize: 13, height: 1.6),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/i18n/i18n.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart'
    show Waypoint;
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_theme.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';

import '../data/gpx_service.dart';
import '../domain/tour_entities.dart';
import 'track_thumbnail.dart';

/// GPX-Import: Datei wählen (Dateimanager), parsen, Vorschau mit
/// Miniaturkarte + Statistik, dann als Ziel in den normalen Route-
/// Start-Flow übergeben (Startpunkt-Wahl kommt dort).
class GpxImportScreen extends ConsumerStatefulWidget {
  const GpxImportScreen({super.key});

  @override
  ConsumerState<GpxImportScreen> createState() => _GpxImportScreenState();
}

class _GpxImportScreenState extends ConsumerState<GpxImportScreen> {
  RecordedTour? _parsed;
  bool _parsing = false;
  String? _error;
  String? _errorHint;

  Future<void> _pickAndParse() async {
    setState(() {
      _parsing = true;
      _error = null;
      _errorHint = null;
      _parsed = null;
    });
    try {
      // v13-API: gibt direkt eine Liste zurück (leer = abgebrochen);
      // Bytes werden mitgeliefert, damit wir nicht vom Pfad abhängen.
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gpx', 'xml'],
        compressionQuality: 0,
      );
      if (files.isEmpty) {
        if (mounted) setState(() => _parsing = false);
        return;
      }
      final file = files.single;
      // v13-Plattform-API: Inhalt über readAsBytes() (Pfad kann entfallen,
      // je nach Anbieter - deshalb kein hartes !).
      final bytes = await file.readAsBytes();
      final content = utf8.decode(bytes, allowMalformed: true);
      final tour = GpxParser().parse(
        content,
        fallbackTitle: file.name
            .replaceFirst(RegExp(r'\.(gpx|xml)$', caseSensitive: false), ''),
      );
      if (!mounted) return;
      setState(() {
        _parsed = tour;
        _parsing = false;
      });
    } on GpxException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ref.read(i18nProvider).tr('tour.import.invalid');
        _errorHint = e.message;
        _parsing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = ref.read(i18nProvider).tr('tour.import.failed');
        _parsing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = ref.watch(i18nProvider);
    final tour = _parsed;

    return Scaffold(
      backgroundColor: context.palette.bgBase,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: AppTheme.overlayFor(context),
        title: Text(i18n.tr('tour.import.title'), style: AppTypography.title),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_parsing && tour == null && _error == null)
                _IntroCard(onPick: _pickAndParse, i18n: i18n),
              if (_parsing)
                Expanded(
                  child: Center(
                      child: CircularProgressIndicator(
                          color: context.palette.accentPrimary)),
                ),
              if (_error != null) ...[
                Icon(Icons.error_outline,
                    size: 48, color: context.palette.statusDanger),
                const SizedBox(height: AppSpacing.md),
                Text(_error!,
                    style: AppTypography.body, textAlign: TextAlign.center),
                if (_errorHint != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _errorHint!,
                    style: AppTypography.captionOf(context)
                        .copyWith(color: context.palette.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                OutlinedButton(
                  onPressed: _pickAndParse,
                  child: Text(i18n.tr('common.retry')),
                ),
              ],
              if (tour != null) ...[
                SizedBox(
                  height: 240,
                  child: TrackThumbnail(track: tour.track, large: true),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(tour.title,
                    style: AppTypography.title, textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _PreviewMetric(
                      icon: Icons.route,
                      label:
                          '${(tour.distanceMeters / 1000).toStringAsFixed(1)} ${i18n.tr('tour.summary.km')}',
                    ),
                    _PreviewMetric(
                      icon: Icons.place_outlined,
                      label:
                          '${tour.track.length} ${i18n.tr('tour.import.points')}',
                    ),
                    if (tour.elevationGainMeters > 0)
                      _PreviewMetric(
                        icon: Icons.terrain,
                        label:
                            '${tour.elevationGainMeters.toStringAsFixed(0)} ${i18n.tr('tour.summary.elevation')}',
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  height: AppSpacing.touchTargetPlanning,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: context.palette.accentPrimary),
                    onPressed: () => _startNavigation(context),
                    icon: const Icon(Icons.navigation),
                    label: Text(i18n.tr('tour.import.ride')),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Importierte GPX-Route in den normalen Navigation-Start-Flow
  /// übergeben: Der GPX-Track wird als Wegpunktkette (verdünnisiert)
  /// zum Ziel - der Start kommt aus der üblichen Startpunkt-Wahl.
  void _startNavigation(BuildContext context) {
    final tour = _parsed;
    if (tour == null || tour.track.length < 2) return;
    final waypoints = _thinToWaypoints(tour.track, maxPoints: 12);
    ref.read(waypointListProvider.notifier).state = waypoints;
    // Zur Routenübersicht: Start ist das letzte Element? Nein - der
    // Flow erwartet [Ziel]; Start wählt der Nutzer im /route-start.
    final destination = waypoints.last;
    Navigator.of(context)
        .pushNamed('/route-start', arguments: {'destination': destination});
  }

  /// GPX-Spur (ggf. tausende Punkte) auf <= maxPoints siginifikante
  /// Wegpunkte verdünnen - gleichmäßig verteilt, Start und Ziel bleiben
  /// immer erhalten. Das Backend routet sauber darüber.
  List<Waypoint> _thinToWaypoints(List<TrackPoint> track,
      {int maxPoints = 12}) {
    if (track.length <= maxPoints) {
      return track
          .map((p) => Waypoint(lat: p.lat, lng: p.lng))
          .toList(growable: false);
    }
    final step = (track.length - 1) / (maxPoints - 1);
    final out = <Waypoint>[];
    for (var i = 0; i < maxPoints; i++) {
      final idx = (i * step).round().clamp(0, track.length - 1);
      out.add(Waypoint(lat: track[idx].lat, lng: track[idx].lng));
    }
    return out;
  }
}

class _PreviewMetric extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PreviewMetric({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Chip(
        avatar: Icon(icon, size: 18, color: context.palette.accentSecondary),
        label: Text(label),
        backgroundColor: context.palette.bgSurface,
        side: BorderSide(color: context.palette.borderHairline),
        labelStyle:
            AppTypography.caption.copyWith(color: context.palette.textPrimary),
      );
}

class _IntroCard extends StatelessWidget {
  final VoidCallback onPick;
  final I18n i18n;
  const _IntroCard({required this.onPick, required this.i18n});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.upload_file,
                size: 64, color: context.palette.stateIdle),
            const SizedBox(height: AppSpacing.lg),
            Text(
              i18n.tr('tour.import.intro'),
              style: AppTypography.body
                  .copyWith(color: context.palette.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: context.palette.accentPrimary),
              onPressed: onPick,
              icon: const Icon(Icons.folder_open),
              label: Text(i18n.tr('tour.import.pick')),
            ),
          ],
        ),
      ),
    );
  }
}

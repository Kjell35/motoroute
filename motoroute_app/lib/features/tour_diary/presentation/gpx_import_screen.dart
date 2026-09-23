
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/i18n/i18n.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart' show Waypoint;
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
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

  Future<void> _pickAndParse() async {
    setState(() {
      _parsing = true;
      _error = null;
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
        setState(() => _parsing = false);
        return;
      }
      final file = files.single;
      // v13-Plattform-API: Inhalt über readAsBytes() (Pfad kann entfallen,
      // je nach Anbieter - deshalb kein hartes !).
      final bytes = await file.readAsBytes();
      final content = String.fromCharCodes(bytes);
      final tour = GpxParser().parse(content, fallbackTitle: file.name.replaceAll('.gpx', '').replaceAll('.xml', ''));
      if (!mounted) return;
      setState(() {
        _parsed = tour;
        _parsing = false;
      });
    } on GpxException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
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
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
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
                const Expanded(
                  child: Center(child: CircularProgressIndicator(color: AppColors.accentPrimaryDark)),
                ),
              if (_error != null) ...[
                const Icon(Icons.error_outline, size: 48, color: AppColors.statusDanger),
                const SizedBox(height: AppSpacing.md),
                Text(_error!, style: AppTypography.body, textAlign: TextAlign.center),
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
                Text(tour.title, style: AppTypography.title, textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${tour.track.length} ${i18n.tr('tour.import.points')}',
                  style: AppTypography.caption,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  height: AppSpacing.touchTargetPlanning,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.accentPrimaryDark),
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
    Navigator.of(context).pushNamed('/route-start', arguments: {'destination': destination});
  }

  /// GPX-Spur (ggf. tausende Punkte) auf <= maxPoints siginifikante
  /// Wegpunkte verdünnen - gleichmäßig verteilt, Start und Ziel bleiben
  /// immer erhalten. Das Backend routet sauber darüber.
  List<Waypoint> _thinToWaypoints(List<TrackPoint> track, {int maxPoints = 12}) {
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
            const Icon(Icons.upload_file, size: 64, color: AppColors.textMutedDark),
            const SizedBox(height: AppSpacing.lg),
            Text(
              i18n.tr('tour.import.intro'),
              style: AppTypography.body.copyWith(color: AppColors.textSecondaryDark),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.accentPrimaryDark),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/auth_providers.dart';
import '../ride_history_repository.dart';

/// Öffentliche Fahrhistorie eines Benutzers (aus dem Chat-Profil-Sheet).
///
/// DATENSCHUTZ: Der Screen rendert NUR, was das Backend ausgeliefert hat
/// - private Profile zeigen nur Basisdaten + Hinweis, Koordinaten fehlen
/// bei hide_start_end, Tracks fehlen bei share_track=false. Es gibt hier
/// keinen lokalen Fallback, der mehr zeigen könnte.
class ProfileHistoryScreen extends ConsumerStatefulWidget {
  const ProfileHistoryScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<ProfileHistoryScreen> createState() => _ProfileHistoryScreenState();
}

class _ProfileHistoryScreenState extends ConsumerState<ProfileHistoryScreen> {
  PublicProfileHistory? _history;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = ref.read(authControllerProvider.notifier).accessToken;
      if (token == null) {
        setState(() {
          _error = 'Nicht angemeldet';
          _loading = false;
        });
        return;
      }
      final data = await ref
          .read(rideHistoryRepositoryProvider)
          .fetchPublicProfile(token, widget.userId);
      if (!mounted) return;
      setState(() {
        _history = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = ref.watch(i18nProvider);
    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(i18n.tr('rideHistory.title'), style: AppTypography.title),
      ),
      body: _buildBody(context, i18n),
    );
  }

  Widget _buildBody(BuildContext context, I18n i18n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accentPrimaryDark));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(i18n.tr('rideHistory.loadError'), style: AppTypography.body),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: Text(i18n.tr('rideHistory.retry'))),
          ],
        ),
      );
    }
    final h = _history!;
    if (h.isPrivate) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48, color: AppColors.textSecondaryDark),
              const SizedBox(height: 12),
              Text(i18n.tr('rideHistory.private'), style: AppTypography.title, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                i18n.tr('rideHistory.privateHint'),
                style: AppTypography.body,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatHeader(h: h, i18n: i18n),
          if (h.rides.isNotEmpty || h.places.isNotEmpty) ...[
            const SizedBox(height: 16),
            _HistoryMap(rides: h.rides, places: h.places),
          ],
          if (h.regions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(i18n.tr('rideHistory.regions'), style: AppTypography.title),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final r in h.regions.take(12)) Chip(label: Text(r))],
            ),
          ],
          const SizedBox(height: 16),
          Text(i18n.tr('rideHistory.rides'), style: AppTypography.title),
          const SizedBox(height: 8),
          if (h.rides.isEmpty)
            Text(i18n.tr('rideHistory.noRides'), style: AppTypography.body)
          else
            ...[for (final ride in h.rides) _RideCard(ride: ride, i18n: i18n)],
          const SizedBox(height: 16),
          Text(i18n.tr('rideHistory.places'), style: AppTypography.title),
          const SizedBox(height: 8),
          if (h.places.isEmpty)
            Text(i18n.tr('rideHistory.noPlaces'), style: AppTypography.body)
          else
            ...[for (final p in h.places.take(30)) _PlaceTile(place: p)],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// Auth-Token-Provider (kleine Brücke, damit der Screen nicht das ganze
/// Auth-Feature importieren muss).
final authTokenProvider = Provider<String?>((ref) => null);

class _StatHeader extends StatelessWidget {
  final PublicProfileHistory h;
  final I18n i18n;
  const _StatHeader({required this.h, required this.i18n});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgSurfaceDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            h.displayName ?? h.username ?? '???',
            style: AppTypography.title,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Stat(value: '${h.rideCount}', label: i18n.tr('rideHistory.statRides')),
              _Stat(value: formatDistanceMeters(h.totalKm * 1000), label: i18n.tr('rideHistory.statKm')),
              _Stat(
                value: formatDurationSeconds(h.totalHours * 3600),
                label: i18n.tr('rideHistory.statTime'),
              ),
              _Stat(
                value: '${h.totalElevationGain.round()} m',
                label: i18n.tr('rideHistory.statElevation'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: AppTypography.title),
        const SizedBox(height: 2),
        Text(label, style: AppTypography.caption),
      ],
    );
  }
}

/// Übersichtskarte: alle freigegebenen Tracks + Orte. Offline-fähige
/// Zeichenfläche (CustomPainter) - dieselbe Technik wie die Tour-
/// Miniaturkarte im Tagebuch, kein Kartendienst nötig.
class _HistoryMap extends StatelessWidget {
  final List<PublicRide> rides;
  final List<PublicPlace> places;
  const _HistoryMap({required this.rides, required this.places});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: AppColors.bgSurfaceDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CustomPaint(
          painter: _HistoryMapPainter(rides: rides, places: places),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _HistoryMapPainter extends CustomPainter {
  final List<PublicRide> rides;
  final List<PublicPlace> places;
  _HistoryMapPainter({required this.rides, required this.places});

  @override
  void paint(Canvas canvas, Size size) {
    final allPoints = <LatLngPoint>[
      for (final r in rides) ...r.track,
      for (final p in places) LatLngPoint(lat: p.lat, lng: p.lng),
    ];
    if (allPoints.isEmpty) return;

    double minLat = allPoints.first.lat, maxLat = allPoints.first.lat;
    double minLng = allPoints.first.lng, maxLng = allPoints.first.lng;
    for (final p in allPoints) {
      minLat = minLat < p.lat ? minLat : p.lat;
      maxLat = maxLat > p.lat ? maxLat : p.lat;
      minLng = minLng < p.lng ? minLng : p.lng;
      maxLng = maxLng > p.lng ? maxLng : p.lng;
    }
    const padding = 24.0;
    final spanLat = (maxLat - minLat).abs().clamp(0.0001, 180);
    final spanLng = (maxLng - minLng).abs().clamp(0.0001, 360);
    final scale = ((size.width - 2 * padding) / spanLng)
        .clamp(0.0, (size.height - 2 * padding) / spanLat);
    final offsetX = (size.width - spanLng * scale) / 2;
    final offsetY = (size.height - spanLat * scale) / 2;

    Offset project(LatLngPoint p) => Offset(
          offsetX + (p.lng - minLng) * scale,
          offsetY + (maxLat - p.lat) * scale,
        );

    // Tracks in Akzentfarbe.
    for (final ride in rides) {
      if (ride.track.length < 2) continue;
      final paint = Paint()
        ..color = AppColors.accentPrimaryDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      final path = Path()..moveTo(project(ride.track.first).dx, project(ride.track.first).dy);
      for (final p in ride.track.skip(1)) {
        path.lineTo(project(p).dx, project(p).dy);
      }
      canvas.drawPath(path, paint);
    }

    // Orte als Punkte.
    for (final place in places) {
      canvas.drawCircle(
        project(LatLngPoint(lat: place.lat, lng: place.lng)),
        5,
        Paint()..color = AppColors.statusWarning,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HistoryMapPainter oldDelegate) =>
      oldDelegate.rides != rides || oldDelegate.places != places;
}

class _RideCard extends StatelessWidget {
  final PublicRide ride;
  final I18n i18n;
  const _RideCard({required this.ride, required this.i18n});

  static String two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final d = ride.startedAt;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgSurfaceDark,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(ride.title, style: AppTypography.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (ride.region != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.bgBaseDark,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(ride.region!, style: AppTypography.caption),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${two(d.day)}.${two(d.month)}.${d.year} · ${two(d.hour)}:${two(d.minute)}',
            style: AppTypography.caption,
          ),
          const SizedBox(height: 10),
          if (ride.track.length >= 2)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 110,
                width: double.infinity,
                child: CustomPaint(painter: _RideTrackPainter(ride: ride)),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Stat(value: formatDistanceMeters(ride.km * 1000), label: 'km'),
              _Stat(
                value: formatDurationSeconds(ride.hours * 3600),
                label: 'Fahrzeit',
              ),
              _Stat(value: '${ride.elevationGainMeters.round()} m', label: 'Höhe'),
            ],
          ),
          if (ride.startLabel != null || ride.endLabel != null) ...[
            const SizedBox(height: 10),
            Text(
              '${ride.startLabel ?? '?'} → ${ride.endLabel ?? '?'}',
              style: AppTypography.caption,
            ),
          ],
          if (ride.description != null && ride.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(ride.description!, style: AppTypography.body),
          ],
        ],
      ),
    );
  }
}

class _RideTrackPainter extends CustomPainter {
  final PublicRide ride;
  _RideTrackPainter({required this.ride});

  @override
  void paint(Canvas canvas, Size size) {
    if (ride.track.length < 2) return;
    double minLat = ride.track.first.lat, maxLat = minLat;
    double minLng = ride.track.first.lng, maxLng = minLng;
    for (final p in ride.track) {
      minLat = minLat < p.lat ? minLat : p.lat;
      maxLat = maxLat > p.lat ? maxLat : p.lat;
      minLng = minLng < p.lng ? minLng : p.lng;
      maxLng = maxLng > p.lng ? maxLng : p.lng;
    }
    const padding = 16.0;
    final spanLat = (maxLat - minLat).abs().clamp(0.0001, 180);
    final spanLng = (maxLng - minLng).abs().clamp(0.0001, 360);
    final scale = ((size.width - 2 * padding) / spanLng)
        .clamp(0.0, (size.height - 2 * padding) / spanLat);
    final offsetX = (size.width - spanLng * scale) / 2;
    final offsetY = (size.height - spanLat * scale) / 2;

    Offset project(LatLngPoint p) => Offset(
          offsetX + (p.lng - minLng) * scale,
          offsetY + (maxLat - p.lat) * scale,
        );

    final paint = Paint()
      ..color = AppColors.accentPrimaryDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(project(ride.track.first).dx, project(ride.track.first).dy);
    for (final p in ride.track.skip(1)) {
      path.lineTo(project(p).dx, project(p).dy);
    }
    canvas.drawPath(path, paint);

    // Start (grün) / Ziel (rot) - nur wenn Koordinaten freigegeben sind.
    final start = ride.start;
    final end = ride.end;
    if (start != null) {
      canvas.drawCircle(project(start), 5, Paint()..color = AppColors.statusWarning);
    }
    if (end != null) {
      canvas.drawCircle(project(end), 5, Paint()..color = AppColors.statusDanger);
    }
  }

  @override
  bool shouldRepaint(covariant _RideTrackPainter oldDelegate) => oldDelegate.ride != ride;
}

class _PlaceTile extends StatelessWidget {
  final PublicPlace place;
  const _PlaceTile({required this.place});

  IconData get _icon => switch (place.category) {
        'fuel' => Icons.local_gas_station,
        'restaurant' => Icons.restaurant,
        'hotel' => Icons.hotel,
        'camping' => Icons.forest,
        'bikertreff' => Icons.local_bar,
        _ => Icons.place,
      };

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(_icon, color: AppColors.accentPrimaryDark),
      title: Text(place.label, style: AppTypography.body),
      subtitle: Text(
        place.visitCount == 1 ? '1 Besuch' : '${place.visitCount} Besuche',
        style: AppTypography.caption,
      ),
    );
  }
}

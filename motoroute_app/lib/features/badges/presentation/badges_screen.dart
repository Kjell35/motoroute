import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/network/error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/auth_providers.dart';
import '../badges_repository.dart';
import 'badge_icon.dart';

/// Trophäenschrank ("Pass-Knacker"): Alle Badges als Grid - freige-
/// schaltet mit farbigem Icon + Datum, gesperrt ausgegraut mit Schloss.
/// Über den Floating-Button macht der Biker einen GPS-Check-in; trifft
/// er einen Pass/Treff, erscheint direkt die Freischalt-Feier.
class BadgesScreen extends ConsumerStatefulWidget {
  const BadgesScreen({super.key});

  @override
  ConsumerState<BadgesScreen> createState() => _BadgesScreenState();
}

class _BadgesScreenState extends ConsumerState<BadgesScreen> {
  BadgeShelf? _shelf;
  String? _error;
  bool _loading = true;
  bool _checkingIn = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final token = ref.read(badgesTokenProvider);
    final i18n = ref.read(i18nProvider);
    if (token == null) {
      setState(() {
        _error = i18n.tr('badges.loginRequired');
        _loading = false;
      });
      return;
    }
    try {
      final shelf = await ref.read(badgesRepositoryProvider).shelf(token: token);
      if (!mounted) return;
      setState(() {
        _shelf = shelf;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = technicalCause(e);
        _loading = false;
      });
    }
  }

  /// GPS-Check-in: Position holen (Berechtigungen im Screen behandelt)
  /// und an das Backend schicken. Ergebnis = Feier-Dialog oder Hinweis.
  Future<void> _checkin() async {
    final i18n = ref.read(i18nProvider);
    final token = ref.read(badgesTokenProvider);
    if (token == null) {
      _toast(i18n.tr('badges.loginRequired'));
      return;
    }
    setState(() => _checkingIn = true);
    try {
      // 1) Dienst aktiv? (Sonst wirft getLocationPositionStack schiefer)
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() => _checkingIn = false);
        _toast(i18n.tr('badges.gpsDenied'));
        return;
      }
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (!mounted) return;
        setState(() => _checkingIn = false);
        _toast(i18n.tr('badges.gpsOff'));
        return;
      }
      // 2) Position mit motorradtauglichem Genauigkeits-Filter.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      // 3) An den Server - die DB entscheidet per ST_DWithin.
      final result = await ref
          .read(badgesRepositoryProvider)
          .checkin(token: token, lat: pos.latitude, lon: pos.longitude);
      if (!mounted) return;
      setState(() => _checkingIn = false);
      if (result.unlockedNow.isNotEmpty) {
        await _celebrate(result);
        await _load();
      } else if (result.revisitedTitles.isNotEmpty) {
        _toast(i18n.tr('badges.revisited', {
          'title': result.revisitedTitles.join(', '),
          'count': '${result.totalUnlocked}',
        }));
      } else {
        _toast(i18n.tr('badges.nothingNearby'));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _checkingIn = false);
      _toast(i18n.tr('badges.checkinFailed', {'cause': technicalCause(e)}));
    }
  }

  Future<void> _celebrate(CheckinResult result) async {
    final i18n = ref.read(i18nProvider);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgSurfaceRaisedDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          i18n.tr('badges.unlockedTitle'),
          style: AppTypography.title.copyWith(color: AppColors.textPrimaryDark),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final b in result.unlockedNow) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  BadgeIcon(iconUrl: b.iconUrl, category: b.category),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.title,
                          style: AppTypography.bodyStrong
                              .copyWith(color: AppColors.textPrimaryDark),
                        ),
                        Text(
                          i18n.tr('badges.metersAway', {'m': '${b.distanceMeters}'}),
                          style:
                              AppTypography.caption.copyWith(color: AppColors.textSecondaryDark),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Text(
              i18n.tr('badges.unlockedCount', {'count': '${result.totalUnlocked}'}),
              style: AppTypography.caption.copyWith(color: AppColors.textSecondaryDark),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('🏍️'),
          ),
        ],
      ),
    );
  }

  /// Admin: neuen Pass/Treff/Landmark anlegen (ohne SQL im Dashboard).
  Future<void> _adminCreateBadge() async {
    final i18n = ref.read(i18nProvider);
    final token = ref.read(badgesTokenProvider);
    if (token == null) {
      _toast(i18n.tr('badges.loginRequired'));
      return;
    }
    final title = TextEditingController();
    final description = TextEditingController();
    final lat = TextEditingController();
    final lon = TextEditingController();
    final radius = TextEditingController(text: '150');
    final iconUrl = TextEditingController();
    var category = BadgeCategory.pass;
    String? formError;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          backgroundColor: AppColors.bgSurfaceRaisedDark,
          title: Text(i18n.tr('badges.adminAdd'), style: AppTypography.title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: title, decoration: InputDecoration(labelText: i18n.tr('badges.adminTitle'))),
                TextField(controller: description, decoration: InputDecoration(labelText: i18n.tr('badges.adminDescription'))),
                DropdownButton<BadgeCategory>(
                  value: category,
                  isExpanded: true,
                  items: [
                    for (final c in BadgeCategory.values)
                      DropdownMenuItem(value: c, child: Text('${c.emoji} ${c.name}')),
                  ],
                  onChanged: (v) => setLocal(() => category = v ?? category),
                ),
                TextField(
                  controller: lat,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: InputDecoration(labelText: i18n.tr('badges.adminLat')),
                ),
                TextField(
                  controller: lon,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: InputDecoration(labelText: i18n.tr('badges.adminLon')),
                ),
                TextField(
                  controller: radius,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: i18n.tr('badges.adminRadius')),
                ),
                TextField(controller: iconUrl, decoration: InputDecoration(labelText: i18n.tr('badges.adminIconUrl'))),
                if (formError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(formError!, style: AppTypography.caption.copyWith(color: AppColors.statusDanger)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(i18n.tr('badges.adminCancel')),
            ),
            TextButton(
              onPressed: () {
                final la = double.tryParse(lat.text.trim().replaceAll(',', '.'));
                final lo = double.tryParse(lon.text.trim().replaceAll(',', '.'));
                final r = int.tryParse(radius.text.trim());
                if (title.text.trim().length < 2 ||
                    la == null || la < -90 || la > 90 ||
                    lo == null || lo < -180 || lo > 180 ||
                    r == null || r < 20 || r > 500) {
                  setLocal(() => formError = i18n.tr('badges.adminInvalid'));
                  return;
                }
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(i18n.tr('badges.adminSave')),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      await ref.read(badgesRepositoryProvider).createBadge(
            token: token,
            title: title.text.trim(),
            description: description.text.trim(),
            category: category,
            lat: double.parse(lat.text.trim().replaceAll(',', '.')),
            lon: double.parse(lon.text.trim().replaceAll(',', '.')),
            radiusMeters: int.parse(radius.text.trim()),
            iconUrl: iconUrl.text.trim(),
          );
      _toast(i18n.tr('badges.adminCreated'));
      await _load();
    } catch (e) {
      _toast(i18n.tr('badges.adminFailed', {'cause': technicalCause(e)}));
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.bgSurfaceRaisedDark),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = ref.watch(i18nProvider);
    final shelf = _shelf;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? AppColors.bgSurfaceDark : AppColors.bgSurfaceLight;
    final raised = dark ? AppColors.bgSurfaceRaisedDark : AppColors.bgSurfaceRaisedLight;
    final textPrimary = dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary = dark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: surface,
        title: Text(i18n.tr('badges.title'), style: AppTypography.title),
        actions: [
          if (ref.watch(authControllerProvider).user?.isAdmin ?? false)
            IconButton(
              tooltip: i18n.tr('badges.adminAdd'),
              icon: const Icon(Icons.add_location_alt_outlined),
              onPressed: _adminCreateBadge,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _checkingIn ? null : _checkin,
        backgroundColor: AppColors.accentPrimaryDark,
        foregroundColor: Colors.white,
        icon: _checkingIn
            ? const SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.explore),
        label: Text(i18n.tr('badges.checkin'), style: AppTypography.bodyStrong),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorCard(
                  message: _error!,
                  onRetry: _load,
                  raised: raised,
                  textPrimary: textPrimary,
                  i18n: i18n,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    children: [
                      // Fortschritt: "7 / 19 freigeschaltet"
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: raised,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            const Text('🏆', style: TextStyle(fontSize: 30)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    i18n.tr('badges.progress', {
                                      'unlocked': '${shelf!.unlockedCount}',
                                      'total': '${shelf.totalCount}',
                                    }),
                                    style: AppTypography.bodyStrong.copyWith(color: textPrimary),
                                  ),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(                                          value: shelf.totalCount == 0
                                          ? 0
                                          : shelf.unlockedCount / shelf.totalCount,
                                      minHeight: 8,
                                      backgroundColor: textSecondary.withOpacity(0.2),
                                      valueColor: AlwaysStoppedAnimation(AppColors.accentPrimaryDark),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Grid: freigeschaltet = farbig + Datum, gesperrt = grau + Schloss.
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final cols = (constraints.maxWidth / 160).floor().clamp(2, 4);
                          return GridView.count(
                            crossAxisCount: cols,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.82,
                            children: [
                              for (final b in shelf.badges)
                                _BadgeCard(
                                  badge: b,
                                  i18n: i18n,
                                  raised: raised,
                                  textPrimary: textPrimary,
                                  textSecondary: textSecondary,
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _BadgeCard extends StatelessWidget {
  final BadgeItem badge;
  final I18n i18n;
  final Color raised;
  final Color textPrimary;
  final Color textSecondary;

  const _BadgeCard({
    required this.badge,
    required this.i18n,
    required this.raised,
    required this.textPrimary,
    required this.textSecondary,
  });

  /// Kompaktes Datum (TT.MM.JJJJ) - gleiche Konvention wie im Tour-Tagebuch.
  String _formatDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = badge.unlocked;
    final color = switch (badge.category) {
      // Farbige Icons je Kategorie - nur wenn freigeschaltet.
      BadgeCategory.pass => AppColors.statusSuccess,
      BadgeCategory.meeting => AppColors.accentPrimaryDark,
      BadgeCategory.sight => AppColors.statusWarning,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: raised,
        borderRadius: BorderRadius.circular(16),
        border: unlocked ? Border.all(color: color.withOpacity(0.6), width: 1.5) : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon: Freigeschaltet farbig, gesperrt grau mit Schloss-Overlay.
          Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: unlocked ? 1 : 0.35,
                child: BadgeIcon(iconUrl: badge.iconUrl, category: badge.category),
              ),
              if (!unlocked)
                Icon(Icons.lock, size: 20, color: textSecondary),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            unlocked ? badge.title : '???',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyStrong.copyWith(color: textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            unlocked
                // Datum der Freischaltung direkt an der Trophäe.
                ? _formatDate(badge.unlockedAt ?? DateTime.now())
                : i18n.tr('badges.lockedHint'),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(
              color: unlocked ? color : textSecondary,
              fontWeight: unlocked ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final Color raised;
  final Color textPrimary;
  final I18n i18n;

  const _ErrorCard({
    required this.message,
    required this.onRetry,
    required this.raised,
    required this.textPrimary,
    required this.i18n,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_outlined, size: 44, color: AppColors.textSecondaryDark),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: AppTypography.body),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: Text(i18n.tr('common.retry'))),
          ],
        ),
      ),
    );
  }
}

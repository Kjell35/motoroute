import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/constants/route_enums.dart';
import 'package:motoroute_app/core/i18n/i18n.dart';
import 'package:motoroute_app/core/network/error_reporter.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_theme.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';
import 'package:motoroute_app/core/utils/formatters.dart' show DistanceUnit;
import 'package:motoroute_app/features/map/data/location_repository.dart';
import 'package:motoroute_app/features/settings/offline_maps.dart';
import 'package:motoroute_app/features/settings/theme_mode.dart';
import 'package:motoroute_app/features/auth/auth_providers.dart';
import 'package:motoroute_app/features/chat/chat_providers.dart';
import 'package:motoroute_app/features/chat/data/chat_repository.dart';
import 'package:motoroute_app/features/map/data/map_style.dart';
import 'package:motoroute_app/features/ride_history/ride_history_settings.dart';
import 'package:motoroute_app/features/settings/energy_saver.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Screen 11: Einstellungen (vollständig, neu gruppiert).
///
/// Aufbau von oben nach unten (die wichtigsten Bereiche zuerst):
///   1. Fahrzeug & Navigation - Fahrzeugtyp, Einheiten, Energiesparen
///   2. Konto - Profil, Passwort, Abmelden, Konto löschen
///   3. Karte - Kartenstil (hell/dunkel) + Offline-Regionen
///   4. Community (eingeklappt) - Chat-Status/-Name, Online-Status,
///      Benachrichtigungen, Fahrhistorie-Privatsphäre
///   5. Sprache & Erscheinungsbild (eingeklappt)
///   6. Recht & Info (eingeklappt) - Datenschutz/Impressum/Über/Version
///
/// Bewusst NICHT vorhanden: manuelle Token-/Key-/URL-Eingaben. Chat und
/// Konto laufen ausschließlich über die App-Anmeldung (Auth-Brücke);
/// Backend- und Garage-URL sind fest ins APK gebacken.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// Einklapp-Status pro Sektion (stabile IDs, nicht die Titel - sonst
  /// kippt der Zustand beim Sprachwechsel). Sekundäres startet eingeklappt.
  final Set<String> _collapsed = {'community', 'language', 'legal'};

  String _appVersion = '…';

  /// Farben des aktiven Schemas (hell/dunkel). Der Screen faerbt
  /// Flaechen und Texte selbst, deshalb loest er die Tokens hier auf,
  /// statt sie aus dem Theme zu ziehen.
  AppPalette get _colors => AppPalette.of(Theme.of(context).brightness);

  /// Sekundaerer Textstil des Schemas - `AppTypography.caption` traegt
  /// eine feste dunkle Farbe und waere im hellen Schema unlesbar.
  TextStyle get _caption =>
      AppTypography.caption.copyWith(color: _colors.textSecondary);

  @override
  void initState() {
    super.initState();
    // Echte Version aus der APK (pubspec versionName) statt hardcodierter
    // Zahl - die Anzeige stimmt dann mit dem Release-Tag überein.
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _appVersion = info.version);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final vehicleType = ref.watch(vehicleTypeProvider);
    final auth = ref.watch(authControllerProvider);
    final unit = ref.watch(distanceUnitProvider);
    final energy = ref.watch(energySaverControllerProvider);
    final voiceOn = ref.watch(voiceAnnouncementsEnabledProvider);
    final i18n = ref.watch(i18nProvider);

    final user = auth.user;
    return Scaffold(
      backgroundColor: _colors.bgBase,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        // Durchsichtige AppBar: Flutter schaetzt die Helligkeit aus
        // `Colors.transparent` und waehlt sonst helle Symbole.
        systemOverlayStyle:
            Theme.of(context).brightness == Brightness.dark
                ? AppTheme.statusOverlayDark
                : AppTheme.statusOverlayLight,
        title: Text(i18n.tabSettings, style: AppTypography.title),
      ),
      // Calimoto-inspirierter Profil-Header: großer Avatar-Kreis,
      // Name + E-Mail darunter - gibt der Einstellungs-Seite ein
      // Persoenliches Gesicht (Vorbild: Profil-Tab des Referenz-Screens).
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          children: [
            Center(
              child: Column(
                children: [
                  // AuthUser hat bewusst kein avatarUrl (App setzt es
                  // nie) - der Initialen-/Icon-Fallback reicht hier.
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: _colors.bgSurfaceRaised,
                    child: Icon(Icons.person,
                        size: 44, color: _colors.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    user?.displayName ?? user?.email ?? '',
                    style: AppTypography.title.copyWith(fontSize: 20),
                  ),
                  if (user?.email != null)
                    Text(user!.email,
                        style: AppTypography.body
                            .copyWith(color: _colors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // --------------------------------------------- 1. Navigation
            _buildSection('nav', i18n.navigation,
                icon: Icons.navigation_outlined,
                children: [
                  _controlTile(
                    icon: Icons.motorcycle,
                    title: i18n.tr('settings.vehicleDefault'),
                    subtitle: i18n.tr('settings.vehicleDefaultHint'),
                    control: SegmentedButton<VehicleType>(
                      segments: const [
                        ButtonSegment(
                            value: VehicleType.motorcycle,
                            icon: Icon(Icons.two_wheeler, size: 18)),
                        ButtonSegment(
                            value: VehicleType.car,
                            icon: Icon(Icons.directions_car, size: 18)),
                        ButtonSegment(
                            value: VehicleType.bicycle,
                            icon: Icon(Icons.pedal_bike, size: 18)),
                      ],
                      selected: {vehicleType},
                      onSelectionChanged: (selection) {
                        ref.read(vehicleTypeProvider.notifier).state =
                            selection.first;
                        persistVehicleType(selection.first);
                      },
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.straighten,
                        color: _colors.textSecondary, size: 20),
                    title: Text(i18n.tr('settings.units'),
                        style: AppTypography.body),
                    subtitle: Text(
                        unit == DistanceUnit.kilometers
                            ? i18n.tr('settings.units.km')
                            : i18n.tr('settings.units.mi'),
                        style: _caption),
                    trailing: SegmentedButton<DistanceUnit>(
                      segments: const [
                        ButtonSegment(
                            value: DistanceUnit.kilometers, label: Text('km')),
                        ButtonSegment(
                            value: DistanceUnit.miles, label: Text('mi')),
                      ],
                      selected: {unit},
                      onSelectionChanged: (selection) {
                        ref.read(distanceUnitProvider.notifier).state =
                            selection.first;
                        persistDistanceUnit(selection.first);
                      },
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                  // Sprachansagen: DERSSELBE Provider wie der Lautsprecher-
                  // Toggle am aktiven Nav-Screen - beide Orte bleiben immer
                  // synchron, die Persistierung läuft über initSessionSettings.
                  _buildSwitchTile(
                    Icons.record_voice_over,
                    i18n.tr('settings.voiceAnnouncements'),
                    voiceOn,
                    (value) {
                      ref
                          .read(voiceAnnouncementsEnabledProvider.notifier)
                          .state = value;
                      unawaited(persistVoiceAnnouncementsEnabled(value));
                    },
                  ),
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.record_voice_over,
                        color: _colors.textMuted, size: 18),
                    title: Text(
                      i18n.tr('settings.voiceAnnouncements.desc'),
                      style: _caption,
                    ),
                  ),
                  _buildSwitchTile(
                    Icons.battery_saver,
                    i18n.tr('settings.energySaver'),
                    energy.mode != EnergySaverMode.off,
                    (value) async {
                      await ref
                          .read(energySaverControllerProvider.notifier)
                          .setEnabled(value);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              value
                                  ? i18n.tr('settings.energySaver.onHint')
                                  : i18n.tr('settings.energySaver.offHint'),
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  if (energy.mode != EnergySaverMode.off)
                    ListTile(
                      leading: Icon(Icons.bolt,
                          color: _colors.statusWarning, size: 20),
                      title: Text(
                        energy.mode == EnergySaverMode.critical
                            ? i18n.tr('settings.energySaver.critical')
                            : i18n.tr('settings.energySaver.throttled'),
                        style: _caption,
                      ),
                      subtitle: Text(
                          i18n.tr('settings.energySaver.battery',
                              {'level': '${energy.batteryLevelPercent}'}),
                          style: _caption),
                    ),
                ]),
            const SizedBox(height: AppSpacing.lg),

            // -------------------------------------------------- 2. Konto
            _buildAccountSection(context, ref, auth),
            const SizedBox(height: AppSpacing.lg),

            // -------------------------------------------------- 3. Karte
            _buildMapSection(),
            const SizedBox(height: AppSpacing.lg),

            // ---------------------------------------------- 4. Community
            _buildSection('community', i18n.tr('settings.community'),
                icon: Icons.forum_outlined,
                children: [
                  ..._notificationChildren(),
                  Divider(height: 1, color: _colors.borderHairline),
                  ..._chatChildren(),
                  Divider(height: 1, color: _colors.borderHairline),
                  ..._rideHistoryChildren(),
                ]),
            const SizedBox(height: AppSpacing.lg),

            // ------------------------------------------------ 5. Sprache
            _buildLanguageSection(),
            const SizedBox(height: AppSpacing.lg),

            // -------------------------------------------- 6. Recht & Info
            _buildSection('legal', i18n.tr('settings.legal'),
                icon: Icons.gavel_outlined,
                children: [
                  _buildListTile(Icons.privacy_tip_outlined,
                      i18n.tr('settings.privacy'),
                      i18n.tr('settings.legal.privacyHint'), () {
                    Navigator.of(context).pushNamed('/privacy');
                  }),
                  _buildListTile(Icons.description_outlined,
                      i18n.tr('settings.imprint'),
                      i18n.tr('settings.legal.imprintHint'), () {
                    Navigator.of(context).pushNamed('/imprint');
                  }),
                  _buildListTile(Icons.info_outline,
                      i18n.tr('settings.about'),
                      i18n.tr('settings.legal.aboutHint'), () {
                    Navigator.of(context).pushNamed('/about');
                  }),
                  ListTile(
                    dense: true,
                    title: Text(i18n.appVersion, style: AppTypography.body),
                    trailing: Text(_appVersion, style: _caption),
                  ),
                ]),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // 1/2: Konto - Profil, Passwort, Konto löschen, Abmelden - alles echt.
  // ------------------------------------------------------------------
  Widget _buildAccountSection(
      BuildContext context, WidgetRef ref, AuthState auth) {
    final i18n = ref.watch(i18nProvider);
    if (!auth.isAuthenticated) {
      return _buildSection('account', i18n.tr('settings.account'),
          icon: Icons.person_outline,
          children: [
            ListTile(
              leading: Icon(Icons.person_outline,
                  color: _colors.textSecondary, size: 20),
              title: Text(i18n.tr('settings.account.loggedOut'),
                  style: AppTypography.body),
              subtitle: Text(i18n.tr('settings.account.loggedOutHint'),
                  style: _caption),
              trailing: TextButton(
                onPressed: () => Navigator.of(context).pushNamed('/welcome'),
                child: Text(i18n.tr('settings.account.signIn')),
              ),
            ),
          ]);
    }

    final user = auth.user!;
    return _buildSection('account', i18n.tr('settings.account'),
        icon: Icons.person_outline,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  _colors.accentPrimary.withValues(alpha: 0.2),
              child: Text(
                user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                style: TextStyle(
                    color: _colors.accentPrimary,
                    fontWeight: FontWeight.w800),
              ),
            ),
            title: Text(user.name, style: AppTypography.body),
            subtitle: Text(user.email, style: _caption),
          ),
          _buildListTile(Icons.edit_outlined,
              i18n.tr('settings.account.editName'), user.name, () {
            _showEditProfileDialog(context, ref, user.displayName ?? '');
          }),
          _buildListTile(Icons.password_outlined,
              i18n.tr('settings.account.changePassword'), null, () {
            _showChangePasswordDialog(context, ref);
          }),
          _buildListTile(Icons.delete_forever_outlined,
              i18n.tr('settings.account.delete'),
              i18n.tr('settings.account.deleteHint'), () {
            _showDeleteAccountDialog(context, ref);
          }),
          ListTile(
            leading: Icon(Icons.logout,
                color: _colors.statusDanger, size: 20),
            title: Text(i18n.tr('settings.logout'),
                style: TextStyle(color: _colors.statusDanger)),
            onTap: () async {
              final confirmed = await _confirmDialog(
                context,
                title: i18n.tr('settings.account.logoutConfirm'),
                body: i18n.tr('settings.account.logoutHint'),
                confirmLabel: i18n.tr('settings.logout'),
                danger: true,
              );
              if (confirmed != true) return;
              await ref.read(authControllerProvider.notifier).logout();
              if (!context.mounted) return;
              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/welcome', (route) => false);
            },
          ),
        ]);
  }

  Future<void> _showEditProfileDialog(
      BuildContext context, WidgetRef ref, String current) async {
    final i18n = ref.read(i18nProvider);
    final controller = TextEditingController(text: current);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _colors.bgSurface,
        title: Text(i18n.tr('settings.account.editName'),
            style: AppTypography.title),
        content: TextField(
          controller: controller,
          maxLength: 80,
          autofocus: true,
          style: AppTypography.body,
          decoration:
              InputDecoration(
                  hintText: i18n.tr('settings.account.nameHint')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(i18n.cancel)),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) Navigator.of(dialogContext).pop(name);
            },
            style: FilledButton.styleFrom(
                backgroundColor: _colors.accentPrimary),
            child: Text(i18n.save),
          ),
        ],
      ),
    );
    if (newName == null || !mounted) return;
    try {
      await ref
          .read(authControllerProvider.notifier)
          .updateDisplayName(newName);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(
              content: Text(
                  i18n.tr('settings.account.savedAs', {'name': newName}))));
    } on AuthException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(i18n.tr('settings.account.serverUnreachable'))));
    }
  }

  Future<void> _showChangePasswordDialog(
      BuildContext context, WidgetRef ref) async {
    final i18n = ref.read(i18nProvider);
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final result = await showDialog<_PasswordChange>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _colors.bgSurface,
        title: Text(i18n.tr('settings.account.changePassword'),
            style: AppTypography.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentController,
              obscureText: true,
              style: AppTypography.body,
              decoration: InputDecoration(
                  labelText: i18n.tr('settings.account.currentPassword')),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: newController,
              obscureText: true,
              style: AppTypography.body,
              decoration: InputDecoration(
                labelText: i18n.tr('settings.account.newPassword'),
                helperText: i18n.tr('settings.account.sessionsHint'),
                helperMaxLines: 2,
                helperStyle: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(i18n.cancel)),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(
              _PasswordChange(currentController.text, newController.text),
            ),
            style: FilledButton.styleFrom(
                backgroundColor: _colors.accentPrimary),
            child: Text(i18n.tr('settings.account.change')),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (result == null) return;
    if (result.newPassword.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(i18n.tr('settings.account.passwordTooShort'))));
      return;
    }
    try {
      await ref
          .read(authControllerProvider.notifier)
          .changePassword(result.currentPassword, result.newPassword);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(
              content: Text(i18n.tr('settings.account.passwordChanged'))));
    } on AuthException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Konto löschen: doppelte Bestätigung, zweite durch Eingabe von
  /// LÖSCHEN - das ist unwiderruflich (Cascade auf alle Tabellen).
  Future<void> _showDeleteAccountDialog(
      BuildContext context, WidgetRef ref) async {
    final i18n = ref.read(i18nProvider);
    final keyword = i18n.tr('settings.account.deleteKeyword');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController();
        return AlertDialog(
          backgroundColor: _colors.bgSurface,
          title: Text(i18n.tr('settings.account.deleteConfirmTitle'),
              style: AppTypography.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                i18n.tr('settings.account.deleteConfirmBody'),
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: controller,
                autofocus: true,
                style: AppTypography.body,
                decoration: InputDecoration(
                    hintText: i18n.tr('settings.account.deleteTypeHint',
                        {'keyword': keyword})),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(i18n.cancel)),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext)
                  .pop(controller.text.trim().toUpperCase() ==
                      keyword.toUpperCase()),
              style: FilledButton.styleFrom(
                  backgroundColor: _colors.statusDanger),
              child: Text(i18n.tr('settings.account.deleteForever')),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(authControllerProvider.notifier).deleteAccount();
      if (!context.mounted) return;
      Navigator.of(context)
          .pushNamedAndRemoveUntil('/welcome', (route) => false);
    } on AuthException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // ------------------------------------------------------------------
  // 3: Karte - Kartenstil + Offline-Regionen in EINER Sektion.
  // ------------------------------------------------------------------
  Widget _buildMapSection() {
    final i18n = ref.watch(i18nProvider);
    final currentStyle = ref.watch(mapStyleChoiceProvider);
    final offlineState = ref.watch(offlineMapsProvider);

    return _buildSection('map', i18n.tr('settings.map'),
        icon: Icons.map_outlined,
        children: [
      _controlTile(
        icon: Icons.brightness_6_outlined,
        title: i18n.mapStyleTitle,
        control: SegmentedButton<MapStyleChoice>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: MapStyleChoice.light, label: Text(i18n.light)),
            ButtonSegment(value: MapStyleChoice.dark, label: Text(i18n.dark)),
          ],
          selected: {currentStyle},
          onSelectionChanged: (selection) {
            ref.read(mapStyleChoiceProvider.notifier).set(selection.first);
          },
        ),
      ),
      Divider(height: 1, color: _colors.borderHairline),
      ListTile(
        leading: Icon(Icons.download_for_offline_outlined,
            color: _colors.textSecondary, size: 20),
        title: Text(i18n.tr('settings.offlineMaps.add'),
            style: AppTypography.body),
        subtitle: offlineState.isDownloading
            ? LinearProgressIndicator(
                value: offlineState.activeDownloadProgress)
            : Text(i18n.tr('settings.offlineMaps.addHint'),
                style: _caption),
        onTap: offlineState.isDownloading
            ? null
            : () => _showOfflineRegionDialog(),
      ),
      if (offlineState.error != null)
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
          child: Text(offlineState.error!,
              style: _caption
                  .copyWith(color: _colors.statusDanger)),
        ),
      ...offlineState.regions.map(
        (r) => ListTile(
          leading: Icon(Icons.map_outlined,
              color: _colors.textSecondary, size: 20),
          title: Text(r.name, style: AppTypography.body),
          subtitle: Text(
            '${r.createdAt.day}.${r.createdAt.month}.${r.createdAt.year} · '
            '(${r.southWest.lat.toStringAsFixed(2)}, ${r.southWest.lng.toStringAsFixed(2)}) → '
            '(${r.northEast.lat.toStringAsFixed(2)}, ${r.northEast.lng.toStringAsFixed(2)})',
            style: _caption,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => ref.read(offlineMapsProvider.notifier).delete(r),
          ),
        ),
      ),
    ]);
  }

  Future<void> _showOfflineRegionDialog() async {
    final i18n = ref.watch(i18nProvider);
    final nameController = TextEditingController(
        text: i18n.tr('settings.offlineMaps.defaultName'));
    var radius = 50.0;
    double centerLat = 48.1351;
    double centerLng = 11.5820;
    try {
      final position = await LocationRepository().getCurrentPosition();
      centerLat = position.latitude;
      centerLng = position.longitude;
    } catch (_) {
      // Kein GPS (Berechtigungen/Aus): Dialog mit Fallback-Mitte (München).
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(i18n.tr('settings.offlineMaps.dialogTitle'),
              style: AppTypography.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration:
                    InputDecoration(labelText: i18n.tr('common.name')),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(i18n.tr('settings.offlineMaps.radius'),
                  style: _caption),
              SegmentedButton<double>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 25.0, label: Text('25 km')),
                  ButtonSegment(value: 50.0, label: Text('50 km')),
                  ButtonSegment(value: 100.0, label: Text('100 km')),
                ],
                selected: {radius},
                onSelectionChanged: (s) =>
                    setDialogState(() => radius = s.first),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '${centerLat.toStringAsFixed(4)}, ${centerLng.toStringAsFixed(4)}',
                style: _caption,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(i18n.tr('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(i18n.tr('common.save')),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref.read(offlineMapsProvider.notifier).download(
            name: nameController.text.trim().isEmpty
                ? i18n.tr('settings.offlineMaps.fallbackName')
                : nameController.text.trim(),
            centerLat: centerLat,
            centerLng: centerLng,
            radiusKm: radius,
          );
    }
  }

  /// Kurzstatus des anonymen Reportings - zeigt Admins ohne Log-Zugriff,
  /// ob Berichte wirklich ankommen (und ob welche warten). Die Zähler sind
  /// persistent; "Seit <Datum>" nennt den Beginn der Zählung.
  String _telemetryStatusLine(I18n i18n, TelemetryDiagnostics d) {
    if (d.attempted == 0 && d.queued == 0) {
      return i18n.tr('settings.telemetry.none');
    }
    final parts = <String>[
      i18n.tr('settings.telemetry.accepted', {
        'accepted': '${d.accepted}',
        'attempted': '${d.attempted}',
      }),
    ];
    if (d.queued > 0) {
      parts.add(
          i18n.tr('settings.telemetry.queued', {'queued': '${d.queued}'}));
    }
    if (d.failed > 0) {
      parts.add(
          i18n.tr('settings.telemetry.failed', {'failed': '${d.failed}'}));
    }
    final reason = d.lastFailureReason;
    final details = reason == null
        ? ''
        : ' (${i18n.tr('settings.telemetry.lastFailure', {'reason': reason})})';
    final since = d.since;
    final prefix = since == null
        ? ''
        : '${i18n.tr('settings.telemetry.since', {'date': _shortDate(since)})} ';
    return '$prefix${parts.join(' · ')}$details';
  }

  String _shortDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// Reduzierte Variante für normale Nutzer: nur, OB und wie viele Berichte
  /// angekommen sind - keine technischen Fehlergründe, keine Interna der
  /// Warteschlange. Genau die Auskunft, die im Supportfall gebraucht wird.
  String _telemetryUserStatusLine(I18n i18n, TelemetryDiagnostics d) {
    if (d.accepted == 0) {
      return i18n.tr('settings.telemetry.userNone');
    }
    final last = d.lastAcceptedAt;
    final wann = last == null
        ? ''
        : i18n.tr('settings.telemetry.userWhen', {'date': _shortDate(last)});
    return d.accepted == 1
        ? i18n.tr('settings.telemetry.userOne', {'when': wann})
        : i18n.tr('settings.telemetry.userMany',
            {'n': '${d.accepted}', 'when': wann});
  }

  /// Setzt die Reporter-Zähler zurück. Wartende Berichte würden dabei
  /// verworfen - das ist endgültig, deshalb fragt die Methode vorher nach
  /// (gleicher Dialog wie bei den übrigen Löschaktionen). Ohne wartende
  /// Berichte gibt es nichts zu verlieren, dann geht es direkt.
  Future<void> _resetTelemetryDiagnostics() async {
    final reporter = ErrorReporter.instance;
    final i18n = ref.read(i18nProvider);
    final queued = reporter.diagnostics.queued;
    if (queued > 0) {
      final confirmed = await _confirmDialog(
        context,
        title: i18n.tr('settings.telemetry.resetTitle'),
        body: i18n.tr('settings.telemetry.resetBody', {'n': '$queued'}),
        confirmLabel: i18n.tr('settings.telemetry.resetConfirm'),
        danger: true,
      );
      if (confirmed != true || !mounted) return;
    }
    await reporter.resetDiagnostics(discardPending: true);
  }

  /// Kopiert genau die angezeigte Statuszeile in die Zwischenablage - im
  /// Supportfall reicht dann Einfügen im Chat statt Abschreiben. Admins
  /// kopieren ihre ausführliche Zeile (inkl. Fehlergrund).
  Future<void> _copyTelemetryStatus() async {
    final d = ErrorReporter.instance.diagnostics;
    final i18n = ref.read(i18nProvider);
    final isAdmin = ref.read(authControllerProvider).user?.isAdmin ?? false;
    final text = isAdmin
        ? _telemetryStatusLine(i18n, d)
        : _telemetryUserStatusLine(i18n, d);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(i18n.tr('settings.telemetry.copied')),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ------------------------------------------------------------------
  // 4: Community - Benachrichtigungen + Chat-Status/-Name + Privatsphäre.
  // ------------------------------------------------------------------
  List<Widget> _notificationChildren() {
    final notifications = ref.watch(notificationsEnabledProvider);
    final telemetry = ref.watch(telemetryEnabledProvider);
    final isAdmin = ref.watch(authControllerProvider).user?.isAdmin ?? false;
    final i18n = ref.watch(i18nProvider);
    return [
      _buildSwitchTile(
        Icons.notifications_outlined,
        i18n.tr('settings.notifyUnreadTitle'),
        notifications,
        (value) {
          ref.read(notificationsEnabledProvider.notifier).state = value;
          persistNotificationsEnabled(value);
        },
      ),
      ListTile(
        dense: true,
        leading: Icon(Icons.info_outline,
            color: _colors.textMuted, size: 18),
        title: Text(
          i18n.tr('settings.notifyUnreadHint'),
          style: _caption,
        ),
      ),
      Divider(height: 1, color: _colors.borderHairline),
      _buildSwitchTile(
        Icons.error_outline,
        i18n.tr('settings.telemetry.toggle'),
        telemetry,
        (value) async {
          ref.read(telemetryEnabledProvider.notifier).state = value;
          await ErrorReporter.instance.setEnabled(value);
        },
      ),
      ListTile(
        dense: true,
        leading: Icon(Icons.shield_outlined,
            color: _colors.textMuted, size: 18),
        title: Text(
          i18n.tr('settings.telemetry.toggleHint'),
          style: _caption,
        ),
      ),
      // Gleiche Zeile für alle: normale Nutzer sehen nur, OB und wie viele
      // Berichte beim Support angekommen sind - das beantwortet die erste
      // Rückfrage im Supportfall ohne Logs. Fehlergründe, Warteschlange und
      // der Zurücksetzen-Knopf bleiben Admin-Werkzeug.
      ValueListenableBuilder<int>(
        valueListenable: ErrorReporter.instance.changes,
        builder: (context, _, __) {
          final d = ErrorReporter.instance.diagnostics;
          return ListTile(
            dense: true,
            leading: Icon(Icons.monitor_heart_outlined,
                color: _colors.textMuted, size: 18),
            title: Text(
              isAdmin
                  ? _telemetryStatusLine(i18n, d)
                  : _telemetryUserStatusLine(i18n, d),
              style: _caption,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isAdmin)
                  IconButton(
                    icon: Icon(Icons.restart_alt,
                        color: _colors.textMuted, size: 18),
                    tooltip: i18n.tr('settings.telemetry.resetTooltip'),
                    onPressed: _resetTelemetryDiagnostics,
                  ),
                IconButton(
                  icon: Icon(Icons.content_copy,
                      color: _colors.textMuted, size: 18),
                  tooltip: i18n.tr('settings.telemetry.copyTooltip'),
                  onPressed: _copyTelemetryStatus,
                ),
              ],
            ),
          );
        },
      ),
    ];
  }

  List<Widget> _chatChildren() {
    final i18n = ref.watch(i18nProvider);
    final token = ref.watch(chatSessionTokenProvider);
    final me = ref.watch(chatMeProvider).value;

    return [
      ListTile(
        leading: Icon(Icons.forum_outlined,
            color: _colors.textSecondary, size: 20),
        title: Text(i18n.tr('settings.chatAccount'), style: AppTypography.body),
        subtitle: Text(
          token == null
              ? i18n.tr('settings.chatAccount.notConnectedHint')
              : i18n.tr('settings.chatAccount.connectedAs',
                  {'name': me?.effectiveName ?? '…'}),
          style: _caption,
        ),
      ),
      ListTile(
        leading: Icon(Icons.visibility_outlined,
            color: _colors.textSecondary, size: 20),
        title: Text(i18n.tr('settings.showOnline'), style: AppTypography.body),
        enabled: token != null,
        trailing: Switch(
          value: me?.showOnline ?? true,
          onChanged: token == null
              ? null
              : (value) async {
                  try {
                    await ref
                        .read(chatRepositoryProvider)
                        .updateMe(token, showOnline: value);
                    ref.invalidate(chatMeProvider);
                  } catch (e) {
                    // "Online sichtbar"-Schalter: scheitert das Speichern,
                    // glaubt der Nutzer faelschlich, er sei verborgen.
                    ErrorReporter.instance.report('settings.privacy', e);
                  }
                },
          activeThumbColor: _colors.accentPrimary,
          inactiveThumbColor: _colors.stateIdle,
          inactiveTrackColor: _colors.bgSurfaceRaised,
        ),
      ),
      _controlTile(
        icon: Icons.badge_outlined,
        title: i18n.tr('settings.chatName.mode'),
        subtitle: me?.effectiveName ?? '–',
        control: token == null
            ? null
            : _chatNameModeSelector(
                selected: me?.chatNameMode ?? 'username',
                options: [
                  ('username', i18n.tr('settings.chatName.username')),
                  ('first_name', i18n.tr('settings.chatName.firstName')),
                  ('custom', i18n.tr('settings.chatName.custom')),
                ],
                onChanged: (mode) async {
                  if (mode == 'custom') {
                    await _editChatDisplayName();
                    return;
                  }
                  await _saveChatNameSettings(chatNameMode: mode);
                },
              ),
      ),
      if (me?.chatNameMode == 'custom')
        ListTile(
          dense: true,
          leading: Icon(Icons.edit_outlined,
              color: _colors.textSecondary, size: 20),
          title: Text(i18n.tr('settings.chatName.customLabel'),
              style: AppTypography.body),
          subtitle:
              Text(me?.chatDisplayName ?? '–', style: _caption),
          trailing: Icon(Icons.chevron_right,
              size: 18, color: _colors.textMuted),
          onTap: _editChatDisplayName,
        ),
      ListTile(
        dense: true,
        leading: Icon(Icons.person_outline,
            color: _colors.textSecondary, size: 20),
        title: Text(i18n.firstName, style: AppTypography.body),
        subtitle: Text(me?.firstName ?? '–', style: _caption),
        trailing: Icon(Icons.chevron_right,
            size: 18, color: _colors.textMuted),
        onTap: token == null ? null : _editFirstName,
      ),
    ];
  }

  Future<void> _saveChatNameSettings(
      {String? chatNameMode,
      String? chatDisplayName,
      String? firstName}) async {
    final token = ref.read(chatSessionTokenProvider);
    if (token == null) return;
    try {
      await ref.read(chatRepositoryProvider).updateMe(
            token,
            chatNameMode: chatNameMode,
            chatDisplayName: chatDisplayName,
            firstName: firstName,
          );
      ref.invalidate(chatMeProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.read(i18nProvider).tr('settings.saved'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.read(i18nProvider).tr('errors.saveFailed'))),
      );
    }
  }

  Future<void> _editChatDisplayName() async {
    final me = ref.read(chatMeProvider).value;
    final controller = TextEditingController(text: me?.chatDisplayName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _colors.bgSurface,
        title: Text(ref.read(i18nProvider).tr('settings.chatName.customLabel'),
            style: AppTypography.title),
        content: TextField(
          controller: controller,
          maxLength: 80,
          autofocus: true,
          style: AppTypography.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(ref.read(i18nProvider).cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            style: FilledButton.styleFrom(
                backgroundColor: _colors.accentPrimary),
            child: Text(ref.read(i18nProvider).save),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    if (name.isEmpty) return;
    await _saveChatNameSettings(chatNameMode: 'custom', chatDisplayName: name);
  }

  Future<void> _editFirstName() async {
    final me = ref.read(chatMeProvider).value;
    final controller = TextEditingController(text: me?.firstName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _colors.bgSurface,
        title:
            Text(ref.read(i18nProvider).firstName, style: AppTypography.title),
        content: TextField(
          controller: controller,
          maxLength: 80,
          autofocus: true,
          style: AppTypography.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(ref.read(i18nProvider).cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            style: FilledButton.styleFrom(
                backgroundColor: _colors.accentPrimary),
            child: Text(ref.read(i18nProvider).save),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    await _saveChatNameSettings(firstName: name);
  }

  /// Fahrhistorie: 5 Privatsphäre-Schalter (Default alles privat).
  /// Server ist die Wahrheit, optimistische UI mit Rollback.
  List<Widget> _rideHistoryChildren() {
    final settings = ref.watch(rideHistorySettingsProvider);
    final controller = ref.read(rideHistorySettingsProvider.notifier);
    final i18n = ref.watch(i18nProvider);

    Future<void> change(Future<bool> Function() call) async {
      final ok = await call();
      if (mounted && !ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(i18n.tr('settings.saveOfflineFailed'))),
        );
      }
    }

    return [
      if (!ref.read(authControllerProvider).isAuthenticated)
        ListTile(
          dense: true,
          leading: Icon(Icons.info_outline,
              color: _colors.textMuted, size: 18),
          title: Text(
            i18n.tr('rideHistory.requiresLogin'),
            style: _caption,
          ),
        )
      else ...[
        _buildSwitchTile(
          Icons.history,
          i18n.tr('rideHistory.enabled'),
          settings.rideHistoryEnabled,
          (v) => change(() => controller.update(rideHistoryEnabled: v)),
        ),
        _buildSwitchTile(
          Icons.public,
          i18n.tr('rideHistory.publicProfile'),
          settings.isPublic,
          (v) => change(
              () => controller.update(authPrivacy: v ? 'public' : 'private')),
        ),
        if (settings.isPublic) ...[
          _buildSwitchTile(
            Icons.route,
            i18n.tr('rideHistory.shareRides'),
            settings.shareRides,
            (v) => change(() => controller.update(shareRides: v)),
          ),
          _buildSwitchTile(
            Icons.place_outlined,
            i18n.tr('rideHistory.sharePlaces'),
            settings.sharePlaces,
            (v) => change(() => controller.update(sharePlaces: v)),
          ),
          _buildSwitchTile(
            Icons.visibility_off_outlined,
            i18n.tr('rideHistory.hideStartEnd'),
            settings.hideStartEnd,
            (v) => change(() => controller.update(hideStartEnd: v)),
          ),
        ],
        ListTile(
          dense: true,
          leading: Icon(Icons.lock_outline,
              color: _colors.textMuted, size: 18),
          title: Text(
            settings.isPublic
                ? i18n.tr('rideHistory.hintPublic')
                : i18n.tr('rideHistory.hintPrivate'),
            style: _caption,
          ),
        ),
      ],
    ];
  }

  // ------------------------------------------------------------------
  // 6: Sprache & Erscheinungsbild.
  // ------------------------------------------------------------------
  Widget _buildLanguageSection() {
    final i18n = ref.watch(i18nProvider);
    final currentLanguage = ref.watch(languageControllerProvider);
    final currentThemeMode = ref.watch(themeModeControllerProvider);

    return _buildSection('language', i18n.tr('settings.languageAndAppearance'),
        icon: Icons.language,
        children: [
          _controlTile(
            icon: Icons.language,
            title: i18n.languageLabel,
            control: SegmentedButton<AppLanguage>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: AppLanguage.de, label: Text('🇩🇪 DE')),
                ButtonSegment(value: AppLanguage.en, label: Text('🇬🇧 EN')),
              ],
              selected: {currentLanguage},
              onSelectionChanged: (selection) {
                ref
                    .read(languageControllerProvider.notifier)
                    .set(selection.first);
              },
            ),
          ),
          _controlTile(
            icon: Icons.contrast,
            title: i18n.themeModeTitle,
            control: SegmentedButton<AppThemeMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: AppThemeMode.system,
                    label: Text(i18n.themeModeSystem)),
                ButtonSegment(
                    value: AppThemeMode.light,
                    label: Text(i18n.themeModeLight)),
                ButtonSegment(
                    value: AppThemeMode.dark, label: Text(i18n.themeModeDark)),
              ],
              selected: {currentThemeMode},
              onSelectionChanged: (selection) {
                ref
                    .read(themeModeControllerProvider.notifier)
                    .set(selection.first);
              },
            ),
          ),
        ]);
  }

  // ------------------------------------------------------------------
  // Wiederverwendbare Bausteine.
  // ------------------------------------------------------------------
  /// Kachel mit Titel, optionalem Untertitel und einer Steuerung DARUNTER.
  ///
  /// Die Steuerung bekam früher den Platz rechts neben dem Text und hat die
  /// Textspalte dadurch auf ~60 dp zusammengedrückt: englische Titel brachen
  /// zweizeilig um, lange deutsche Wörter mitten im Wort ("Fahrzeu/gstanda/rd").
  Widget _controlTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? control,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: _colors.textSecondary, size: 20),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: AppTypography.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (subtitle != null)
                      Text(subtitle,
                          style: _caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          if (control != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(alignment: Alignment.centerRight, child: control),
          ],
        ],
      ),
    );
  }

  /// Drei-Wege-Auswahl für den Chat-Anzeigenamen.
  ///
  /// Solange die Labels nebeneinander passen: SegmentedButton. Ab ~1,2x
  /// Systemschrift sind drei Segmente zu schmal - die Labels brachen dann
  /// mitten im Wort ("Benutzernam/e"). Statt dessen eine umbrechende
  /// Chip-Reihe, die zwischen den Labels umbricht statt innerhalb.
  Widget _chatNameModeSelector({
    required String selected,
    required List<(String, String)> options,
    required Future<void> Function(String) onChanged,
  }) {
    if (MediaQuery.textScalerOf(context).scale(1) > 1.15) {
      return Wrap(
        alignment: WrapAlignment.end,
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          for (final (value, label) in options)
            ChoiceChip(
              label: Text(label),
              selected: value == selected,
              showCheckmark: false,
              selectedColor: _colors.accentPrimary,
              backgroundColor: _colors.bgSurfaceRaised,
              side: BorderSide(color: _colors.borderHairline),
              labelStyle: AppTypography.body.copyWith(
                color: value == selected
                    ? _colors.textPrimary
                    : _colors.textSecondary,
              ),
              onSelected: (_) => onChanged(value),
            ),
        ],
      );
    }
    return SegmentedButton<String>(
      showSelectedIcon: false,
      // Kompakter Innenabstand, damit drei Textsegmente in eine Zeile passen.
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding:
            WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: AppSpacing.sm)),
      ),
      segments: [
        for (final (value, label) in options)
          ButtonSegment(value: value, label: Text(label)),
      ],
      selected: {selected},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }

  Future<bool?> _confirmDialog(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    required bool danger,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _colors.bgSurface,
        title: Text(title, style: AppTypography.title),
        content: Text(body, style: _caption),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(ref.read(i18nProvider).cancel)),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor:
                  danger ? _colors.statusDanger : _colors.accentPrimary,
              foregroundColor: Colors.white,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  /// Sektion mit einklappbarem Header. `id` ist stabil (Sprachwechsel-
  /// fest), `title` wird angezeigt.
  ///
  /// Calimoto-Look: fette, großere Sektionstitel in Normal-Schreibung
  /// AUSSERHALB der Karte ("Weitere Premium-Vorteile"-Stil), nicht die
  /// kleinen Caps-Labels mit Akzent-Balken.
  Widget _buildSection(String id, String title,
      {required List<Widget> children, IconData? icon}) {
    final collapsed = _collapsed.contains(id);
    final header = Padding(
      padding:
          const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTypography.title.copyWith(fontSize: 18),
            ),
          ),
        ],
      ),
    );

    // Alles, was optisch unter dem Header liegt, ist einklappbar.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() {
            collapsed ? _collapsed.remove(id) : _collapsed.add(id);
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(children: [
              Expanded(child: header),
              Icon(
                collapsed ? Icons.expand_more : Icons.expand_less,
                size: 20,
                color: _colors.textSecondary,
              ),
            ]),
          ),
        ),
        if (!collapsed) ...[
          const SizedBox(height: AppSpacing.xs),
          // Material-Wrapper: ListTile malt Hintergrund/Ink auf das nächste
          // Material - ein nackter Container würde die Effekte verdecken
          // (Flutter-Assert "ListTile background color or ink splashes may
          // be invisible").
          Material(
            color: _colors.bgSurface,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _colors.borderHairline),
                boxShadow: [
                  BoxShadow(
                    color: _colors.shadow,
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(children: children),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildListTile(
      IconData icon, String title, String? subtitle, VoidCallback? onTap) {
    return ListTile(
      leading: Icon(icon, color: _colors.textSecondary, size: 20),
      title: Text(title, style: AppTypography.body),
      subtitle: subtitle != null
          ? Text(subtitle, style: _caption)
          : null,
      onTap: onTap,
      // Chevron auf Tap-Zeilen (calimoto-Stil) - macht klar, dass die
      // Zeile in einen eigenen Screen fuhrt.
      trailing: onTap == null
          ? null
          : Icon(Icons.chevron_right, color: _colors.textSecondary),
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
    );
  }

  Widget _buildSwitchTile(
      IconData icon, String title, bool value, ValueChanged<bool> onChanged) {
    return ListTile(
      leading: Icon(icon, color: _colors.textSecondary, size: 20),
      title: Text(title, style: AppTypography.body),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: _colors.accentPrimary,
        inactiveThumbColor: _colors.stateIdle,
        inactiveTrackColor: _colors.bgSurfaceRaised,
      ),
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
    );
  }
}

class _PasswordChange {
  final String currentPassword;
  final String newPassword;
  const _PasswordChange(this.currentPassword, this.newPassword);
}

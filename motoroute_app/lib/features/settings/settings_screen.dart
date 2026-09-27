import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/constants/route_enums.dart';
import 'package:motoroute_app/core/i18n/i18n.dart';
import 'package:motoroute_app/core/network/api_client.dart';
import 'package:motoroute_app/core/network/error_message.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';
import 'package:motoroute_app/core/utils/formatters.dart' show DistanceUnit;
import 'package:motoroute_app/features/map/data/location_repository.dart';
import 'package:motoroute_app/features/settings/offline_maps.dart';
import 'package:motoroute_app/features/settings/theme_mode.dart';
import 'package:motoroute_app/features/auth/auth_providers.dart';
import 'package:motoroute_app/features/chat/chat_providers.dart';
import 'package:motoroute_app/features/chat/data/chat_repository.dart';
import 'package:motoroute_app/features/garage/garage_repository.dart';
import 'package:motoroute_app/features/map/data/map_style.dart';
import 'package:motoroute_app/features/marketplace/marketplace_repository.dart';
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
///   5. Diagnose (eingeklappt) - testet Server/Anmeldung/Chat/Marktplatz/
///      Garage DIREKT vom Gerät; macht sichtbar, welcher Bereich hakt,
///      statt "Etwas ist schiefgelaufen" zu raten
///   6. Sprache & Erscheinungsbild (eingeklappt)
///   7. Recht & Info (eingeklappt) - Datenschutz/Impressum/Über/Version
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
  final Set<String> _collapsed = {'community', 'diagnostics', 'language', 'legal'};

  bool _runningDiagnostics = false;
  final Map<String, String> _diagResults = {};
  String _appVersion = '…';

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
    final i18n = ref.watch(i18nProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(i18n.tabSettings, style: AppTypography.title),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          children: [
            // --------------------------------------------- 1. Navigation
            _buildSection('nav', i18n.navigation, icon: Icons.navigation_outlined, children: [
              ListTile(
                leading: const Icon(Icons.motorcycle, color: AppColors.textSecondaryDark, size: 20),
                title: Text('Fahrzeugstandard', style: AppTypography.body),
                subtitle: Text('Beeinflusst Routing und Dauer', style: AppTypography.caption),
                trailing: SegmentedButton<VehicleType>(
                  segments: const [
                    ButtonSegment(value: VehicleType.motorcycle, icon: Icon(Icons.two_wheeler, size: 18)),
                    ButtonSegment(value: VehicleType.car, icon: Icon(Icons.directions_car, size: 18)),
                    ButtonSegment(value: VehicleType.bicycle, icon: Icon(Icons.pedal_bike, size: 18)),
                  ],
                  selected: {vehicleType},
                  onSelectionChanged: (selection) {
                    ref.read(vehicleTypeProvider.notifier).state = selection.first;
                    persistVehicleType(selection.first);
                  },
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.straighten, color: AppColors.textSecondaryDark, size: 20),
                title: Text('Einheiten', style: AppTypography.body),
                subtitle: Text(unit == DistanceUnit.kilometers ? 'Kilometer' : 'Meilen', style: AppTypography.caption),
                trailing: SegmentedButton<DistanceUnit>(
                  segments: const [
                    ButtonSegment(value: DistanceUnit.kilometers, label: Text('km')),
                    ButtonSegment(value: DistanceUnit.miles, label: Text('mi')),
                  ],
                  selected: {unit},
                  onSelectionChanged: (selection) {
                    ref.read(distanceUnitProvider.notifier).state = selection.first;
                    persistDistanceUnit(selection.first);
                  },
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              _buildSwitchTile(
                Icons.battery_saver,
                'Energiesparmodus',
                energy.mode != EnergySaverMode.off,
                (value) async {
                  await ref.read(energySaverControllerProvider.notifier).setEnabled(value);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          value
                              ? 'Energiesparmodus aktiv - GPS wird während der Navigation gedrosselt.'
                              : 'Energiesparmodus aus - volle GPS-Genauigkeit.',
                        ),
                      ),
                    );
                  }
                },
              ),
              if (energy.mode != EnergySaverMode.off)
                ListTile(
                  leading: const Icon(Icons.bolt, color: AppColors.statusWarning, size: 20),
                  title: Text(
                    energy.mode == EnergySaverMode.critical
                        ? 'Kritischer Akku - minimale GPS-Genauigkeit'
                        : 'GPS gedrosselt',
                    style: AppTypography.caption,
                  ),
                  subtitle: Text('Akkustand: ${energy.batteryLevelPercent} %', style: AppTypography.caption),
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
            _buildSection('community', 'Community', icon: Icons.forum_outlined, children: [
              ..._notificationChildren(),
              const Divider(height: 1, color: AppColors.borderHairlineDark),
              ..._chatChildren(),
              const Divider(height: 1, color: AppColors.borderHairlineDark),
              ..._rideHistoryChildren(),
            ]),
            const SizedBox(height: AppSpacing.lg),

            // ----------------------------------------------- 5. Diagnose
            _buildDiagnosticsSection(),
            const SizedBox(height: AppSpacing.lg),

            // ------------------------------------------------ 6. Sprache
            _buildLanguageSection(),
            const SizedBox(height: AppSpacing.lg),

            // -------------------------------------------- 7. Recht & Info
            _buildSection('legal', i18n.tr('settings.legal'), icon: Icons.gavel_outlined, children: [
              _buildListTile(Icons.privacy_tip_outlined, 'Datenschutz', 'Welche Daten MotoRoute verarbeitet', () {
                Navigator.of(context).pushNamed('/privacy');
              }),
              _buildListTile(Icons.description_outlined, 'Impressum', 'Betreiber der Instanz', () {
                Navigator.of(context).pushNamed('/imprint');
              }),
              _buildListTile(Icons.info_outline, 'Über MotoRoute', 'Version, Datenquellen, Danksagung', () {
                Navigator.of(context).pushNamed('/about');
              }),
              ListTile(
                dense: true,
                title: Text(i18n.appVersion, style: AppTypography.body),
                trailing: Text(_appVersion, style: AppTypography.caption),
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
  Widget _buildAccountSection(BuildContext context, WidgetRef ref, AuthState auth) {
    if (!auth.isAuthenticated) {
      return _buildSection('account', 'Konto', icon: Icons.person_outline, children: [
        ListTile(
          leading: const Icon(Icons.person_outline, color: AppColors.textSecondaryDark, size: 20),
          title: Text('Nicht angemeldet', style: AppTypography.body),
          subtitle: Text('Chat und Gruppen brauchen ein Konto', style: AppTypography.caption),
          trailing: TextButton(
            onPressed: () => Navigator.of(context).pushNamed('/welcome'),
            child: const Text('Anmelden'),
          ),
        ),
      ]);
    }

    final user = auth.user!;
    return _buildSection('account', 'Konto', icon: Icons.person_outline, children: [
      ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.accentPrimaryDark.withValues(alpha: 0.2),
          child: Text(
            user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
            style: const TextStyle(color: AppColors.accentPrimaryDark, fontWeight: FontWeight.w800),
          ),
        ),
        title: Text(user.name, style: AppTypography.body),
        subtitle: Text(user.email, style: AppTypography.caption),
      ),
      _buildListTile(Icons.edit_outlined, 'Anzeigename ändern', user.name, () {
        _showEditProfileDialog(context, ref, user.displayName ?? '');
      }),
      _buildListTile(Icons.password_outlined, 'Passwort ändern', null, () {
        _showChangePasswordDialog(context, ref);
      }),
      _buildListTile(Icons.delete_forever_outlined, 'Konto löschen', 'Endgültig - alle Daten werden entfernt', () {
        _showDeleteAccountDialog(context, ref);
      }),
      ListTile(
        leading: const Icon(Icons.logout, color: AppColors.statusDanger, size: 20),
        title: const Text('Abmelden', style: TextStyle(color: AppColors.statusDanger)),
        onTap: () async {
          final confirmed = await _confirmDialog(
            context,
            title: 'Abmelden?',
            body: 'Gespeicherte Routen und Einstellungen bleiben auf dem Gerät.',
            confirmLabel: 'Abmelden',
            danger: true,
          );
          if (confirmed != true) return;
          await ref.read(authControllerProvider.notifier).logout();
          if (!context.mounted) return;
          Navigator.of(context).pushNamedAndRemoveUntil('/welcome', (route) => false);
        },
      ),
    ]);
  }

  Future<void> _showEditProfileDialog(BuildContext context, WidgetRef ref, String current) async {
    final controller = TextEditingController(text: current);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.bgSurfaceDark,
        title: Text('Anzeigename ändern', style: AppTypography.title),
        content: TextField(
          controller: controller,
          maxLength: 80,
          autofocus: true,
          style: AppTypography.body,
          decoration: const InputDecoration(hintText: 'z. B. Vati auf zwei Rädern'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) Navigator.of(dialogContext).pop(name);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.accentPrimaryDark),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (newName == null || !mounted) return;
    try {
      await ref.read(authControllerProvider.notifier).updateDisplayName(newName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gespeichert: $newName')));
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Server nicht erreichbar - später erneut versuchen')));
    }
  }

  Future<void> _showChangePasswordDialog(BuildContext context, WidgetRef ref) async {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final result = await showDialog<_PasswordChange>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.bgSurfaceDark,
        title: Text('Passwort ändern', style: AppTypography.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentController,
              obscureText: true,
              style: AppTypography.body,
              decoration: const InputDecoration(labelText: 'Aktuelles Passwort'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: newController,
              obscureText: true,
              style: AppTypography.body,
              decoration: const InputDecoration(
                labelText: 'Neues Passwort (min. 8 Zeichen)',
                helperText: 'Alte Sitzungen bleiben gültig - danach überall abmelden, wo nötig.',
                helperStyle: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(
              _PasswordChange(currentController.text, newController.text),
            ),
            style: FilledButton.styleFrom(backgroundColor: AppColors.accentPrimaryDark),
            child: const Text('Ändern'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    if (result.newPassword.length < 8) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Das neue Passwort muss mindestens 8 Zeichen haben')));
      return;
    }
    try {
      await ref.read(authControllerProvider.notifier).changePassword(result.currentPassword, result.newPassword);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwort geändert ✓')));
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Konto löschen: doppelte Bestätigung, zweite durch Eingabe von
  /// LÖSCHEN - das ist unwiderruflich (Cascade auf alle Tabellen).
  Future<void> _showDeleteAccountDialog(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController();
        return AlertDialog(
          backgroundColor: AppColors.bgSurfaceDark,
          title: Text('Konto endgültig löschen?', style: AppTypography.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Es werden gelöscht: Profil, Chat-Nachrichten, Gruppen-'
                'Mitgliedschaften und gespeicherte Gruppenrouten-Anteile. '
                'Das kann nicht rückgängig gemacht werden.',
                style: TextStyle(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: controller,
                autofocus: true,
                style: AppTypography.body,
                decoration: const InputDecoration(hintText: 'Tippe LÖSCHEN zur Bestätigung'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim().toUpperCase() == 'LÖSCHEN'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.statusDanger),
              child: const Text('Endgültig löschen'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(authControllerProvider.notifier).deleteAccount();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/welcome', (route) => false);
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // ------------------------------------------------------------------
  // 3: Karte - Kartenstil + Offline-Regionen in EINER Sektion.
  // ------------------------------------------------------------------
  Widget _buildMapSection() {
    final i18n = ref.watch(i18nProvider);
    final currentStyle = ref.watch(mapStyleChoiceProvider);
    final offlineState = ref.watch(offlineMapsProvider);

    return _buildSection('map', 'Karte', icon: Icons.map_outlined, children: [
      ListTile(
        leading: const Icon(Icons.brightness_6_outlined, color: AppColors.textSecondaryDark, size: 20),
        title: Text(i18n.mapStyleTitle, style: AppTypography.body),
        trailing: SegmentedButton<MapStyleChoice>(
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
      const Divider(height: 1, color: AppColors.borderHairlineDark),
      ListTile(
        leading: const Icon(Icons.download_for_offline_outlined,
            color: AppColors.textSecondaryDark, size: 20),
        title: Text(i18n.tr('settings.offlineMaps.add'), style: AppTypography.body),
        subtitle: offlineState.isDownloading
            ? LinearProgressIndicator(value: offlineState.activeDownloadProgress)
            : Text(i18n.tr('settings.offlineMaps.addHint'), style: AppTypography.caption),
        onTap: offlineState.isDownloading ? null : () => _showOfflineRegionDialog(),
      ),
      if (offlineState.error != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
          child: Text(offlineState.error!, style: AppTypography.caption.copyWith(color: AppColors.statusDanger)),
        ),
      ...offlineState.regions.map(
        (r) => ListTile(
          leading: const Icon(Icons.map_outlined, color: AppColors.textSecondaryDark, size: 20),
          title: Text(r.name, style: AppTypography.body),
          subtitle: Text(
            '${r.createdAt.day}.${r.createdAt.month}.${r.createdAt.year} · '
            '(${r.southWest.lat.toStringAsFixed(2)}, ${r.southWest.lng.toStringAsFixed(2)}) → '
            '(${r.northEast.lat.toStringAsFixed(2)}, ${r.northEast.lng.toStringAsFixed(2)})',
            style: AppTypography.caption,
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
    final nameController = TextEditingController(text: 'Meine Region');
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
          title: Text(i18n.tr('settings.offlineMaps.dialogTitle'), style: AppTypography.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(i18n.tr('settings.offlineMaps.radius'), style: AppTypography.caption),
              SegmentedButton<double>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 25.0, label: Text('25 km')),
                  ButtonSegment(value: 50.0, label: Text('50 km')),
                  ButtonSegment(value: 100.0, label: Text('100 km')),
                ],
                selected: {radius},
                onSelectionChanged: (s) => setDialogState(() => radius = s.first),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '${centerLat.toStringAsFixed(4)}, ${centerLng.toStringAsFixed(4)}',
                style: AppTypography.caption,
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

    if (confirmed == true) {
      await ref.read(offlineMapsProvider.notifier).download(
            name: nameController.text.trim().isEmpty
                ? 'Region'
                : nameController.text.trim(),
            centerLat: centerLat,
            centerLng: centerLng,
            radiusKm: radius,
          );
    }
  }

  // ------------------------------------------------------------------
  // 4: Community - Benachrichtigungen + Chat-Status/-Name + Privatsphäre.
  // ------------------------------------------------------------------
  List<Widget> _notificationChildren() {
    final notifications = ref.watch(notificationsEnabledProvider);
    return [
      _buildSwitchTile(
        Icons.notifications_outlined,
        'Ungelesen-Hinweis am Chat-Tab',
        notifications,
        (value) {
          ref.read(notificationsEnabledProvider.notifier).state = value;
          persistNotificationsEnabled(value);
        },
      ),
      ListTile(
        dense: true,
        leading: const Icon(Icons.info_outline, color: AppColors.textMutedDark, size: 18),
        title: Text(
          'Es gibt keine Push-Benachrichtigungen von Google - Hinweise erscheinen direkt in der App.',
          style: AppTypography.caption,
        ),
      ),
    ];
  }

  List<Widget> _chatChildren() {
    final i18n = ref.watch(i18nProvider);
    final token = ref.watch(chatSessionTokenProvider);
    final me = ref.watch(chatMeProvider).value;

    return [
      ListTile(
        leading: const Icon(Icons.forum_outlined, color: AppColors.textSecondaryDark, size: 20),
        title: const Text('Chat-Konto', style: AppTypography.body),
        subtitle: Text(
          token == null
              ? 'Nicht verbunden - Anmeldung in der App nötig'
              : 'Verbunden als ${me?.effectiveName ?? '…'}',
          style: AppTypography.caption,
        ),
      ),
      ListTile(
        leading: const Icon(Icons.visibility_outlined, color: AppColors.textSecondaryDark, size: 20),
        title: const Text('Online-Status anzeigen', style: AppTypography.body),
        enabled: token != null,
        trailing: Switch(
          value: me?.showOnline ?? true,
          onChanged: token == null
              ? null
              : (value) async {
                  try {
                    await ref.read(chatRepositoryProvider).updateMe(token, showOnline: value);
                    ref.invalidate(chatMeProvider);
                  } catch (_) {}
                },
          activeColor: AppColors.accentPrimaryDark,
          inactiveThumbColor: AppColors.textMutedDark,
          inactiveTrackColor: AppColors.bgSurfaceRaisedDark,
        ),
      ),
      ListTile(
        leading: const Icon(Icons.badge_outlined, color: AppColors.textSecondaryDark, size: 20),
        title: Text(i18n.tr('settings.chatName.mode'), style: AppTypography.body),
        subtitle: Text(me?.effectiveName ?? '–', style: AppTypography.caption),
        trailing: token == null
            ? null
            : SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'username', label: Text(i18n.tr('settings.chatName.username'))),
                  ButtonSegment(value: 'first_name', label: Text(i18n.tr('settings.chatName.firstName'))),
                  ButtonSegment(value: 'custom', label: Text(i18n.tr('settings.chatName.custom'))),
                ],
                selected: {(me?.chatNameMode ?? 'username')},
                onSelectionChanged: (selection) async {
                  final mode = selection.first;
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
          leading: const Icon(Icons.edit_outlined, color: AppColors.textSecondaryDark, size: 20),
          title: Text(i18n.tr('settings.chatName.customLabel'), style: AppTypography.body),
          subtitle: Text(me?.chatDisplayName ?? '–', style: AppTypography.caption),
          trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textMutedDark),
          onTap: _editChatDisplayName,
        ),
      ListTile(
        dense: true,
        leading: const Icon(Icons.person_outline, color: AppColors.textSecondaryDark, size: 20),
        title: Text(i18n.firstName, style: AppTypography.body),
        subtitle: Text(me?.firstName ?? '–', style: AppTypography.caption),
        trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textMutedDark),
        onTap: token == null ? null : _editFirstName,
      ),
    ];
  }

  Future<void> _saveChatNameSettings({String? chatNameMode, String? chatDisplayName, String? firstName}) async {
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
        backgroundColor: AppColors.bgSurfaceDark,
        title: Text(ref.read(i18nProvider).tr('settings.chatName.customLabel'), style: AppTypography.title),
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
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: AppColors.accentPrimaryDark),
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
        backgroundColor: AppColors.bgSurfaceDark,
        title: Text(ref.read(i18nProvider).firstName, style: AppTypography.title),
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
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: AppColors.accentPrimaryDark),
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
          const SnackBar(content: Text('Konnte nicht gespeichert werden - offline?')),
        );
      }
    }

    return [
      if (!ref.read(authControllerProvider).isAuthenticated)
        ListTile(
          dense: true,
          leading: const Icon(Icons.info_outline, color: AppColors.textMutedDark, size: 18),
          title: Text(
            i18n.tr('rideHistory.requiresLogin'),
            style: AppTypography.caption,
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
          (v) => change(() => controller.update(authPrivacy: v ? 'public' : 'private')),
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
          leading: const Icon(Icons.lock_outline, color: AppColors.textMutedDark, size: 18),
          title: Text(
            settings.isPublic
                ? i18n.tr('rideHistory.hintPublic')
                : i18n.tr('rideHistory.hintPrivate'),
            style: AppTypography.caption,
          ),
        ),
      ],
    ];
  }

  // ------------------------------------------------------------------
  // 5: Diagnose - testet alle Server-Bereiche DIREKT vom Gerät. Damit
  // sieht der Nutzer (und wir im Support), welcher Bereich wirklich
  // hakt - statt "Etwas ist schiefgelaufen" ohne Ursache zu raten.
  // ------------------------------------------------------------------
  Widget _buildDiagnosticsSection() {
    final entries = _diagResults.entries.toList();
    return _buildSection('diagnostics', 'Diagnose', icon: Icons.troubleshoot_outlined, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
        child: Text(
          'Testet Server, Anmeldung, Chat, Marktplatz und Garage direkt vom Gerät aus. '
          'Nützlich, wenn ein Bereich "Etwas ist schiefgelaufen" zeigt.',
          style: AppTypography.caption,
        ),
      ),
      for (final e in entries)
        ListTile(
          dense: true,
          leading: Icon(
            e.value.startsWith('✓') ? Icons.check_circle : Icons.error_outline,
            color: e.value.startsWith('✓') ? AppColors.statusSuccess : AppColors.statusDanger,
            size: 20,
          ),
          title: Text(e.key, style: AppTypography.body),
          subtitle: Text(e.value.substring(2), style: AppTypography.caption),
        ),
      ListTile(
        leading: _runningDiagnostics
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.play_arrow, color: AppColors.accentPrimaryDark),
        title: Text(_runningDiagnostics ? 'Tests laufen…' : 'Tests starten', style: AppTypography.body),
        onTap: _runningDiagnostics ? null : _runDiagnostics,
      ),
    ]);
  }

  /// Führt alle Prüfungen SEQUENZIELL aus (klare Reihenfolge, keine
  /// konkurrierenden setStates). Jede Zeile zeigt ✓/✗ plus Detail.
  Future<void> _runDiagnostics() async {
    setState(() {
      _runningDiagnostics = true;
      _diagResults.clear();
    });

    Future<void> report(String name, Future<String> Function() run) async {
      try {
        final detail = await run();
        if (!mounted) return;
        setState(() => _diagResults[name] = '✓ $detail');
      } on TimeoutException {
        if (!mounted) return;
        setState(() => _diagResults[name] = '✗ Keine Antwort (Timeout)');
      } on DioException catch (e) {
        if (!mounted) return;
        setState(() => _diagResults[name] = '✗ ${friendlyErrorMessage(e, ref.read(i18nProvider))}');
      } catch (e) {
        if (!mounted) return;
        setState(() => _diagResults[name] = '✗ $e');
      }
    }

    // 1) Backend-Grundgesundheit (anonym).
    String? token;
    await report('Server (API)', () async {
      final sw = Stopwatch()..start();
      final res = await ApiClient.create()
          .get<Map<String, dynamic>>('/v1/health')
          .timeout(const Duration(seconds: 20));
      final ok = res.data?['status'] == 'ok';
      return '${ok ? 'HTTP 200' : 'unerwartete Antwort'} · ${sw.elapsedMilliseconds} ms';
    });

    // 2) Anmeldung (Token da?).
    await report('Anmeldung', () async {
      token = ref.read(authControllerProvider.notifier).accessToken;
      if (token == null || token!.isEmpty) {
        return 'Nicht angemeldet - bitte einloggen';
      }
      return 'Sitzung aktiv';
    });

    // 3) Chat: Konversationen laden (gleicher Call wie der Chat-Hub).
    await report('Chat', () async {
      if (token == null) return 'übersprungen (nicht angemeldet)';
      await ref.read(chatRepositoryProvider).conversations(token!).timeout(const Duration(seconds: 20));
      return 'Konversationen geladen';
    });

    // 4) Marktplatz: Katalog laden (gleicher Call wie der Markt-Screen).
    await report('Marktplatz', () async {
      if (token == null) return 'übersprungen (nicht angemeldet)';
      final cat = await ref
          .read(marketplaceRepositoryProvider)
          .catalog(token: token!)
          .timeout(const Duration(seconds: 20));
      return '${cat.categories.length} Kategorien geladen';
    });

    // 5) Garage: Übersicht laden (gleicher Call wie der Garage-Screen).
    await report('Garage', () async {
      final base = await ref.read(garageBaseUrlProvider.future);
      final session = ref.read(garageSessionProvider).value;
      if (session == null) return 'Nicht verbunden - Garage verbindet sich automatisch';
      await ref
          .read(garageRepositoryProvider)
          .garage(base, session.token)
          .timeout(const Duration(seconds: 20));
      return 'verbunden (${base.replaceAll('https://', '')})';
    });

    if (!mounted) return;
    setState(() => _runningDiagnostics = false);
  }

  // ------------------------------------------------------------------
  // 6: Sprache & Erscheinungsbild.
  // ------------------------------------------------------------------
  Widget _buildLanguageSection() {
    final i18n = ref.watch(i18nProvider);
    final currentLanguage = ref.watch(languageControllerProvider);
    final currentThemeMode = ref.watch(themeModeControllerProvider);

    return _buildSection('language', i18n.tr('settings.languageAndAppearance'), icon: Icons.language, children: [
      ListTile(
        leading: const Icon(Icons.language, color: AppColors.textSecondaryDark, size: 20),
        title: Text(i18n.languageLabel, style: AppTypography.body),
        trailing: SegmentedButton<AppLanguage>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: AppLanguage.de, label: const Text('🇩🇪 DE')),
            ButtonSegment(value: AppLanguage.en, label: const Text('🇬🇧 EN')),
          ],
          selected: {currentLanguage},
          onSelectionChanged: (selection) {
            ref.read(languageControllerProvider.notifier).set(selection.first);
          },
        ),
      ),
      ListTile(
        leading: const Icon(Icons.contrast, color: AppColors.textSecondaryDark, size: 20),
        title: Text(i18n.themeModeTitle, style: AppTypography.body),
        trailing: SegmentedButton<AppThemeMode>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: AppThemeMode.system, label: Text(i18n.themeModeSystem)),
            ButtonSegment(value: AppThemeMode.light, label: Text(i18n.themeModeLight)),
            ButtonSegment(value: AppThemeMode.dark, label: Text(i18n.themeModeDark)),
          ],
          selected: {currentThemeMode},
          onSelectionChanged: (selection) {
            ref.read(themeModeControllerProvider.notifier).set(selection.first);
          },
        ),
      ),
    ]);
  }

  // ------------------------------------------------------------------
  // Wiederverwendbare Bausteine.
  // ------------------------------------------------------------------
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
        backgroundColor: AppColors.bgSurfaceDark,
        title: Text(title, style: AppTypography.title),
        content: Text(body, style: AppTypography.caption),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: danger ? AppColors.statusDanger : AppColors.accentPrimaryDark,
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
  Widget _buildSection(String id, String title, {required List<Widget> children, IconData? icon}) {
    final collapsed = _collapsed.contains(id);
    final header = Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: AppColors.textSecondaryDark),
            const SizedBox(width: AppSpacing.sm),
          ] else ...[
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: AppColors.accentPrimaryDark,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondaryDark,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
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
                color: AppColors.textMutedDark,
              ),
            ]),
          ),
        ),
        if (!collapsed) ...[
          const SizedBox(height: AppSpacing.xs),
          Container(
            decoration: BoxDecoration(
              color: AppColors.bgSurfaceDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderHairlineDark),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(children: children),
          ),
        ],
      ],
    );
  }

  Widget _buildListTile(IconData icon, String title, String? subtitle, VoidCallback? onTap) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondaryDark, size: 20),
      title: Text(title, style: AppTypography.body),
      subtitle: subtitle != null ? Text(subtitle, style: AppTypography.caption) : null,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
    );
  }

  Widget _buildSwitchTile(IconData icon, String title, bool value, ValueChanged<bool> onChanged) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondaryDark, size: 20),
      title: Text(title, style: AppTypography.body),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.accentPrimaryDark,
        inactiveThumbColor: AppColors.textMutedDark,
        inactiveTrackColor: AppColors.bgSurfaceRaisedDark,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
    );
  }
}

class _PasswordChange {
  final String currentPassword;
  final String newPassword;
  const _PasswordChange(this.currentPassword, this.newPassword);
}

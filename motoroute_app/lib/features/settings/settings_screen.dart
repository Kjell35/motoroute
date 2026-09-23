import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/constants/route_enums.dart';
import 'package:motoroute_app/core/i18n/i18n.dart';
import 'package:motoroute_app/core/network/api_client.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';
import 'package:motoroute_app/core/utils/formatters.dart' show DistanceUnit;
import 'package:motoroute_app/features/auth/auth_providers.dart';
import 'package:motoroute_app/features/chat/chat_providers.dart';
import 'package:motoroute_app/features/chat/data/chat_repository.dart';
import 'package:motoroute_app/features/map/data/map_style.dart';
import 'package:motoroute_app/features/ride_history/ride_history_settings.dart';
import 'package:motoroute_app/features/settings/energy_saver.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Screen 11: Einstellungen (vollständig).
///
/// Bereiche: Konto (Profil/Passwort/Konto löschen/Abmelden), Navigation
/// (Fahrzeug/Einheiten/Energiesparen), Karte (POI-Kategorien),
/// Benachrichtigungen (In-App-Badge), Server & Verbindung (URL +
/// Verbindungstest), Sprache & Erscheinungsbild (ehrlich: fest verdrahtet),
/// Datenschutz/Impressum/Über, App-Version.
///
/// Bewusst NICHT vorhanden: manuelle Token-/Key-Eingaben. Chat und Konto
/// laufen ausschließlich über die App-Anmeldung (Auth-Brücke); API-Keys
/// liegen nur im Backend.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _runningHealthCheck = false;
  String? _healthResult; // null = noch nicht getestet
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

  /// Echter Verbindungstest: GET /v1/health (anonym, kein Auth nötig).
  /// Misst Latenz und zeigt ein klares Ergebnis statt nur Fehlermeldungen.
  Future<void> _runHealthCheck() async {
    setState(() {
      _runningHealthCheck = true;
      _healthResult = null;
    });
    final sw = Stopwatch()..start();
    try {
      final response = await ApiClient.create()
          .get<Map<String, dynamic>>('/v1/health')
          .timeout(const Duration(seconds: 8));
      sw.stop();
      final ok = response.data?['status'] == 'ok';
      if (!mounted) return;
      setState(() {
        _healthResult = ok
            ? 'Verbunden - Antwort in ${sw.elapsedMilliseconds} ms ✓'
            : 'Server antwortet, aber mit unerwartetem Inhalt';
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _healthResult = e.type == DioExceptionType.connectionError ||
                e.type == DioExceptionType.connectionTimeout
            ? 'Nicht erreichbar: Host/Port falsch oder Server aus? URL prüfen.'
            : 'Server antwortete mit Fehler (HTTP ${e.response?.statusCode ?? '?'})';
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _healthResult = 'Keine Antwort innerhalb von 8 s');
    } finally {
      if (mounted) setState(() => _runningHealthCheck = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicleType = ref.watch(vehicleTypeProvider);
    final auth = ref.watch(authControllerProvider);
    final unit = ref.watch(distanceUnitProvider);
    final categories = ref.watch(activePoiCategoriesProvider);
    final energy = ref.watch(energySaverControllerProvider);
    final notifications = ref.watch(notificationsEnabledProvider);
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
            _buildAccountSection(context, ref, auth),
            const SizedBox(height: AppSpacing.lg),
            _buildSection(i18n.navigation, [
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
            _buildPoiSection(categories),
            const SizedBox(height: AppSpacing.lg),
            _buildSection(i18n.tr('settings.notifications'), [
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
            ]),
            const SizedBox(height: AppSpacing.lg),
            _buildChatStatusSection(),
            const SizedBox(height: AppSpacing.lg),
            _buildChatNameSection(),
            const SizedBox(height: AppSpacing.lg),
            _buildRideHistorySection(),
            const SizedBox(height: AppSpacing.lg),
            _buildServerSection(),
            const SizedBox(height: AppSpacing.lg),
            _buildLanguageAppearanceSection(),
            const SizedBox(height: AppSpacing.lg),
            _buildSection(i18n.tr('settings.legal'), [
              _buildListTile(Icons.privacy_tip_outlined, 'Datenschutz', 'Welche Daten MotoRoute verarbeitet', () {
                Navigator.of(context).pushNamed('/privacy');
              }),
              _buildListTile(Icons.description_outlined, 'Impressum', 'Betreiber der Instanz', () {
                Navigator.of(context).pushNamed('/imprint');
              }),
              _buildListTile(Icons.info_outline, 'Über MotoRoute', 'Version, Datenquellen, Danksagung', () {
                Navigator.of(context).pushNamed('/about');
              }),
            ]),
            const SizedBox(height: AppSpacing.lg),
            ListTile(
              dense: true,
              title: Text(i18n.appVersion, style: AppTypography.body),
              trailing: Text(_appVersion, style: AppTypography.caption),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Konto: Profil, Passwort, Konto löschen, Abmelden - alles echt.
  // ------------------------------------------------------------------
  Widget _buildAccountSection(BuildContext context, WidgetRef ref, AuthState auth) {
    if (!auth.isAuthenticated) {
      return _buildSection('Konto', [
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
    return _buildSection('Konto', [
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
      // Tarif-Status (Premium-Vorbereitung): wird aus /v1/users/me
      // gelesen; in der Testphase ist alles kostenlos.
      ListTile(
        dense: true,
        leading: const Icon(Icons.workspace_premium_outlined, color: AppColors.accentPrimaryDark, size: 20),
        title: Text('Testphase - alle Funktionen kostenlos', style: AppTypography.caption),
        subtitle: Text(
          'Premium (10 €/Monat) ist später geplant, aktuell ohne Paywall.',
          style: AppTypography.caption,
        ),
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
  // Karte: POI-Kategorien (persistent).
  // ------------------------------------------------------------------
  Widget _buildPoiSection(Set<PoiCategory> categories) {
    final i18n = ref.watch(i18nProvider);
    return _buildSection(i18n.tr('settings.mapPoiSection'), [
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.sm),
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final category in PoiCategory.values)
              FilterChip(
                label: Text(category.label, style: const TextStyle(fontSize: 12)),
                selected: categories.contains(category),
                onSelected: (selected) {
                  final next = {...categories};
                  selected ? next.add(category) : next.remove(category);
                  if (next.isEmpty) return; // immer mindestens eine Kategorie
                  ref.read(activePoiCategoriesProvider.notifier).state = next;
                  persistPoiCategories(next);
                },
                checkmarkColor: AppColors.accentPrimaryDark,
                selectedColor: AppColors.accentPrimaryDark.withValues(alpha: 0.25),
                backgroundColor: AppColors.bgSurfaceRaisedDark,
                labelStyle: TextStyle(
                  color: categories.contains(category)
                      ? AppColors.textPrimaryDark
                      : AppColors.textSecondaryDark,
                ),
                side: BorderSide(
                  color: categories.contains(category)
                      ? AppColors.accentPrimaryDark
                      : AppColors.borderHairlineDark,
                ),
                showCheckmark: false,
              ),
          ],
        ),
      ),
    ]);
  }

  // ------------------------------------------------------------------
  // Server & Verbindung: Status + echter Verbindungstest gegen
  // /v1/health. KEIN URL-Eingabefeld mehr - die Backend-URL ist fest
  // im APK (dart-define), normale Nutzer tragen nie etwas ein.
  // ------------------------------------------------------------------
  Widget _buildServerSection() {
    return _buildSection('Server & Verbindung', [
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _runningHealthCheck ? null : _runHealthCheck,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accentPrimaryDark,
                    side: const BorderSide(color: AppColors.accentPrimaryDark),
                  ),
                  icon: _runningHealthCheck
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check, size: 18),
                  label: const Text('Verbindung testen'),
                ),
              ],
            ),
            if (_healthResult != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_healthResult!, style: AppTypography.caption),
            ],
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Die Verbindung zum MotoRoute-Server ist fest konfiguriert - kein API-Key und keine URL nötig. Falls Probleme auftreten, hier testen.',
              style: AppTypography.caption,
            ),
          ],
        ),
      ),
    ]);
  }

  // ------------------------------------------------------------------
  // Chat-Status (read-only): Token kommt automatisch aus der App-
  // Anmeldung (Auth-Brücke) - hier gibt es bewusst kein Eingabefeld mehr.
  // ------------------------------------------------------------------
  /// Sprache (DE/EN) + Kartenstil (HELL als Standard / Dunkel). Beide
  /// Wahlem werden GERAETEWEIT persistiert und wirken sofort (Provider).
  Widget _buildLanguageAppearanceSection() {
    final i18n = ref.watch(i18nProvider);
    final currentLanguage = ref.watch(languageControllerProvider);
    final currentStyle = ref.watch(mapStyleChoiceProvider);

    return _buildSection(i18n.tr('settings.languageAndAppearance'), [
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
        leading: const Icon(Icons.map_outlined, color: AppColors.textSecondaryDark, size: 20),
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
    ]);
  }

  /// Chat-Anzeigename: welcher Name in ALLEN Chats erscheint
  /// (Benutzername / Vorname / eigener Name). Persistiert im Profil
  /// (users-Tabelle) - gilt damit geräteübergreifend.
  Widget _buildChatNameSection() {
    final i18n = ref.watch(i18nProvider);
    final me = ref.watch(chatMeProvider).value;
    final token = ref.watch(chatSessionTokenProvider);

    return _buildSection(i18n.tr('settings.chatName'), [
      ListTile(
        leading: const Icon(Icons.badge_outlined, color: AppColors.textSecondaryDark, size: 20),
        title: Text(i18n.tr('settings.chatName.mode'), style: AppTypography.body),
        subtitle: Text(
          me?.effectiveName ?? '–',
          style: AppTypography.caption,
        ),
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
    ]);
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

  Widget _buildChatStatusSection() {
    final token = ref.watch(chatSessionTokenProvider);
    final me = ref.watch(chatMeProvider).value;
    final i18n = ref.watch(i18nProvider);
    return _buildSection(i18n.tr('settings.chatCommunity'), [
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
    ]);
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

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section-Header mit Akzent-Marker - klarere Hierarchie als
        // der alte reine Caption-Text.
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xs),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: AppColors.accentPrimaryDark,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                title.toUpperCase(),
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondaryDark,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
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

  // ------------------------------------------------------------------
  // Fahrhistorie: 5 Privatsphäre-Schalter (Default alles privat).
  // Server ist die Wahrheit, optimistische UI mit Rollback.
  // ------------------------------------------------------------------
  Widget _buildRideHistorySection() {
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

    return _buildSection(i18n.tr('settings.rideHistory'), [
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
    ]);
  }
}

class _PasswordChange {
  final String currentPassword;
  final String newPassword;
  const _PasswordChange(this.currentPassword, this.newPassword);
}

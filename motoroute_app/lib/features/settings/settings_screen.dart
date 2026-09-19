import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/constants/route_enums.dart';
import 'package:motoroute_app/core/network/api_client.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';
import 'package:motoroute_app/core/utils/formatters.dart' show DistanceUnit;
import 'package:motoroute_app/features/chat/chat_providers.dart';
import 'package:motoroute_app/features/chat/data/chat_repository.dart';
import 'package:motoroute_app/features/settings/energy_saver.dart';

/// Screen 11: Einstellungen. Fahrzeug, Einheiten und POI-Kategorien
/// sind ECHTE, persistente Toggles (shared_preferences - überleben
/// App-Starts und Updates); der Server-Bereich schaltet REST und
/// WebSocket auf eine andere Backend-Instanz um (Runtime-Override,
/// wirksam nach App-Neustart vollständig, neue Requests sofort).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _serverController;
  bool _serverDirty = false;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(text: ApiClient.baseUrl);
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _saveServer() async {
    await ApiClient.saveBaseUrl(_serverController.text);
    if (!mounted) return;
    setState(() => _serverDirty = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Server gespeichert. Neue Anfragen nutzen ihn sofort - für Chat/Karte einmal App neu starten.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vehicleType = ref.watch(vehicleTypeProvider);
    final unit = ref.watch(distanceUnitProvider);
    final categories = ref.watch(activePoiCategoriesProvider);
    final energy = ref.watch(energySaverControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBaseDark,
        title: Text('Einstellungen', style: AppTypography.title),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          children: [
            _buildSection('Fahrzeug', [
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
            ]),
            const SizedBox(height: AppSpacing.lg),
            _buildSection('Navigation', [
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
                              ? 'Energiesparmodus aktiv - GPS wird während der Navigation gedrosselt. Bei kritischem Akku (< 15 %) wird die Genauigkeit weiter reduziert.'
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
                  subtitle: Text(
                    'Akkustand: ${energy.batteryLevelPercent} %',
                    style: AppTypography.caption,
                  ),
                ),
            ]),
            const SizedBox(height: AppSpacing.lg),
            _buildPoiSection(categories),
            const SizedBox(height: AppSpacing.lg),
            _buildServerSection(),
            const SizedBox(height: AppSpacing.lg),
            _buildChatSection(context, ref),
            const SizedBox(height: AppSpacing.lg),
            _buildSection('Konto', [
              _buildListTile(Icons.person_outline, 'Profil', 'Kommt mit Supabase-Auth', null),
              _buildListTile(Icons.privacy_tip_outlined, 'Datenschutz', 'Datenlöschung', null),
              const ListTile(
                dense: true,
                title: Text('App-Version', style: AppTypography.body),
                trailing: Text('0.1.1', style: AppTypography.caption),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.caption),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bgSurfaceDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderHairlineDark),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  /// POI-Kategorien: Sichtbarkeit der Karten-Layer, persistent pro
  /// Gerät (gleiche Kategorien wie der Auswahl-Screen auf der Karte).
  Widget _buildPoiSection(Set<PoiCategory> categories) {
    return _buildSection('Karte - POI-Kategorien', [
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

  /// Server & Verbindung: Die App spricht NUR mit dem eigenen Backend.
  /// Diese URL kann auf dem Gerät umgestellt werden (eigener Server im
  /// LAN, eigener VPS, später Produktion) - ohne Neubau der App.
  Widget _buildServerSection() {
    return _buildSection('Server & Verbindung', [
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _serverController,
              onChanged: (_) => setState(() => _serverDirty = true),
              keyboardType: TextInputType.url,
              autocorrect: false,
              style: AppTypography.caption,
              decoration: InputDecoration(
                labelText: 'Backend-URL',
                hintText: 'http://192.168.1.50:3000',
                hintStyle: const TextStyle(color: AppColors.textMutedDark, fontSize: 12),
                labelStyle: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.borderHairlineDark),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.accentPrimaryDark),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                if (_serverDirty)
                  Expanded(
                    child: SizedBox(
                      height: AppSpacing.touchTargetPlanning,
                      child: ElevatedButton.icon(
                        onPressed: _saveServer,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentPrimaryDark,
                          foregroundColor: AppColors.textPrimaryDark,
                        ),
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text('Speichern'),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Leer lassen = eingebaute Standard-URL. Die Karte (OpenStreetMap/CARTO) braucht keinen API-Key; Verkehrs-, Wetter- und Routing-Daten liefert das Backend.',
              style: AppTypography.caption,
            ),
          ],
        ),
      ),
    ]);
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

  /// Chat-Bereich der Einstellungen: Session-Anmeldung + Datenschutz.
  /// Das Token wird bewusst HIER gesetzt (dezent), bis das Login-Feature
  /// den Session-Store liefert - der Chat liest es ausschließlich über
  /// chatSessionTokenProvider (keine Kopplung an diesen Screen).
  Widget _buildChatSection(BuildContext context, WidgetRef ref) {
    final token = ref.watch(chatSessionTokenProvider);
    final me = ref.watch(chatMeProvider).value;

    return _buildSection('Chat & Community', [
      ListTile(
        leading: const Icon(Icons.forum_outlined, color: AppColors.textSecondaryDark, size: 20),
        title: const Text('Chat-Konto', style: AppTypography.body),
        subtitle: Text(
          token == null
              ? 'Nicht angemeldet - Token in das Feld unten einfügen'
              : 'Angemeldet als ${me?.effectiveName ?? '…'}',
          style: AppTypography.caption,
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: TextField(
          obscureText: true,
          enabled: true,
          controller: TextEditingController(text: token ?? ''),
          onSubmitted: (value) {
            final trimmed = value.trim();
            ref.read(chatSessionTokenProvider.notifier).state = trimmed.isEmpty ? null : trimmed;
            if (trimmed.isNotEmpty) {
              // Profil + Listen direkt laden (Chat-Hub refresh).
              ref.invalidate(chatMeProvider);
            }
          },
          style: AppTypography.caption,
          decoration: const InputDecoration(
            hintText: 'Supabase Access-Token (JWT)',
            hintStyle: TextStyle(color: AppColors.textMutedDark, fontSize: 12),
            border: InputBorder.none,
          ),
        ),
      ),
      _buildSwitchTile(
        Icons.visibility_outlined,
        'Online-Status anzeigen',
        me?.showOnline ?? true,
        token == null
            ? (_) {}
            : (value) async {
                try {
                  await ref.read(chatRepositoryProvider).updateMe(token, showOnline: value);
                  ref.invalidate(chatMeProvider);
                } catch (_) {}
              },
      ),
    ]);
  }
}

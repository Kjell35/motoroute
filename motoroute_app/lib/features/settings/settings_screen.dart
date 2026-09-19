import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/constants/route_enums.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';
import 'package:motoroute_app/core/utils/formatters.dart';
import 'package:motoroute_app/features/chat/chat_providers.dart';
import 'package:motoroute_app/features/chat/data/chat_repository.dart';
import 'package:motoroute_app/features/settings/energy_saver.dart';

/// Screen 11: Einstellungen - ruhige Listen-Struktur. Fahrzeugstandard
/// und Einheiten sind echte Toggles gegen die globalen Provider; die
/// übrigen Punkte bleiben bewusst inaktiv, bis Auth (Supabase) und
/// Energiesparmodus (Sprint 11) umgesetzt sind.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleType = ref.watch(vehicleTypeProvider);
    final unit = ref.watch(distanceUnitProvider);
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
                trailing: SegmentedButton<VehicleType>(
                  segments: const [
                    ButtonSegment(value: VehicleType.motorcycle, icon: Icon(Icons.two_wheeler, size: 18)),
                    ButtonSegment(value: VehicleType.car, icon: Icon(Icons.directions_car, size: 18)),
                    ButtonSegment(value: VehicleType.bicycle, icon: Icon(Icons.pedal_bike, size: 18)),
                  ],
                  selected: {vehicleType},
                  onSelectionChanged: (selection) =>
                      ref.read(vehicleTypeProvider.notifier).state = selection.first,
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
                  onSelectionChanged: (selection) =>
                      ref.read(distanceUnitProvider.notifier).state = selection.first,
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
            _buildChatSection(context, ref),
            const SizedBox(height: AppSpacing.lg),
            _buildSection('Konto', [
              _buildListTile(Icons.person_outline, 'Profil', 'Kommt mit Supabase-Auth', null),
              _buildListTile(Icons.privacy_tip_outlined, 'Datenschutz', 'Datenlöschung', null),
              const ListTile(
                dense: true,
                title: Text('App-Version', style: AppTypography.body),
                trailing: Text('0.1.0', style: AppTypography.caption),
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

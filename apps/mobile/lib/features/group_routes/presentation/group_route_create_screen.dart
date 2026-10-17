import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/route_enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../chat/chat_providers.dart';
import '../../search/search_providers.dart';
import '../group_route_repository.dart';

/// „Neue Gruppenroute“ (Abschnitt 2/3/4/29): Name, Start/Ziel (über die
/// bestehende Ortssuche), Fahrzeug (Default: Motorrad), Routenstil,
/// Vermeidungen - und die Pflichtfrage „Wer darf diese Route bearbeiten?“.
class GroupRouteCreateScreen extends ConsumerStatefulWidget {
  final String groupId;
  const GroupRouteCreateScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupRouteCreateScreen> createState() => _GroupRouteCreateScreenState();
}

class _GroupRouteCreateScreenState extends ConsumerState<GroupRouteCreateScreen> {
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();

  SearchResult? _start;
  SearchResult? _destination;
  VehicleType _vehicle = VehicleType.motorcycle;
  RouteStyle _style = RouteStyle.curvy;
  final Set<AvoidOption> _avoid = {AvoidOption.highway, AvoidOption.ferry, AvoidOption.toll};
  EditingPermission _permission = EditingPermission.allMembers;

  bool _searching = false;
  List<SearchResult> _results = [];
  bool _pickingStart = true;
  bool _creating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Timer? _debounce;

  Future<void> _runSearch(String query) async {
    // Nutzt das bestehende SearchRepository (Ortssuche mit PLZ-Support).
    _debounce?.cancel();
    if (query.trim().length < 3) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _searching = true);
      try {
        final repo = ref.read(searchRepositoryProvider);
        final list = await repo.search(query.trim());
        if (!mounted) return;
        setState(() {
          _results = list;
          _searching = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _searching = false);
      }
    });
  }

  Future<void> _create() async {
    final token = ref.read(chatSessionTokenProvider);
    final name = _nameController.text.trim();
    if (token == null || name.isEmpty || _start == null || _destination == null || _creating) return;
    setState(() => _creating = true);
    try {
      final repo = ref.read(groupRouteRepositoryProvider);
      final routeId = await repo.create(
        token,
        groupId: widget.groupId,
        name: name,
        startLat: _start!.lat,
        startLng: _start!.lng,
        startName: _start!.label,
        destLat: _destination!.lat,
        destLng: _destination!.lng,
        destName: _destination!.label,
        vehicleType: _vehicle.apiValue,
        routingStyle: _style.apiValue,
        avoidHighways: _avoid.contains(AvoidOption.highway),
        avoidFerries: _avoid.contains(AvoidOption.ferry),
        avoidTolls: _avoid.contains(AvoidOption.toll),
        permission: _permission.apiValue,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        '/chat/group-route-planner',
        arguments: {'routeId': routeId},
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Route konnte nicht erstellt werden: ${e.toString().split('(').first}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(backgroundColor: AppColors.bgBaseDark, title: const Text('Neue Gruppenroute')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          TextField(
            controller: _nameController,
            maxLength: 80,
            style: const TextStyle(color: AppColors.textPrimaryDark),
            decoration: _input('Name der Tour', 'z. B. Alpenrunde'),
          ),
          const SizedBox(height: AppSpacing.md),

          // Start / Ziel über die bestehende Ortssuche (Abschnitt 2).
          _locationField(
            label: _start?.label ?? 'Start wählen (Adresse, Ort, PLZ)',
            icon: Icons.trip_origin,
            onTap: () => _openSearch(isStart: true),
          ),
          const SizedBox(height: AppSpacing.sm),
          _locationField(
            label: _destination?.label ?? 'Ziel wählen (Adresse, Ort, PLZ)',
            icon: Icons.flag,
            onTap: () => _openSearch(isStart: false),
          ),
          const SizedBox(height: AppSpacing.lg),

          Text('Fahrzeug', style: _sectionLabel()),
          const SizedBox(height: AppSpacing.sm),
          SegmentedButton<VehicleType>(
            segments: const [
              ButtonSegment(value: VehicleType.motorcycle, icon: Icon(Icons.two_wheeler, size: 18)),
              ButtonSegment(value: VehicleType.car, icon: Icon(Icons.directions_car, size: 18)),
              ButtonSegment(value: VehicleType.bicycle, icon: Icon(Icons.pedal_bike, size: 18)),
            ],
            selected: {_vehicle},
            onSelectionChanged: (s) => setState(() => _vehicle = s.first),
          ),
          const SizedBox(height: AppSpacing.lg),

          Text('Routenstil', style: _sectionLabel()),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _styleChip('Schnell', RouteStyle.fast),
              _styleChip('Kurvig', RouteStyle.curvy),
              _styleChip('Extra kurvig', RouteStyle.extraCurvy),
              _styleChip('Schnell & kurvig', RouteStyle.fastAndCurvy),
              _styleChip('Unbefestigt', RouteStyle.unpaved),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          Text('Vermeiden', style: _sectionLabel()),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            children: [
              _avoidChip('Autobahn', AvoidOption.highway),
              _avoidChip('Fähren', AvoidOption.ferry),
              _avoidChip('Maut', AvoidOption.toll),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // Berechtigungsfrage (Abschnitt 4) - Pflichtdialog direkt im
          // Erstellen-Flow statt später versteckt in den Einstellungen.
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.bgSurfaceDark,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderHairlineDark),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Wer darf diese Route bearbeiten?',
                    style: TextStyle(
                        color: AppColors.textPrimaryDark, fontWeight: FontWeight.w700)),
                const SizedBox(height: AppSpacing.sm),
                RadioListTile<EditingPermission>(
                  value: EditingPermission.allMembers,
                  groupValue: _permission,
                  activeColor: AppColors.accentPrimaryDark,
                  title: const Text('🔓 Alle Gruppenmitglieder',
                      style: TextStyle(color: AppColors.textPrimaryDark, fontSize: 14)),
                  subtitle: const Text('Alle dürfen Stopps hinzufügen, verschieben, löschen',
                      style: TextStyle(color: AppColors.textMutedDark, fontSize: 12)),
                  onChanged: (v) => setState(() => _permission = v!),
                ),
                RadioListTile<EditingPermission>(
                  value: EditingPermission.ownerOnly,
                  groupValue: _permission,
                  activeColor: AppColors.accentPrimaryDark,
                  title: const Text('🔒 Nur der Owner',
                      style: TextStyle(color: AppColors.textPrimaryDark, fontSize: 14)),
                  subtitle: const Text('Andere sehen und fahren die Route nur',
                      style: TextStyle(color: AppColors.textMutedDark, fontSize: 12)),
                  onChanged: (v) => setState(() => _permission = v!),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentPrimaryDark,
              foregroundColor: AppColors.textPrimaryDark,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: (_creating || _start == null || _destination == null || _nameController.text.trim().isEmpty)
                ? null
                : _create,
            child: _creating
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('ROUTE ERSTELLEN', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1)),
          ),
        ],
      ),
    );
  }

  void _openSearch({required bool isStart}) {
    setState(() => _pickingStart = isStart);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurfaceDark,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: _runSearch,
                style: const TextStyle(color: AppColors.textPrimaryDark),
                decoration: _input('Ort, Adresse oder PLZ …', 'z. B. München'),
              ),
            ),
            Expanded(
              child: _searching
                  ? const Center(child: CircularProgressIndicator(color: AppColors.accentPrimaryDark))
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, i) {
                        final r = _results[i];
                        return ListTile(
                          leading: const Icon(Icons.place, color: AppColors.accentPrimaryDark, size: 20),
                          title: Text(r.label,
                              style: const TextStyle(color: AppColors.textPrimaryDark, fontSize: 14)),
                          onTap: () {
                            setState(() {
                              if (_pickingStart) {
                                _start = r;
                              } else {
                                _destination = r;
                              }
                            });
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _sectionLabel() =>
      const TextStyle(color: AppColors.textSecondaryDark, fontSize: 13, fontWeight: FontWeight.w600);

  InputDecoration _input(String label, String hint) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSecondaryDark),
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMutedDark),
        filled: true,
        fillColor: AppColors.bgSurfaceDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderHairlineDark),
        ),
        counterText: '',
      );

  Widget _locationField({required String label, required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.bgSurfaceDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderHairlineDark),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.accentPrimaryDark, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: label.startsWith('Start wählen') || label.startsWith('Ziel wählen')
                          ? AppColors.textMutedDark
                          : AppColors.textPrimaryDark)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _styleChip(String label, RouteStyle style) {
    final selected = _style == style;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: AppColors.accentPrimaryDark.withValues(alpha: 0.35),
      labelStyle: TextStyle(
          color: selected ? AppColors.textPrimaryDark : AppColors.textSecondaryDark),
      onSelected: (_) => setState(() => _style = style),
    );
  }

  Widget _avoidChip(String label, AvoidOption option) {
    final selected = _avoid.contains(option);
    return FilterChip(
      label: Text(label),
      selected: selected,
      selectedColor: AppColors.accentPrimaryDark.withValues(alpha: 0.35),
      checkmarkColor: AppColors.textPrimaryDark,
      labelStyle: TextStyle(
          color: selected ? AppColors.textPrimaryDark : AppColors.textSecondaryDark),
      onSelected: (v) => setState(() {
        v ? _avoid.add(option) : _avoid.remove(option);
      }),
    );
  }
}

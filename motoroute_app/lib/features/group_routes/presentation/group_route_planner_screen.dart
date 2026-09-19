import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart' show formatDistanceMeters, formatDurationSeconds;
import '../../chat/chat_providers.dart';
import '../../search/search_providers.dart';
import '../group_route_providers.dart';
import '../group_route_repository.dart';

/// Kollaborativer Planer (Abschnitt 6-14/16/17): Karte-Übersicht, Stopps-
/// Liste mit Reorder/Löschen, Metriken, Status-Banner, Änderungsverlauf,
/// „Route starten“-Übergabe an die normale Navigation.
class GroupRoutePlannerScreen extends ConsumerStatefulWidget {
  final String routeId;
  const GroupRoutePlannerScreen({super.key, required this.routeId});

  @override
  ConsumerState<GroupRoutePlannerScreen> createState() => _GroupRoutePlannerScreenState();
}

class _GroupRoutePlannerScreenState extends ConsumerState<GroupRoutePlannerScreen> {
  Timer? _metricsPoll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(groupRouteDetailProvider(widget.routeId).notifier).load();
      // Recalc läuft serverseitig asynchron - Metriken kurz nachziehen.
      _metricsPoll = Timer.periodic(const Duration(seconds: 8), (_) {
        if (mounted) ref.read(groupRouteDetailProvider(widget.routeId).notifier).refreshFromRealtime();
      });
    });
  }

  @override
  void dispose() {
    _metricsPoll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(groupRouteDetailProvider(widget.routeId));
    final me = ref.watch(chatMeProvider).value;

    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBaseDark,
        title: async.valueOrNull == null
            ? const Text('Gruppenroute')
            : Text(async.valueOrNull!.route.name),
        actions: [
          ..._appBarActions(context, async, me?.id),
          if (async.valueOrNull != null)
            IconButton(
              icon: const Icon(Icons.groups, color: AppColors.textSecondaryDark),
              tooltip: 'Live-Gruppenfahrt',
              onPressed: () => Navigator.of(context)
                  .pushNamed('/chat/group-ride', arguments: {'routeId': widget.routeId}),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accentPrimaryDark)),
        error: (msg, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$msg', style: const TextStyle(color: AppColors.textSecondaryDark)),
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: () => ref.read(groupRouteDetailProvider(widget.routeId).notifier).load(force: true),
                child: const Text('Erneut versuchen'),
              ),
            ],
          ),
        ),
        data: (detail) => _buildBody(context, detail, me?.id),
      ),
    );
  }

  List<Widget> _appBarActions(BuildContext context, AsyncValue<GroupRouteDetail> async, String? meId) {
    final detail = async.valueOrNull;
    if (detail == null) return const [];
    final route = detail.route;
    final isOwner = route.createdBy == meId;
    return [
      PopupMenuButton<String>(
        color: AppColors.bgSurfaceDark,
        icon: const Icon(Icons.more_vert, color: AppColors.textSecondaryDark),
        onSelected: (action) => _onMenuAction(context, action, route, isOwner),
        itemBuilder: (_) => [
          if (isOwner)
            const PopupMenuItem(
                value: 'permission',
                child: Text('Routenberechtigungen', style: TextStyle(color: AppColors.textPrimaryDark))),
          const PopupMenuItem(
              value: 'duplicate', child: Text('Route duplizieren', style: TextStyle(color: AppColors.textPrimaryDark))),
          if (isOwner && route.status == GroupRouteStatus.finalized)
            const PopupMenuItem(
                value: 'lock', child: Text('Route sperren', style: TextStyle(color: AppColors.textPrimaryDark))),
          if (isOwner && route.status == GroupRouteStatus.locked)
            const PopupMenuItem(
                value: 'unlock', child: Text('Route freigeben', style: TextStyle(color: AppColors.textPrimaryDark))),
        ],
      ),
    ];
  }

  Future<void> _onMenuAction(BuildContext context, String action, GroupRoute route, bool isOwner) async {
    final controller = ref.read(groupRouteDetailProvider(widget.routeId).notifier);
    switch (action) {
      case 'permission':
        final current = route.permission;
        final selected = await showDialog<EditingPermission>(
          context: context,
          builder: (dialogContext) => SimpleDialog(
            backgroundColor: AppColors.bgSurfaceDark,
            title: const Text('Routenberechtigungen',
                style: TextStyle(color: AppColors.textPrimaryDark)),
            children: [
              RadioListTile<EditingPermission>(
                value: EditingPermission.allMembers,
                groupValue: current,
                activeColor: AppColors.accentPrimaryDark,
                title: const Text('🔓 Alle Gruppenmitglieder',
                    style: TextStyle(color: AppColors.textPrimaryDark)),
                onChanged: (v) => Navigator.pop(dialogContext, v),
              ),
              RadioListTile<EditingPermission>(
                value: EditingPermission.ownerOnly,
                groupValue: current,
                activeColor: AppColors.accentPrimaryDark,
                title: const Text('🔒 Nur Owner', style: TextStyle(color: AppColors.textPrimaryDark)),
                onChanged: (v) => Navigator.pop(dialogContext, v),
              ),
            ],
          ),
        );
        if (selected != null) await controller.setPermission(selected);
        break;
      case 'duplicate':
        await controller.duplicate('${route.name} - Alternative');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kopie erstellt - siehe Routenliste')),
          );
        }
        break;
      case 'lock':
        await controller.lock();
        break;
      case 'unlock':
        await controller.unlock();
        break;
    }
  }

  Widget _buildBody(BuildContext context, GroupRouteDetail detail, String? meId) {
    final route = detail.route;
    final isOwner = route.createdBy == meId;
    // Bearbeiten darf ich, wenn Owner/Ersteller ODER all_members (nicht
    // gesperrt) - dieselbe Regel wie serverseitig can_edit_route, hier nur
    // für die UI-Präsentation (Abschnitt 32: Server bleibt Autorität).
    final canEdit = route.status != GroupRouteStatus.locked &&
        (isOwner || route.permission == EditingPermission.allMembers);

    return Column(
      children: [
        _statusBanner(route, isOwner),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _metricsCard(route),
              const SizedBox(height: AppSpacing.lg),
              _stopsList(context, detail, canEdit),
              const SizedBox(height: AppSpacing.lg),
              if (canEdit) _addStopButton(context),
              if (canEdit) const SizedBox(height: AppSpacing.lg),
              _historyCard(detail),
              const SizedBox(height: AppSpacing.lg),
              _startButton(context, route),
              const SizedBox(height: AppSpacing.md),
              // Live-Gruppenfahrt (Abschnitt 18): wer fährt mit?
              OutlinedButton.icon(
                icon: const Icon(Icons.groups, color: AppColors.accentSecondary),
                label: const Text('👥 LIVE-GRUPPENFAHRT',
                    style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1)),
                onPressed: () => Navigator.of(context)
                    .pushNamed('/chat/group-ride', arguments: {'routeId': widget.routeId}),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.accentSecondary),
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusBanner(GroupRoute route, bool isOwner) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      color: AppColors.bgSurfaceDark,
      child: Row(
        children: [
          Text(route.status.label,
              style: const TextStyle(color: AppColors.textPrimaryDark, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (isOwner && route.status != GroupRouteStatus.locked)
            TextButton(
              onPressed: () {
                final controller = ref.read(groupRouteDetailProvider(widget.routeId).notifier);
                controller.setStatus(
                  route.status == GroupRouteStatus.finalized
                      ? GroupRouteStatus.planning
                      : GroupRouteStatus.finalized,
                );
              },
              child: Text(
                route.status == GroupRouteStatus.finalized ? 'Weiter planen' : 'Route fertigstellen',
                style: const TextStyle(color: AppColors.accentPrimaryDark),
              ),
            ),
        ],
      ),
    );
  }

  Widget _metricsCard(GroupRoute route) {
    final distance = route.distanceMeters != null
        ? formatDistanceMeters(route.distanceMeters!)
        : '– km';
    final duration = route.durationSeconds != null
        ? formatDurationSeconds(route.durationSeconds!)
        : '–';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.bgSurfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderHairlineDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _metric(distance, 'Entfernung'),
              const SizedBox(width: AppSpacing.xl),
              _metric(duration, 'Fahrzeit'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '${route.startName ?? 'Start'}  →  ${route.destName ?? 'Ziel'}',
            style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            children: [
              _metaChip('🏍️ ${route.vehicleType}'),
              _metaChip('🌀 ${route.routingStyle}'),
              if (route.avoidHighways) _metaChip('🚫 Autobahn'),
              if (route.avoidFerries) _metaChip('🚫 Fähren'),
              if (route.avoidTolls) _metaChip('🚫 Maut'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: const TextStyle(
                color: AppColors.textPrimaryDark, fontSize: 22, fontWeight: FontWeight.w700)),
        Text(label, style: const TextStyle(color: AppColors.textMutedDark, fontSize: 12)),
      ],
    );
  }

  Widget _metaChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.bgSurfaceRaisedDark,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 11)),
    );
  }

  Widget _stopsList(BuildContext context, GroupRouteDetail detail, bool canEdit) {
    final stops = detail.stops;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Stopps (${stops.length})',
            style: const TextStyle(
                color: AppColors.textPrimaryDark, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpacing.sm),
        // START-Marker
        _terminalTile('START', route: true),
        if (stops.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text('Noch keine Stopps - füge Tankstellen, Treffs oder Aussichtspunkte hinzu!',
                style: TextStyle(color: AppColors.textMutedDark)),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: canEdit,
            itemCount: stops.length,
            onReorder: _onReorder,
            itemBuilder: (context, index) {
              final stop = stops[index];
              return _stopTile(context, stop, canEdit, key: ValueKey(stop.id));
            },
          ),
        _terminalTile('ZIEL', route: false),
      ],
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    final detail = ref.read(groupRouteDetailProvider(widget.routeId)).valueOrNull;
    if (detail == null) return;
    final stops = [...detail.stops];
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = stops.removeAt(oldIndex);
    stops.insert(newIndex, moved);
    ref.read(groupRouteDetailProvider(widget.routeId).notifier).reorder(stops);
  }

  Widget _terminalTile(String label, {required bool route}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(route ? Icons.trip_origin : Icons.flag,
              color: AppColors.accentPrimaryDark, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondaryDark, fontWeight: FontWeight.w700, letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _stopTile(BuildContext context, RouteStop stop, bool canEdit, {required Key key}) {
    return ListTile(
      key: key,
      contentPadding: EdgeInsets.zero,
      leading: Text('${stop.position}.',
          style: const TextStyle(color: AppColors.textMutedDark, fontWeight: FontWeight.w700)),
      title: Text(stop.category.label + '  ' + stop.name,
          style: const TextStyle(color: AppColors.textPrimaryDark), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: stop.address != null
          ? Text(stop.address!, style: const TextStyle(color: AppColors.textMutedDark, fontSize: 12))
          : null,
      trailing: canEdit
          ? IconButton(
              icon: const Icon(Icons.close, color: AppColors.textMutedDark, size: 18),
              onPressed: () => _confirmDelete(context, stop),
            )
          : null,
    );
  }

  Future<void> _confirmDelete(BuildContext context, RouteStop stop) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.bgSurfaceDark,
        title: const Text('Stopp wirklich entfernen?', style: TextStyle(color: AppColors.textPrimaryDark)),
        content: Text(stop.name, style: const TextStyle(color: AppColors.textSecondaryDark)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.statusDanger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(groupRouteDetailProvider(widget.routeId).notifier).deleteStop(stop.id);
    }
  }

  Widget _addStopButton(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.add_location_alt, color: AppColors.accentPrimaryDark),
      label: const Text('＋ Stopp hinzufügen',
          style: TextStyle(color: AppColors.textPrimaryDark, fontWeight: FontWeight.w600)),
      onPressed: () => _openAddStopSheet(context),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.accentPrimaryDark),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }

  void _openAddStopSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddStopSheet(routeId: widget.routeId),
    );
  }

  Widget _historyCard(GroupRouteDetail detail) {
    if (detail.history.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgSurfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderHairlineDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Änderungen',
              style: TextStyle(color: AppColors.textSecondaryDark, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: AppSpacing.sm),
          ...detail.history.take(5).map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${c.userName ?? 'Jemand'} · ${_actionLabel(c.action)}${c.detail != null ? ': ${c.detail}' : ''}',
                  style: const TextStyle(color: AppColors.textMutedDark, fontSize: 12),
                ),
              )),
        ],
      ),
    );
  }

  String _actionLabel(String action) => switch (action) {
        'stop_added' => 'Stopp hinzugefügt',
        'stop_removed' => 'Stopp entfernt',
        'reordered' => 'Reihenfolge geändert',
        'recalculated' => 'Route neu berechnet',
        'status_changed' => 'Status geändert',
        'created' => 'Route erstellt',
        'permission_changed' => 'Berechtigungen geändert',
        _ => action,
      };

  Widget _startButton(BuildContext context, GroupRoute route) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accentPrimaryDark,
        foregroundColor: AppColors.textPrimaryDark,
        minimumSize: const Size.fromHeight(56),
      ),
      icon: const Icon(Icons.motorcycle, size: 24),
      label: const Text('ROUTE STARTEN',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 1)),
      onPressed: () {
        // Übergabe an die normale MotoRoute-Navigation (Abschnitt 17).
        Navigator.of(context).pushNamed('/chat/group-route-start',
            arguments: {'routeId': widget.routeId});
      },
    );
  }
}

/// „Stopp hinzufügen“-Sheet (Abschnitt 7): Suche ODER POI-Kategorie
/// (verwendet die bestehende POI-Suche des Backends, sobald eine Karte
/// geöffnet wird; hier: Textsuche + Kategorie-Vorlage).
class _AddStopSheet extends ConsumerStatefulWidget {
  final String routeId;
  const _AddStopSheet({required this.routeId});

  @override
  ConsumerState<_AddStopSheet> createState() => _AddStopSheetState();
}

class _AddStopSheetState extends ConsumerState<_AddStopSheet> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<SearchResult> _results = [];
  bool _searching = false;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search(String query) async {
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

  Future<void> _add(SearchResult r, StopCategory category) async {
    final controller = ref.read(groupRouteDetailProvider(widget.routeId).notifier);
    final stopId = await controller.addStop(RouteStop(
      id: 'pending',
      position: 0,
      lat: r.lat,
      lng: r.lng,
      name: r.label,
      category: category,
      createdBy: '',
      createdAt: '',
    ));
    if (mounted) {
      Navigator.pop(context);
      if (stopId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stopp konnte nicht hinzugefügt werden (keine Berechtigung?)')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Stopp hinzufügen',
                style: TextStyle(color: AppColors.textPrimaryDark, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: _search,
              style: const TextStyle(color: AppColors.textPrimaryDark),
              decoration: InputDecoration(
                hintText: 'Adresse, Ort oder PLZ suchen …',
                hintStyle: const TextStyle(color: AppColors.textMutedDark),
                prefixIcon: const Icon(Icons.search, color: AppColors.textSecondaryDark),
                filled: true,
                fillColor: AppColors.bgSurfaceRaisedDark,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: StopCategory.values
                  .map((c) => ActionChip(
                        label: Text(c.label, style: const TextStyle(fontSize: 12)),
                        backgroundColor: AppColors.bgSurfaceRaisedDark,
                        onPressed: () {
                          // Kategorie als Name-Vorlage ohne Koordinate macht
                          // keinen Sinn - Nutzer sucht zuerst, Kategorie ist
                          // im Suchergebnis anpassbar (Placeholder-Tap).
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${c.label}: Suche zuerst einen Ort aus.')),
                          );
                        },
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 240,
              child: _searching
                  ? const Center(child: CircularProgressIndicator(color: AppColors.accentPrimaryDark))
                  : _results.isEmpty
                      ? const Center(
                          child: Text('Suche einen Ort - oder tippe später direkt auf der Karte.',
                              style: TextStyle(color: AppColors.textMutedDark)))
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (context, i) {
                            final r = _results[i];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.place, color: AppColors.accentPrimaryDark, size: 18),
                              title: Text(r.label,
                                  style: const TextStyle(color: AppColors.textPrimaryDark, fontSize: 13)),
                              onTap: () => _add(r, StopCategory.other),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

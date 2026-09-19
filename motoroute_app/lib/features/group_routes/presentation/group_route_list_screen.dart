import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../chat/chat_providers.dart';
import '../group_route_repository.dart';

/// „🏍️ Route planen“-Bereich der Gruppe (Abschnitt 1): Liste aller
/// gemeinsamen Routen; der Owner sieht „Neue Route planen“.
class GroupRouteListScreen extends ConsumerStatefulWidget {
  final String groupId;
  const GroupRouteListScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupRouteListScreen> createState() => _GroupRouteListScreenState();
}

class _GroupRouteListScreenState extends ConsumerState<GroupRouteListScreen> {
  List<GroupRoute>? _routes;
  String? _error;
  bool _loading = true;
  bool _isOwner = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = ref.read(chatSessionTokenProvider);
    if (token == null) {
      setState(() {
        _loading = false;
        _error = 'Zum Planen anmelden';
      });
      return;
    }
    try {
      final routes = await ref.read(groupRouteRepositoryProvider).listForGroup(token, widget.groupId);
      final me = ref.read(chatMeProvider).value;
      if (!mounted) return;
      setState(() {
        _routes = routes;
        _isOwner = me != null && routes.isNotEmpty && routes.first.createdBy == me.id;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Routen konnten nicht geladen werden';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(backgroundColor: AppColors.bgBaseDark, title: const Text('🏍️ Route planen')),
      floatingActionButton: _isOwner
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.accentPrimaryDark,
              foregroundColor: AppColors.textPrimaryDark,
              icon: const Icon(Icons.add_road),
              label: const Text('Neue Route planen'),
              onPressed: () => Navigator.of(context)
                  .pushNamed('/chat/group-route-create', arguments: {'groupId': widget.groupId}),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accentPrimaryDark))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.textSecondaryDark)))
              : (_routes == null || _routes!.isEmpty)
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.route_outlined, size: 48, color: AppColors.textMutedDark),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              _isOwner
                                  ? 'Noch keine gemeinsame Route.\nPlane die erste Tour für deine Gruppe!'
                                  : 'Der Owner hat noch keine Route geplant.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.textSecondaryDark),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      color: AppColors.accentPrimaryDark,
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: _routes!.length,
                        itemBuilder: (context, i) {
                          final r = _routes![i];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                            leading: const Icon(Icons.route, color: AppColors.accentPrimaryDark),
                            title: Text(r.name,
                                style: const TextStyle(color: AppColors.textPrimaryDark, fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              r.distanceMeters != null
                                  ? '${(r.distanceMeters! / 1000).round()} km · ${r.status.label}'
                                  : r.status.label,
                              style: const TextStyle(color: AppColors.textMutedDark, fontSize: 12),
                            ),
                            trailing: const Icon(Icons.chevron_right, color: AppColors.textMutedDark),
                            onTap: () => Navigator.of(context)
                                .pushNamed('/chat/group-route-planner', arguments: {'routeId': r.id}),
                          );
                        },
                      ),
                    ),
    );
  }
}

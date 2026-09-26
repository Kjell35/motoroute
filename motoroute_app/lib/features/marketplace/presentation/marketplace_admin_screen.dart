import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/network/error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../marketplace_repository.dart';

/// Admin-Bereich (Anforderung 20): Prüfstau (KI + manuell), gemeldete
/// Angebote, Freigabe/Ablehnung/Sperren. Serverseitig per users.role
/// geschützt - ohne Admin-Role antwortet das Backend mit 403.
class MarketplaceAdminScreen extends ConsumerStatefulWidget {
  const MarketplaceAdminScreen({super.key});

  @override
  ConsumerState<MarketplaceAdminScreen> createState() => _MarketplaceAdminScreenState();
}

class _MarketplaceAdminScreenState extends ConsumerState<MarketplaceAdminScreen> {
  List<MpListing> _pending = const [];
  List<({int id, String reason, String details, String listingTitle})> _reports = const [];
  bool _loading = true;
  String? _error;
  bool _isAdmin = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = ref.read(marketplaceTokenProvider);
    if (token == null) {
      setState(() { _loading = false; _error = 'Nicht angemeldet'; });
      return;
    }
    final repo = ref.read(marketplaceRepositoryProvider);
    try {
      final pending = await repo.adminPending(token: token);
      List<({int id, String reason, String details, String listingTitle})> reports = const [];
      try {
        reports = await repo.adminReports(token: token);
      } catch (_) {
        // Reports-Endpunkt ist optional - Pending reicht für den Einstieg.
      }
      if (!mounted) return;
      setState(() {
        _pending = pending;
        _reports = reports;
        _loading = false;
        _isAdmin = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _isAdmin = false;
        _error = friendlyErrorMessage(e, ref.read(i18nProvider));
      });
    }
  }

  Future<void> _moderate(MpListing listing, {bool approve = true}) async {
    final token = ref.read(marketplaceTokenProvider);
    if (token == null) return;
    try {
      await ref.read(marketplaceRepositoryProvider).adminPatch(
            token: token,
            id: listing.id,
            reviewStatus: approve ? 'approved' : 'rejected',
            reason: approve ? 'Manuell freigegeben' : 'Manuell abgelehnt',
          );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.statusDanger,
        content: Text('$e', style: const TextStyle(color: Colors.white)),
      ));
    }
  }

  Future<void> _block(MpListing listing) async {
    final token = ref.read(marketplaceTokenProvider);
    if (token == null) return;
    try {
      await ref.read(marketplaceRepositoryProvider).adminPatch(token: token, id: listing.id, status: 'blocked');
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.statusDanger,
        content: Text('$e', style: const TextStyle(color: Colors.white)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(title: const Text('🛡️ Marktplatz-Admin'), backgroundColor: scheme.surface),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_isAdmin
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Kein Admin-Zugriff.\n$_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.statusDanger),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      const Text('🕵️ Prüfstau (KI unsicher / abgelehnt)',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      if (_pending.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Nichts zu tun - alles geprüft ✅'),
                        ),
                      ..._pending.map((listing) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: scheme.surfaceContainerHigh,
                            elevation: 0,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(listing.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  Text(
                                    '${listing.priceLabel} · ${listing.category.emoji} ${listing.subcategory}',
                                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                                  ),
                                  if (listing.reviewReason != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(listing.reviewReason!,
                                          style: const TextStyle(fontSize: 12)),
                                    ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    children: [
                                      FilledButton.tonal(
                                        onPressed: () => _moderate(listing, approve: true),
                                        child: const Text('✅ Freigeben'),
                                      ),
                                      FilledButton.tonal(
                                        onPressed: () => _moderate(listing, approve: false),
                                        child: const Text('🚫 Ablehnen'),
                                      ),
                                      FilledButton.tonal(
                                        onPressed: () => _block(listing),
                                        child: const Text('⛔ Sperren'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          )),
                      const SizedBox(height: 16),
                      const Text('🚩 Gemeldete Angebote',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      if (_reports.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Keine offenen Meldungen'),
                        ),
                      ..._reports.map((report) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: scheme.surfaceContainerHigh,
                            elevation: 0,
                            child: ListTile(
                              title: Text(report.listingTitle),
                              subtitle: Text('${report.reason}${report.details.isNotEmpty ? '\n${report.details}' : ''}'),
                              isThreeLine: report.details.isNotEmpty,
                              trailing: TextButton(
                                onPressed: () async {
                                  final token = ref.read(marketplaceTokenProvider);
                                  if (token == null) return;
                                  await ref
                                      .read(marketplaceRepositoryProvider)
                                      .adminResolveReport(token: token, reportId: report.id);
                                  _load();
                                },
                                child: const Text('Erledigt'),
                              ),
                            ),
                          )),
                    ],
                  ),
                ),
    );
  }
}

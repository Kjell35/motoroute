import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../marketplace_repository.dart';
import 'marketplace_create_screen.dart';

/// "Meine Angebote" (Anforderung 17): bearbeiten (erneut einreichen),
/// löschen, als verkauft markieren, pausieren, erneut veröffentlichen.
class MarketplaceMyListingsScreen extends ConsumerStatefulWidget {
  const MarketplaceMyListingsScreen({super.key});

  @override
  ConsumerState<MarketplaceMyListingsScreen> createState() => _MarketplaceMyListingsScreenState();
}

class _MarketplaceMyListingsScreenState extends ConsumerState<MarketplaceMyListingsScreen> {
  List<MpListing> _listings = const [];
  bool _loading = true;
  String? _error;

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
    try {
      final listings = await ref.read(marketplaceRepositoryProvider).mine(token: token);
      if (!mounted) return;
      setState(() { _listings = listings; _loading = false; _error = null; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = '$e'; });
    }
  }

  Future<void> _changeStatus(MpListing listing, String status, String successMessage) async {
    final token = ref.read(marketplaceTokenProvider);
    if (token == null) return;
    try {
      await ref.read(marketplaceRepositoryProvider).setStatus(token: token, id: listing.id, status: status);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
      _load();
    } catch (e) {
      if (!mounted) return;
      // 400 NOT_APPROVED = nicht freigegeben - Nutzer klar informieren.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.statusDanger,
        content: Text('$e', style: const TextStyle(color: Colors.white)),
      ));
    }
  }

  Future<void> _delete(MpListing listing) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Angebot löschen?'),
        content: Text('"${listing.title}" wird endgültig entfernt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.statusDanger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final token = ref.read(marketplaceTokenProvider);
    if (token == null) return;
    try {
      await ref.read(marketplaceRepositoryProvider).delete(token: token, id: listing.id);
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
      appBar: AppBar(title: const Text('📦 Meine Angebote'), backgroundColor: scheme.surface),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.statusDanger)))
              : _listings.isEmpty
                  ? const Center(child: Text('Noch keine Angebote'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: _listings.length,
                        padding: const EdgeInsets.all(12),
                        itemBuilder: (context, i) {
                          final listing = _listings[i];
                          return _MyListingTile(
                            listing: listing,
                            onChanged: _load,
                            onDelete: () => _delete(listing),
                            onStatus: (status, msg) => _changeStatus(listing, status, msg),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _MyListingTile extends StatelessWidget {
  final MpListing listing;
  final VoidCallback onChanged;
  final VoidCallback onDelete;
  final void Function(String status, String successMessage) onStatus;

  const _MyListingTile({
    required this.listing,
    required this.onChanged,
    required this.onDelete,
    required this.onStatus,
  });

  ({String label, Color color}) get _reviewBadge => switch (listing.reviewStatus) {
        MpReviewStatus.approved => (label: '✅ Freigegeben', color: AppColors.statusSuccess),
        MpReviewStatus.rejected => (label: '🚫 Abgelehnt', color: AppColors.statusDanger),
        MpReviewStatus.manualReview => (label: '🕵️ Manuelle Prüfung', color: AppColors.accentPrimaryDark),
        MpReviewStatus.pending => (label: '⏳ In Prüfung', color: AppColors.accentPrimaryDark),
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badge = _reviewBadge;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: scheme.surfaceContainerHigh,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(listing.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Text(listing.priceLabel,
                  style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.accentPrimaryDark)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badge.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(badge.label, style: TextStyle(fontSize: 11, color: badge.color, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 6),
              Text(_statusLabel(listing.status), style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ]),
            if (listing.reviewStatus == MpReviewStatus.rejected && listing.reviewReason != null) ...[
              const SizedBox(height: 6),
              Text(
                listing.reviewReason!,
                style: TextStyle(fontSize: 12, color: AppColors.statusDanger),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                // Abgelehnt -> bearbeiten & erneut einreichen (Punkt 6)
                if (listing.reviewStatus == MpReviewStatus.rejected ||
                    listing.reviewStatus == MpReviewStatus.manualReview)
                  _ActionChip(
                    icon: Icons.edit_outlined,
                    label: 'Ändern & erneut einreichen',
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => MarketplaceCreateScreen(editListing: listing),
                      ));
                      onChanged();
                    },
                  ),
                if (listing.status == 'active' && listing.reviewStatus == MpReviewStatus.approved) ...[
                  _ActionChip(
                    icon: Icons.pause_circle_outline,
                    label: 'Pausieren',
                    onTap: () => onStatus('paused', '⏸️ Angebot pausiert'),
                  ),
                  _ActionChip(
                    icon: Icons.check_circle_outline,
                    label: 'Verkauft',
                    onTap: () => onStatus('sold', '🎉 Als verkauft markiert'),
                  ),
                ],
                if (listing.status == 'paused' && listing.reviewStatus == MpReviewStatus.approved)
                  _ActionChip(
                    icon: Icons.play_circle_outline,
                    label: 'Erneut veröffentlichen',
                    onTap: () => onStatus('active', '▶️ Angebot wieder aktiv'),
                  ),
                _ActionChip(
                  icon: Icons.delete_outline,
                  label: 'Löschen',
                  onTap: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
        'active' => 'Aktiv',
        'paused' => 'Pausiert',
        'sold' => 'Verkauft',
        'blocked' => 'Gesperrt (Admin)',
        _ => status,
      };
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionChip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }
}

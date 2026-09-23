import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../marketplace_repository.dart';

/// Angebots-Detail (Anforderung 14/15): Fotos, alle Angaben, Verkäufer
/// kontaktieren (privater Chat), Merken, Melden.
class MarketplaceDetailScreen extends ConsumerStatefulWidget {
  final String listingId;

  const MarketplaceDetailScreen({super.key, required this.listingId});

  @override
  ConsumerState<MarketplaceDetailScreen> createState() => _MarketplaceDetailScreenState();
}

class _MarketplaceDetailScreenState extends ConsumerState<MarketplaceDetailScreen> {
  MpListing? _listing;
  bool _loading = true;
  String? _error;
  bool _isFavorite = false;
  int _photoIndex = 0;
  bool _busy = false;

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
      final listing = await ref.read(marketplaceRepositoryProvider).get(token: token, id: widget.listingId);
      final favorites = await ref.read(marketplaceRepositoryProvider).favorites(token: token);
      if (!mounted) return;
      setState(() {
        _listing = listing;
        _isFavorite = favorites.any((f) => f.id == listing.id);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = '$e'; });
    }
  }

  Future<void> _toggleFavorite() async {
    final token = ref.read(marketplaceTokenProvider);
    if (token == null || _listing == null || _busy) return;
    setState(() => _busy = true);
    final repo = ref.read(marketplaceRepositoryProvider);
    try {
      if (_isFavorite) {
        await repo.removeFavorite(token: token, id: _listing!.id);
      } else {
        await repo.addFavorite(token: token, id: _listing!.id);
      }
      if (!mounted) return;
      setState(() => _isFavorite = !_isFavorite);
    } catch (e) {
      if (mounted) _snack('Fehler: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _contactSeller() async {
    final token = ref.read(marketplaceTokenProvider);
    if (token == null || _listing == null || _busy) return;
    setState(() => _busy = true);
    try {
      final conversationId = await ref.read(marketplaceRepositoryProvider).contactSeller(
            token: token,
            id: _listing!.id,
          );
      if (!mounted) return;
      _snack('💬 Chat geöffnet - Nachricht gesendet');
      // Chat öffnet sich über den Chat-Tab; hier genügt die Bestätigung.
      assert(conversationId.isNotEmpty);
    } catch (e) {
      if (mounted) _snack('Fehler: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _report() async {
    final token = ref.read(marketplaceTokenProvider);
    if (token == null || _listing == null || _busy) return;
    final reason = await _pickReportReason();
    if (reason == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(marketplaceRepositoryProvider).report(token: token, id: _listing!.id, reason: reason);
      if (!mounted) return;
      _snack('🚩 Meldung gespeichert - Admins prüfen das Angebot');
    } catch (e) {
      if (mounted) _snack('Fehler: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _pickReportReason() async {
    const reasons = <(String, String)>[
      ('falsche_kategorie', 'Falsche Kategorie'),
      ('nicht_erlaubter_artikel', 'Nicht erlaubter Artikel'),
      ('betrug', 'Betrug / verdächtig'),
      ('falsche_beschreibung', 'Falsche Beschreibung'),
      ('falsche_bilder', 'Falsche Bilder'),
      ('sonstiges', 'Sonstiger Grund'),
    ];
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Warum meldest du dieses Angebot?', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            ...reasons.map((r) => ListTile(
                  title: Text(r.$2),
                  onTap: () => Navigator.of(context).pop(r.$1),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? AppColors.statusDanger : AppColors.bgSurfaceRaisedDark,
      content: Text(message, style: const TextStyle(color: AppColors.textPrimaryDark)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final listing = _listing;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        actions: [
          IconButton(
            icon: Icon(_isFavorite ? Icons.favorite : Icons.favorite_outline,
                color: _isFavorite ? AppColors.statusDanger : null),
            onPressed: _toggleFavorite,
          ),
          IconButton(
            icon: const Icon(Icons.flag_outlined),
            onPressed: _report,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.statusDanger)))
              : listing == null
                  ? const Center(child: Text('Angebot nicht gefunden'))
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 100),
                      children: [
                        // Fotogalerie
                        if (listing.imageUrls.isNotEmpty) ...[
                          SizedBox(
                            height: 280,
                            child: Stack(children: [
                              PageView.builder(
                                itemCount: listing.imageUrls.length,
                                onPageChanged: (i) => setState(() => _photoIndex = i),
                                itemBuilder: (context, i) => Image.network(
                                  listing.imageUrls[i],
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Center(child: Text('🛠️', style: TextStyle(fontSize: 48))),
                                ),
                              ),
                              Positioned(
                                bottom: 10,
                                right: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${_photoIndex + 1}/${listing.imageUrls.length}',
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                  ),
                                ),
                              ),
                            ]),
                          ),
                        ] else
                          Container(
                            height: 180,
                            color: scheme.surfaceContainerHigh,
                            child: const Center(child: Text('🛠️', style: TextStyle(fontSize: 56))),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                listing.priceLabel,
                                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.accentPrimaryDark),
                              ),
                              const SizedBox(height: 6),
                              Text(listing.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  _MetaChip(label: '${listing.condition.emoji} ${listing.condition.label}'),
                                  _MetaChip(label: '${listing.category.emoji} ${listing.subcategory}'),
                                  if (listing.shipping) const _MetaChip(label: '📦 Versand möglich'),
                                  _MetaChip(label: '📍 ${listing.locationLabel}'),
                                  if (listing.year != null) _MetaChip(label: '🗓️ ${listing.year}'),
                                ],
                              ),
                              const SizedBox(height: 16),
                              if (listing.description.isNotEmpty) ...[
                                const Text('Beschreibung', style: TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                Text(listing.description),
                                const SizedBox(height: 16),
                              ],
                              Text(
                                'Veröffentlicht am ${_fmtDate(listing.createdAt)}',
                                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
      bottomSheet: listing == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: FilledButton.icon(
                  onPressed: _busy ? null : _contactSeller,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentPrimaryDark,
                    foregroundColor: AppColors.textPrimaryDark,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('💬 Verkäufer kontaktieren', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
    );
  }

  String _fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

class _MetaChip extends StatelessWidget {
  final String label;
  const _MetaChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

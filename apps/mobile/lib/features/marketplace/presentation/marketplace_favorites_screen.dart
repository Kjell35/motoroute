import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/network/error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../marketplace_repository.dart';

/// Gemerkte Angebote (Anforderung 18).
class MarketplaceFavoritesScreen extends ConsumerStatefulWidget {
  const MarketplaceFavoritesScreen({super.key});

  @override
  ConsumerState<MarketplaceFavoritesScreen> createState() => _MarketplaceFavoritesScreenState();
}

class _MarketplaceFavoritesScreenState extends ConsumerState<MarketplaceFavoritesScreen> {
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
      final listings = await ref.read(marketplaceRepositoryProvider).favorites(token: token);
      if (!mounted) return;
      setState(() { _listings = listings; _loading = false; _error = null; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = friendlyErrorMessage(e, ref.read(i18nProvider)); });
    }
  }

  Future<void> _remove(String id) async {
    final token = ref.read(marketplaceTokenProvider);
    if (token == null) return;
    await ref.read(marketplaceRepositoryProvider).removeFavorite(token: token, id: id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(title: const Text('❤️ Meine Favoriten'), backgroundColor: scheme.surface),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.statusDanger)))
              : _listings.isEmpty
                  ? const Center(child: Text('Noch keine gemerkten Angebote'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: _listings.length,
                        padding: const EdgeInsets.all(12),
                        itemBuilder: (context, i) {
                          final listing = _listings[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: scheme.surfaceContainerHigh,
                            elevation: 0,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              leading: listing.imageUrls.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        listing.imageUrls.first,
                                        width: 56, height: 56, fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Icon(Icons.image),
                                      ),
                                    )
                                  : const Icon(Icons.image_outlined),
                              title: Text(listing.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text('${listing.condition.emoji} ${listing.condition.label} · 📍 ${listing.locationLabel}'),
                              trailing: Text(
                                listing.priceLabel,
                                style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.accentPrimaryDark),
                              ),
                              onLongPress: () => _remove(listing.id),
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Lang drücken zum Entfernen aus den Favoriten')),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/i18n/i18n.dart';
import 'marketplace_notifications.dart';
import 'marketplace_repository.dart';
import 'presentation/marketplace_create_screen.dart';
import 'presentation/marketplace_detail_screen.dart';
import 'presentation/marketplace_my_listings_screen.dart';
import 'presentation/marketplace_favorites_screen.dart';
import 'presentation/marketplace_admin_screen.dart';
import 'presentation/marketplace_inbox_screen.dart';

/// Marktplatz-Übersicht (Anforderung 11-13): Suche, Kategorien,
/// neue Angebote, Filter. Dark-/Light-fähig über AppColors.
class MarketplaceScreen extends ConsumerStatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  ConsumerState<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MpFilter {
  String? category;
  String? subcategory;
  String? condition;
  bool? shipping;
  int? maxPrice;
  String sort = 'newest';

  bool get isActive =>
      category != null || subcategory != null || condition != null || shipping == true || maxPrice != null;
}

class _MarketplaceScreenState extends ConsumerState<MarketplaceScreen> {
  final _searchController = TextEditingController();
  MpCatalog? _catalog;
  List<MpListing> _listings = const [];
  bool _loading = true;
  String? _error;
  final _filter = _MpFilter();

  // ---- Autocomplete (Suggest + Tippfehler-Toleranz) -----------------------
  final _focusNode = FocusNode();
  List<MpSuggestion> _suggestions = const [];
  Timer? _suggestDebounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) setState(() => _suggestions = const []);
    });
  }

  /// Live-Vorschläge: Server-Präfix-Treffer + FUZZY-Erweiterung gegen den
  /// zuletzt geladenen Katalog (Damerau-Levenshtein <= 2), damit "BMW "
  /// auch bei "BWM" noch "BMW" findet.
  Future<void> _onSearchChanged() async {
    setState(() {}); // Clear-Button sichtbar halten
    final term = _searchController.text.trim();
    _suggestDebounce?.cancel();
    if (term.length < 2) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      return;
    }
    _suggestDebounce = Timer(const Duration(milliseconds: 250), () async {
      final token = ref.read(marketplaceTokenProvider);
      if (token == null) return;
      try {
        final server = await ref
            .read(marketplaceRepositoryProvider)
            .suggest(token: token, q: term);
        var merged = [...server.brands, ...server.models];        // Fuzzy-Erweiterung: schon bekannte Marken/Modelle aus dem Katalog
        // des Screens (aktuelles Listing-Set) per Edit-Distanz ergänzen.
        final known = <String>{
          for (final l in _listings) ...[
            if (l.brand != null && l.brand!.isNotEmpty) l.brand!,
            if (l.model != null && l.model!.isNotEmpty) l.model!,
          ],
        };
        final lower = term.toLowerCase();
        for (final candidate in known) {
          if (merged.any((s) => s.label == candidate)) continue;
          final dist = _damerauLevenshtein(lower, candidate.toLowerCase());
          if (dist <= (lower.length <= 4 ? 1 : 2)) {
            merged = [...merged, MpSuggestion(label: candidate, count: 0)];
          }
        }
        if (!mounted) return;
        setState(() {
          _suggestions = merged.take(8).toList(growable: false);
        });
      } catch (_) {
        // Vorschläge sind Best-Effort - Suchfeld bleibt voll funktionsfähig.
      }
    });
  }

  /// Damerau-Levenshtein-Distanz (inkl. Transpositionen - "BWM" -> "BMW").
  static int _damerauLevenshtein(String a, String b) {
    final la = a.length, lb = b.length;
    final d = List.generate(la + 1, (_) => List<int>.filled(lb + 1, 0));
    for (var i = 0; i <= la; i++) {
      d[i][0] = i;
    }
    for (var j = 0; j <= lb; j++) {
      d[0][j] = j;
    }
    for (var i = 1; i <= la; i++) {
      for (var j = 1; j <= lb; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        d[i][j] = [
          d[i - 1][j] + 1, // löschen
          d[i][j - 1] + 1, // einfügen
          d[i - 1][j - 1] + cost, // ersetzen
        ].reduce((x, y) => x < y ? x : y);
        if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
          d[i][j] = d[i][j] < d[i - 2][j - 2] + 1 ? d[i][j] : d[i - 2][j - 2] + 1;
        }
      }
    }
    return d[la][lb];
  }

  void _applySuggestion(String label) {
    _searchController.text = label;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: label.length),
    );
    setState(() => _suggestions = const []);
    _load();
  }

  Future<void> _load() async {
    final token = ref.read(marketplaceTokenProvider);
    if (token == null) {
      setState(() {
        _loading = false;
        _error = ref.read(i18nProvider).mpNotLoggedIn;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = ref.read(marketplaceRepositoryProvider);
    try {
      final catalog = _catalog ?? await repo.catalog(token: token);
      final listings = await repo.list(
        token: token,
        q: _searchController.text.trim(),
        category: _filter.category,
        subcategory: _filter.subcategory,
        condition: _filter.condition,
        shipping: _filter.shipping,
        maxPrice: _filter.maxPrice,
        sort: _filter.sort,
      );
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _listings = listings;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '${ref.read(i18nProvider).mpLoadFailed}: $e';
      });
    }
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = ref.watch(i18nProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        title: Text('🛒 ${i18n.mpTitle}', style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          // Inbox-Badge: ungelesene Aktivität an eigenen Angeboten.
          IconButton(
            tooltip: 'Aktivität',
            icon: Badge(
              isLabelVisible: ref.watch(unreadCountProvider) > 0,
              label: Text('${ref.watch(unreadCountProvider)}'),
              backgroundColor: AppColors.statusDanger,
              child: const Icon(Icons.notifications_outlined),
            ),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MarketplaceInboxScreen()),
              );
            },
          ),
          IconButton(
            tooltip: i18n.mpFavorites,
            icon: const Icon(Icons.favorite_outline),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MarketplaceFavoritesScreen()),
              );
            },
          ),
          IconButton(
            tooltip: i18n.mpMyListings,
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MarketplaceMyListingsScreen()),
              );
              _load();
            },
          ),
          IconButton(
            tooltip: i18n.mpAdmin,
            icon: const Icon(Icons.admin_panel_settings_outlined),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MarketplaceAdminScreen()),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.accentPrimaryDark,
        foregroundColor: AppColors.textPrimaryDark,
        icon: const Icon(Icons.add),
        label: Text(i18n.mpCreateListing),
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const MarketplaceCreateScreen()),
          );
          if (created == true) _load();
        },
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Suche mit Autocomplete (Suggest + Tippfehler-Toleranz)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _searchController,
                      focusNode: _focusNode,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) {
                        setState(() => _suggestions = const []);
                        _load();
                      },
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: '${i18n.mpSearchHint} (BMW GS Auspuff)',
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _suggestions = const []);
                                  _load();
                                },
                              ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        isDense: true,
                      ),
                    ),
                    if (_suggestions.isNotEmpty && _focusNode.hasFocus)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Column(
                          children: _suggestions.map((s) {
                            final isBrand = s.count > 0;
                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _applySuggestion(s.label),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                child: Row(
                                  children: [
                                    Icon(
                                      isBrand ? Icons.directions_car_outlined : Icons.settings_outlined,
                                      size: 18,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text(s.label, style: const TextStyle(fontSize: 15))),
                                    if (isBrand)
                                      Text(
                                        '${s.count} Treffer',
                                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Hauptkategorien
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: MpCategory.values.map((c) {
                    final selected = _filter.category == c.name;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(c.emoji, textAlign: TextAlign.center),
                          selected: selected,
                          tooltip: c.label,
                          selectedColor: AppColors.accentPrimaryDark,
                          labelStyle: TextStyle(
                            color: selected ? AppColors.textPrimaryDark : scheme.onSurface,
                          ),
                          backgroundColor: scheme.surfaceContainerHighest,
                          onSelected: (sel) {
                            setState(() {
                              _filter.category = sel ? c.name : null;
                              _filter.subcategory = null;
                            });
                            _load();
                          },
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            // Aktive Filter
            if (_filter.isActive)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _FilterChip(
                        label: '${i18n.mpFilterCondition}: ${_filter.condition ?? ''}',
                        visible: _filter.condition != null,
                        onRemove: () {
                          setState(() => _filter.condition = null);
                          _load();
                        },
                      ),
                      _FilterChip(
                        label: '${i18n.mpMaxPrice}: ${(_filter.maxPrice ?? 0) / 100} €',
                        visible: _filter.maxPrice != null,
                        onRemove: () {
                          setState(() => _filter.maxPrice = null);
                          _load();
                        },
                      ),
                      _FilterChip(
                        label: i18n.mpShipping,
                        visible: _filter.shipping == true,
                        onRemove: () {
                          setState(() => _filter.shipping = null);
                          _load();
                        },
                      ),
                      _FilterChip(
                        label: i18n.mpFiltersReset,
                        visible: true,
                        onRemove: () {
                          setState(() {
                            _filter
                              ..category = null
                              ..subcategory = null
                              ..condition = null
                              ..shipping = null
                              ..maxPrice = null
                              ..sort = 'newest';
                          });
                          _load();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            // Filter-Zeile
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.filter_list),
                      label: Text(i18n.mpFilters),
                      onPressed: () => _openFilterSheet(context, i18n),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.swap_vert),
                      label: Text(_filter.sort == 'price_asc'
                          ? i18n.mpSortPriceAsc
                          : _filter.sort == 'price_desc'
                              ? i18n.mpSortPriceDesc
                              : i18n.mpSortNewest),
                      onPressed: () {
                        setState(() {
                          _filter.sort = _filter.sort == 'newest'
                              ? 'price_asc'
                              : _filter.sort == 'price_asc'
                                  ? 'price_desc'
                                  : 'newest';
                        });
                        _load();
                      },
                    ),
                  ],
                ),
              ),
            ),
            // Inhalt
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.statusDanger)),
                  ),
                ),
              )
            else if (_listings.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(i18n.mpEmpty, style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                sliver: SliverList.separated(
                  itemCount: _listings.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _ListingCard(
                    listing: _listings[index],
                    onOpen: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MarketplaceDetailScreen(listingId: _listings[index].id),
                        ),
                      );
                      _load();
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openFilterSheet(BuildContext context, I18n i18n) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        var condition = _filter.condition;
        var shipping = _filter.shipping == true;
        var maxPriceController = TextEditingController(
          text: _filter.maxPrice != null ? (_filter.maxPrice! / 100).toStringAsFixed(0) : '',
        );
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final subcategories = _catalog?.categories
                    .where((c) => c.key == _filter.category)
                    .expand((c) => c.subcategories)
                    .toList(growable: false) ??
                const <MpSubcategoryDef>[];
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(i18n.mpFilters, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  // Unterkategorie
                  if (subcategories.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: _filter.subcategory,
                      decoration: InputDecoration(labelText: i18n.mpSubcategory, border: const OutlineInputBorder(), isDense: true),
                      items: subcategories
                          .map((s) => DropdownMenuItem(value: s.key, child: Text(s.labelDe)))
                          .toList(),
                      onChanged: (v) => setSheetState(() => _filter.subcategory = v),
                    ),
                  const SizedBox(height: 12),
                  // Zustand
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: MpCondition.values.map((c) {
                      return ChoiceChip(
                        label: Text('${c.emoji} ${c.label}'),
                        selected: condition == c.apiValue,
                        selectedColor: AppColors.accentPrimaryDark,
                        onSelected: (sel) =>
                            setSheetState(() => condition = sel ? c.apiValue : null),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(i18n.mpShipping),
                    value: shipping,
                    onChanged: (v) => setSheetState(() => shipping = v),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: maxPriceController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: i18n.mpMaxPrice,
                      suffixText: '€',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      final parsed = int.tryParse(maxPriceController.text.trim());
                      setState(() {
                        _filter.condition = condition;
                        _filter.shipping = shipping ? true : null;
                        _filter.maxPrice = parsed != null ? parsed * 100 : null;
                      });
                      Navigator.of(sheetContext).pop();
                      _load();
                    },
                    child: Text(i18n.mpFiltersApply),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool visible;
  final VoidCallback onRemove;

  const _FilterChip({required this.label, required this.visible, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return InputChip(
      label: Text(label),
      onDeleted: onRemove,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ListingCard extends StatelessWidget {
  final MpListing listing;
  final VoidCallback onOpen;

  const _ListingCard({required this.listing, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final image = listing.imageUrls.isNotEmpty ? listing.imageUrls.first : null;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Foto oder Platzhalter
            SizedBox(
              width: 96,
              child: image != null
                  ? Image.network(
                      image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(child: Text('🛠️', style: TextStyle(fontSize: 32))),
                    )
                  : Center(
                      child: Text(
                        switch (listing.category) {
                          MpCategory.motorradteile => '🏍️',
                          MpCategory.autoteile => '🚗',
                          MpCategory.fahrradteile => '🚲',
                        },
                        style: const TextStyle(fontSize: 32),
                      ),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${listing.brand ?? ''} ${listing.model ?? ''}'.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Text(
                          listing.priceLabel,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: AppColors.accentPrimaryDark,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${listing.condition.emoji} ${listing.condition.label}',
                            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                        const Spacer(),
                        if (listing.shipping)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Text('📦', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                          ),
                        Text('📍 ${listing.locationLabel}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

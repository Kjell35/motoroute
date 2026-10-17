import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/network/error_message.dart';
import '../../../core/network/error_reporter.dart';
import '../../../core/theme/app_colors.dart';
import '../marketplace_repository.dart';
import '../marketplace_taxonomy.dart';

/// Angebot erstellen (Anforderung 4 + 16): geführter Dialog mit
/// Kategorien, Fotos, Infos, Preis - und dem Ergebnis der SERVERSEITIGEN
/// KI-Prüfung. Ohne eindeutige Freigabe erscheint nichts öffentlich;
/// abgelehnte Angebote können korrigiert und erneut eingereicht werden.
class MarketplaceCreateScreen extends ConsumerStatefulWidget {
  final MpListing? editListing; // gesetzt = erneut einreichen (Punkt 6)

  const MarketplaceCreateScreen({super.key, this.editListing});

  @override
  ConsumerState<MarketplaceCreateScreen> createState() => _MarketplaceCreateScreenState();
}

class _MarketplaceCreateScreenState extends ConsumerState<MarketplaceCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _year = TextEditingController();
  final _location = TextEditingController();

  MpCategory? _category = MpCategory.motorradteile;
  String? _subcategory;
  MpCondition _condition = MpCondition.gut;
  bool _shipping = false;
  final List<XFile> _photos = [];
  bool _submitting = false;
  MpListing? _result;

  MpCatalog? _catalog;

  @override
  void initState() {
    super.initState();
    // Auto-Vorschlag live: Sobald Titel/Beschreibung eine Unterkategorie
    // nennen, hebt die Gruppierungs-UI den Treffer umrandet hervor.
    _title.addListener(_onTextChanged);
    _description.addListener(_onTextChanged);
    final edit = widget.editListing;
    if (edit != null) {
      _title.text = edit.title;
      _description.text = edit.description;
      _price.text = (edit.priceCents / 100).toStringAsFixed(0);
      _brand.text = edit.brand ?? '';
      _model.text = edit.model ?? '';
      _year.text = edit.year?.toString() ?? '';
      _location.text = edit.locationLabel;
      _category = edit.category;
      _subcategory = edit.subcategory;
      _condition = edit.condition;
      _shipping = edit.shipping;
    }
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final token = ref.read(marketplaceTokenProvider);
    if (token == null) return;
    try {
      final catalog = await ref.read(marketplaceRepositoryProvider).catalog(token: token);
      if (!mounted) return;
      setState(() => _catalog = catalog);
    } catch (_) {
      // Katalog-Fehlschlag: UI arbeitet mit dem lokalen Enum weiter.
    }
  }

  @override
  void dispose() {
    _title.removeListener(_onTextChanged);
    _description.removeListener(_onTextChanged);
    _title.dispose();
    _description.dispose();
    _price.dispose();
    _brand.dispose();
    _model.dispose();
    _year.dispose();
    _location.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _pickPhotos() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 80, limit: 8 - _photos.length);
    if (picked.isNotEmpty) {
      setState(() => _photos.addAll(picked.take(8 - _photos.length)));
    }
  }

  List<MpSubcategoryDef> get _subcategories {
    final key = _category?.name;
    if (key == null) return const [];
    // Bevorzugt den Server-Katalog; Fallback: lokaler Spiegel (UI bleibt
    // auch ohne Server-Antwort bedienbar - Validierung bleibt serverseitig).
    final fromServer = _catalog?.categories.where((c) => c.key == key).expand((c) => c.subcategories).toList();
    if (fromServer != null && fromServer.isNotEmpty) return fromServer;
    return fallbackCatalog.where((c) => c.key == key).expand((c) => c.subcategories).toList();
  }

  /// Thematische Gruppierung der Unterkategorien: Statt ~30 Chips in einem
  /// flachen Wrap bekommt der Nutzer kompakte Abschnitte (Motor & Abgas,
  /// Bremsen, Elektrik ...). Nur das UI-Layering gruppier - die Keys bleiben
  /// exakt die Server-Taxonomie.
  List<_SubcatGroup> get _groupedSubcategories {
    final subs = _subcategories;
    if (subs.isEmpty) return const [];
    final bicycle = _category == MpCategory.fahrradteile;
    final groupKeys = bicycle ? _bicycleGroupKeys : _vehicleGroupKeys;
    final byKey = {for (final s in subs) s.key: s};
    final groups = <_SubcatGroup>[];
    final assigned = <String>{};
    for (final entry in groupKeys.entries) {
      final items = entry.value.map((k) => byKey[k]).whereType<MpSubcategoryDef>().toList();
      if (items.isEmpty) continue;
      groups.add(_SubcatGroup(entry.key, items));
      assigned.addAll(items.map((s) => s.key));
    }
    // Defensiv: Kategorien vom Server, die in keiner Gruppe landen, zeigen
    // wir unter "Weitere" - nichts geht verloren.
    final rest = subs.where((s) => !assigned.contains(s.key)).toList();
    if (rest.isNotEmpty) groups.add(_SubcatGroup('Weitere', rest));
    return groups;
  }

  /// Automatischer Vorschlag: laengstes passendes Unterkategorie-Label im
  /// Titel/Beschreibung ("Auspuffanlage" -> Auspuff). Nur UI-Hinweis,
  /// der Nutzer waehlt weiterhin selbst.
  String? get _suggestedSubcategory {
    final text = '${_title.text} ${_description.text}'.toLowerCase().trim();
    if (text.length < 4) return null;
    final candidates = _subcategories
        .where((s) => s.labelDe.toLowerCase().length >= 4 && text.contains(s.labelDe.toLowerCase()))
        .toList()
      ..sort((a, b) => b.labelDe.length.compareTo(a.labelDe.length));
    return candidates.isEmpty ? null : candidates.first.key;
  }

  Future<void> _submit() async {
    final i18n = ref.read(i18nProvider);
    if (!_formKey.currentState!.validate()) return;
    if (_category == null || _subcategory == null) {
      _showSnack(i18n.mpCategoryRequired, error: true);
      return;
    }
    final token = ref.read(marketplaceTokenProvider);
    if (token == null) {
      _showSnack(i18n.mpNotLoggedIn, error: true);
      return;
    }

    setState(() => _submitting = true);
    final repo = ref.read(marketplaceRepositoryProvider);
    try {
      final priceCents = ((double.tryParse(_price.text.trim().replaceAll(',', '.')) ?? -1) * 100).round();
      final fields = <String, dynamic>{
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'priceCents': priceCents,
        'condition': _condition.apiValue,
        'category': _category!.name,
        'subcategory': _subcategory,
        'locationLabel': _location.text.trim(),
        'shipping': _shipping,
        if (_brand.text.trim().isNotEmpty) 'brand': _brand.text.trim(),
        if (_model.text.trim().isNotEmpty) 'model': _model.text.trim(),
        if (_year.text.trim().isNotEmpty) 'year': int.tryParse(_year.text.trim()),
      };

      final MpListing listing;
      if (widget.editListing != null) {
        listing = await repo.resubmit(
          token: token,
          id: widget.editListing!.id,
          fields: fields,
          imagePaths: _photos.map((p) => p.path).toList(),
        );
      } else {
        listing = await repo.create(
          token: token,
          fields: fields,
          imagePaths: _photos.map((p) => p.path).toList(),
        );
      }

      if (!mounted) return;
      setState(() {
        _result = listing;
        _submitting = false;
      });
    } catch (e) {
      ErrorReporter.instance.report('mp.create', e);
      if (!mounted) return;
      setState(() => _submitting = false);
      _showSnack('${i18n.mpSubmitFailed}: ${friendlyErrorMessage(e, i18n)}', error: true);
    }
  }

  void _showSnack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? AppColors.statusDanger : AppColors.bgSurfaceRaisedDark,
      content: Text(message, style: const TextStyle(color: AppColors.textPrimaryDark)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final i18n = ref.watch(i18nProvider);
    final scheme = Theme.of(context).colorScheme;

    // KI-Ergebnis-Screen (Punkt 5/6/9): nach dem Absenden zeigen wir die
    // serverseitige Entscheidung statt automatisch zurückzunavigieren.
    if (_result != null) {
      return _ReviewResultView(
        listing: _result!,
        onClose: () => Navigator.of(context).pop(_result!.reviewStatus.isPubliclyVisible),
      );
    }

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        title: Text(widget.editListing != null ? i18n.mpResubmitTitle : i18n.mpCreateListing),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // 1) Hauptkategorie
            Text(i18n.mpStepCategory, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              children: MpCategory.values
                  .map((c) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text('${c.emoji} ${_categoryLabel(c, i18n)}',
                                textAlign: TextAlign.center),
                            selected: _category == c,
                            selectedColor: AppColors.accentPrimaryDark,
                            labelStyle: TextStyle(
                              fontSize: 12,
                              color: _category == c ? AppColors.textPrimaryDark : scheme.onSurface,
                            ),
                            backgroundColor: scheme.surfaceContainerHighest,
                            onSelected: (sel) => setState(() {
                              _category = sel ? c : null;
                              _subcategory = null;
                            }),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),

            // 2) Unterkategorie - thematisch gruppiert statt ~30 flachen
            // Chips; automatisch vorgeschlagene Treffer sind umrandet.
            Text(i18n.mpStepSubcategory, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ..._buildGroupedSubcategoryTiles(scheme),
            const SizedBox(height: 16),

            // 3) Fotos
            Text(i18n.mpStepPhotos, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SizedBox(
              height: 92,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  if (_photos.length < 8)
                    GestureDetector(
                      onTap: _pickPhotos,
                      child: Container(
                        width: 92,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: const Center(child: Icon(Icons.add_a_photo_outlined)),
                      ),
                    ),
                  ..._photos.map((p) => Stack(children: [
                        Container(
                          width: 92,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                          clipBehavior: Clip.antiAlias,
                          // LOKALE Datei (ImagePicker) -> Image.file. Image.
                          // network kann mit einem Gerätepfaad niemals laden
                          // (früher: Vorschau zeigte immer nur den Platzhalter).
                          child: Image.file(
                            File(p.path),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.image)),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 8,
                          child: GestureDetector(
                            onTap: () => setState(() => _photos.remove(p)),
                            child: const CircleAvatar(
                              radius: 11,
                              backgroundColor: AppColors.statusDanger,
                              child: Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ])),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 4) Artikelinformationen
            Text(i18n.mpStepDetails, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _title,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: '${i18n.mpTitleField} *',
                hintText: 'BMW R1250 Auspuff',
                border: const OutlineInputBorder(),
                counterText: '',
              ),
              validator: (v) => (v == null || v.trim().length < 3) ? i18n.mpTitleShort : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _description,
              maxLines: 4,
              maxLength: 4000,
              decoration: InputDecoration(
                labelText: i18n.mpDescription,
                border: const OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _brand,
                  decoration: InputDecoration(labelText: i18n.mpBrand, border: const OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _model,
                  decoration: InputDecoration(labelText: i18n.mpModel, border: const OutlineInputBorder()),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _year,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: '${i18n.mpYear} (${i18n.mpOptional})', border: const OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _location,
                  decoration: InputDecoration(
                    labelText: '${i18n.mpLocation} *',
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? i18n.mpLocationRequired : null,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            // Zustand
            Text(i18n.mpCondition, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: MpCondition.values
                  .map((c) => ChoiceChip(
                        label: Text('${c.emoji} ${c.label}'),
                        selected: _condition == c,
                        selectedColor: AppColors.accentPrimaryDark,
                        onSelected: (sel) => setState(() => _condition = c),
                      ))
                  .toList(),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(i18n.mpShipping),
              subtitle: Text(i18n.mpShippingHint),
              value: _shipping,
              onChanged: (v) => setState(() => _shipping = v),
            ),
            const SizedBox(height: 16),

            // 5) Preis
            Text(i18n.mpStepPrice, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: '${i18n.mpPrice} *',
                suffixText: '€',
                border: const OutlineInputBorder(),
              ),
              validator: (v) {
                final parsed = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                if (parsed == null || parsed < 0) return i18n.mpPriceInvalid;
                return null;
              },
            ),
            const SizedBox(height: 20),

            // 7) KI-Prüfung-Hinweis
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                Icon(Icons.fact_check_outlined, size: 22, color: scheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(child: Text(i18n.mpAiCheckNote, style: const TextStyle(fontSize: 12))),
              ]),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentPrimaryDark,
                foregroundColor: AppColors.textPrimaryDark,
                minimumSize: const Size.fromHeight(52),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimaryDark))
                  : Text(i18n.mpSubmitForReview, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  String _categoryLabel(MpCategory c, I18n i18n) =>
      switch (c) { MpCategory.motorradteile => 'Motorrad', MpCategory.autoteile => 'Auto', MpCategory.fahrradteile => 'Fahrrad' };

  // -- Unterkategorien: gruppierte Abschnitte -------------------------------

  /// Baut die gruppierten Abschnitte. Immer maximal 3 sichtbare Chips pro
  /// Gruppe, Rest hinter "mehr ..." - alles bleibt wahlbar.
  List<Widget> _buildGroupedSubcategoryTiles(ColorScheme scheme) {
    final groups = _groupedSubcategories;
    if (groups.isEmpty) return [Text('–', style: TextStyle(color: scheme.onSurfaceVariant))];
    return [
      for (final g in groups) _SubcatGroupTile(
          group: g,
          scheme: scheme,
          selectedKey: _subcategory,
          suggestedKey: _suggestedSubcategory,
          onSelect: (key) => setState(() => _subcategory = key),
        ),
    ];
  }
}

/// Eine thematische Gruppe von Unterkategorien (z. B. "Bremsen").
class _SubcatGroup {
  final String title;
  final List<MpSubcategoryDef> items;
  const _SubcatGroup(this.title, this.items);
}

/// Zeigt eine Gruppe als kompakte Karte: Titel + bis zu 3 Chips, Rest
/// aufklappbar. Auto-Vorschlag bekommt einen Akzent-Rand.
class _SubcatGroupTile extends StatefulWidget {
  final _SubcatGroup group;
  final ColorScheme scheme;
  final String? selectedKey;
  final String? suggestedKey;
  final ValueChanged<String?> onSelect;

  const _SubcatGroupTile({
    required this.group,
    required this.scheme,
    required this.selectedKey,
    required this.suggestedKey,
    required this.onSelect,
  });

  @override
  State<_SubcatGroupTile> createState() => _SubcatGroupTileState();
}

class _SubcatGroupTileState extends State<_SubcatGroupTile> {
  static const _visibleWithoutExpansion = 3;
  bool _userToggled = false;

  // Auswahl in einer zugeklappten Gruppe: Gruppe startet offen, damit die
  // Auswahl sichtbar bleibt (wird ueberschrieben, sobald der Nutzer klickt).
  bool get _expanded {
    if (_userToggled) return _userExpanded;
    return widget.group.items.any((s) => s.key == widget.selectedKey);
  }

  bool _userExpanded = false;

  bool get _needsExpansion => widget.group.items.length > _visibleWithoutExpansion;

  List<MpSubcategoryDef> get _visible => !_needsExpansion || _expanded
      ? widget.group.items
      : widget.group.items.take(_visibleWithoutExpansion).toList();

  @override
  Widget build(BuildContext context) {
    final scheme = widget.scheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(widget.group.title,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              if (_needsExpansion)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() {
                    _userExpanded = !_expanded;
                    _userToggled = true;
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_expanded ? 'weniger' : 'mehr',
                          style: TextStyle(fontSize: 12, color: scheme.primary)),
                      Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                          size: 16, color: scheme.primary),
                    ]),
                  ),
                ),
            ]),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _visible.map((s) {
                final selected = widget.selectedKey == s.key;
                final suggested = !selected && widget.suggestedKey == s.key;
                return ChoiceChip(
                  label: Text(s.labelDe, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  selectedColor: AppColors.accentPrimaryDark,
                  labelStyle: TextStyle(color: selected ? AppColors.textPrimaryDark : scheme.onSurface),
                  backgroundColor: scheme.surfaceContainerHighest,
                  side: suggested
                      ? BorderSide(color: scheme.primary, width: 1.4)
                      : BorderSide(color: scheme.outlineVariant),
                  onSelected: (sel) => widget.onSelect(sel ? s.key : null),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}


/// Gruppierung Motorrad/Auto: Keys der Server-Taxonomie.
const Map<String, List<String>> _vehicleGroupKeys = {
  'Motor & Abgas': ['motor', 'motorenteile', 'zylinder', 'kolben', 'kupplung', 'auspuff', 'kruemmer', 'schalldaempfer'],
  'Fahrwerk & Bremsen': ['fahrwerk', 'stossdaempfer', 'gabel', 'bremsen', 'bremsscheiben', 'bremsbelaege', 'bremssaettel', 'bremsleitungen'],
  'Elektrik & Elektronik': ['elektrik', 'batterie', 'licht', 'steuergeraete', 'kabel', 'elektronik'],
  'Räder & Reifen': ['raeder', 'felgen', 'reifen', 'radteile'],
  'Karosserie & Verkleidung': ['verkleidung', 'kotfluegel', 'karosserieteile', 'karosserie', 'tueren', 'seitenteile', 'innenraum'],
  'Zubehör & Gepäck': ['zubehoer', 'gepaeck', 'halterungen', 'schutzteile'],
  'Sonstiges': ['sonstiges'],
};

/// Gruppierung Fahrrad.
const Map<String, List<String>> _bicycleGroupKeys = {
  'Antrieb & Schaltung': ['antrieb', 'schaltung', 'pedale', 'ebike_motor', 'akku'],
  'Bremsen': ['bremsen', 'bremsscheiben', 'bremsbelaege'],
  'Räder & Reifen': ['raeder', 'felgen', 'reifen'],
  'Rahmen & Gabel': ['rahmen', 'gabel', 'federung', 'lenker', 'sattel'],
  'Licht & Elektrik': ['beleuchtung'],
  'Zubehör & Gepäck': ['zubehoer', 'gepaeck'],
  'Sonstiges': ['sonstiges'],
};

/// Zeigt die SERVERSEITIGE KI-Entscheidung (approved / rejected /
/// manual_review) mit Grund (Punkt 5/6/9) an.
class _ReviewResultView extends StatelessWidget {
  final MpListing listing;
  final VoidCallback onClose;

  const _ReviewResultView({required this.listing, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, iconColor, title, color) = switch (listing.reviewStatus) {
      MpReviewStatus.approved => (Icons.check_circle_outline, null, 'Veröffentlicht!', AppColors.statusSuccess),
      MpReviewStatus.rejected => (Icons.block_outlined, null, 'Nicht veröffentlicht', AppColors.statusDanger),
      MpReviewStatus.manualReview => (Icons.pending_outlined, null, 'Manuelle Prüfung', AppColors.accentPrimaryDark),
      MpReviewStatus.pending => (Icons.hourglass_top_outlined, null, 'Prüfung läuft', AppColors.accentPrimaryDark),
    };

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(title: const Text('KI-Prüfung'), backgroundColor: scheme.surface),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 64, color: color),
              const SizedBox(height: 16),
              Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  listing.reviewReason ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onClose,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentPrimaryDark,
                  foregroundColor: AppColors.textPrimaryDark,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

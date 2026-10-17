import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import 'garage_repository.dart';

/// Fahrzeug-Detail: technische Daten (Katalog), Erinnerungs-Ampel,
/// Wartungshistorie mit Anlegen, Tankbuch mit Verbrauch, Reifen, Dokumente
/// und Kilometerstand-Update. Alle Daten echt aus der Garage-API.
class GarageVehicleScreen extends ConsumerStatefulWidget {
  const GarageVehicleScreen({super.key, required this.vehicleId});

  final String vehicleId;

  @override
  ConsumerState<GarageVehicleScreen> createState() => _GarageVehicleScreenState();
}

class _GarageVehicleScreenState extends ConsumerState<GarageVehicleScreen> {
  Map<String, dynamic>? _specs;
  List<GarageReminder>? _reminders;
  List<GarageMaintenanceRecord>? _maintenance;
  List<GarageFuelEntry>? _fuel;
  GarageFuelStats? _fuelStats;
  List<GarageTireSet>? _tires;
  List<GarageDocument>? _documents;
  GarageCosts? _costs;
  GarageVehicle? _vehicle;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = ref.read(garageSessionProvider).value;
      final baseUrl = await ref.read(garageBaseUrlProvider.future);
      final repo = ref.read(garageRepositoryProvider);
      if (session == null) throw GarageApiException('no-session');
      final token = session.token;
      final id = widget.vehicleId;
      final results = await Future.wait([
        repo.vehicle(baseUrl, token, id),
        repo.specifications(baseUrl, token, id),
        repo.reminders(baseUrl, token, id),
        repo.maintenance(baseUrl, token, id),
        repo.fuel(baseUrl, token, id),
        repo.fuelStats(baseUrl, token, id),
        repo.tires(baseUrl, token, id),
        repo.documents(baseUrl, token, id),
        repo.costs(baseUrl, token, id),
      ]);
      if (!mounted) return;
      setState(() {
        _vehicle = results[0] as GarageVehicle;
        _specs = results[1] as Map<String, dynamic>;
        _reminders = results[2] as List<GarageReminder>;
        _maintenance = results[3] as List<GarageMaintenanceRecord>;
        _fuel = results[4] as List<GarageFuelEntry>;
        _fuelStats = results[5] as GarageFuelStats;
        _tires = results[6] as List<GarageTireSet>;
        _documents = results[7] as List<GarageDocument>;
        _costs = results[8] as GarageCosts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().split('\n').first;
        _loading = false;
      });
    }
  }

  Future<Map<String, String?>> _callCtx() async {
    final session = ref.read(garageSessionProvider).value;
    final baseUrl = await ref.read(garageBaseUrlProvider.future);
    return {'token': session?.token, 'baseUrl': baseUrl};
  }

  @override
  Widget build(BuildContext context) {
    final i18n = ref.watch(i18nProvider);
    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBaseDark,
        elevation: 0,
        title: Text(_vehicle?.title ?? i18n.gVehicle, style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textSecondaryDark),
            onPressed: _reload,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ListView(padding: const EdgeInsets.all(24), children: [
                  const SizedBox(height: 60),
                  const Icon(Icons.cloud_off, color: AppColors.textMutedDark, size: 44),
                  const SizedBox(height: 12),
                  Center(child: Text(_error!, style: const TextStyle(color: AppColors.textSecondaryDark))),
                ])
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildStatusCard(i18n),
                      const SizedBox(height: 14),
                      _buildReminders(i18n),
                      const SizedBox(height: 14),
                      _buildSpecs(i18n),
                      const SizedBox(height: 14),
                      _buildMaintenance(i18n),
                      const SizedBox(height: 14),
                      _buildFuel(i18n),
                      const SizedBox(height: 14),
                      _buildTires(i18n),
                      const SizedBox(height: 14),
                      _buildDocuments(i18n),
                      const SizedBox(height: 14),
                      _buildCosts(i18n),
                    ],
                  ),
                ),
    );
  }

  // -- Kopf: Fahrzeug + Kilometerstand --------------------------------------

  Widget _buildStatusCard(I18n i18n) {
    final v = _vehicle!;
    return Card(
      color: AppColors.bgSurfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(v.category.emoji, style: const TextStyle(fontSize: 30)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(v.title,
                    style: const TextStyle(color: AppColors.textPrimaryDark, fontSize: 18, fontWeight: FontWeight.w700)),
                if (v.subtitle.isNotEmpty)
                  Text(v.subtitle, style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 13)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: Text('${_fmtKm(v.odometerKm)} km',
                  style: const TextStyle(color: AppColors.textPrimaryDark, fontSize: 22, fontWeight: FontWeight.w700)),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: AppColors.accentPrimaryDark),
              onPressed: _editOdometer,
              icon: const Icon(Icons.edit, size: 18),
              label: Text(i18n.gUpdateKm),
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _editOdometer() async {
    final i18n = ref.read(i18nProvider);
    final ctrl = TextEditingController(text: '${_vehicle!.odometerKm}');
    final newKm = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSurfaceDark,
        title: Text(i18n.gUpdateKm, style: const TextStyle(color: AppColors.textPrimaryDark)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: i18n.gOdometer, filled: true, fillColor: AppColors.bgSurfaceRaisedDark),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(i18n.gCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accentPrimaryDark),
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
            child: Text(i18n.gSave),
          ),
        ],
      ),
    );
    if (newKm == null || newKm == _vehicle!.odometerKm) return;
    final ctx = await _callCtx();
    await ref.read(garageRepositoryProvider).updateOdometer(ctx['baseUrl']!, ctx['token']!, widget.vehicleId, newKm);
    await _reload();
  }

  // -- Erinnerungen -----------------------------------------------------------

  Widget _buildReminders(I18n i18n) {
    final rems = _reminders ?? const <GarageReminder>[];
    if (rems.isEmpty) {
      return _section(i18n.gReminders, [Text(i18n.gNothingDue, style: const TextStyle(color: AppColors.textSecondaryDark))]);
    }
    return _section(
      i18n.gReminders,
      rems.map((r) {
        final color = switch (r.level) {
          GarageReminderStatus.overdue => AppColors.statusDanger,
          GarageReminderStatus.dueSoon => AppColors.statusWarning,
          GarageReminderStatus.ok => AppColors.statusSuccess,
        };
        final rest = <String>[
          if (r.kmRemaining != null) '${_fmtKm(r.kmRemaining!)} km',
          if (r.daysRemaining != null) '${r.daysRemaining} ${i18n.gDays}',
        ].join(' / ');
        return Row(children: [
          Icon(Icons.circle, size: 11, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(r.labelDe, style: const TextStyle(color: AppColors.textPrimaryDark, fontSize: 14))),
          Text(
            r.level == GarageReminderStatus.overdue
                ? i18n.gStatusOverdue
                : rest.isEmpty
                    ? ''
                    : '${i18n.gIn} $rest',
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ]);
      }).toList(),
    );
  }

  // -- Technische Daten --------------------------------------------------------

  Widget _buildSpecs(I18n i18n) {
    final specs = _specs;
    if (specs == null || specs.isEmpty) return const SizedBox.shrink();
    // Katalog-Specs: key/value-Paare sauber formatieren.
    final entries = <Widget>[];
    void addSpec(String label, String? value) {
      if (value == null || value.isEmpty || value == 'null') return;
      entries.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: AppColors.textPrimaryDark, fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ));
    }

    final specList = specs['specs'];
    if (specList is List) {
      for (final s in specList.whereType<Map>()) {
        addSpec((s['key'] ?? '') as String, '${s['value'] ?? ''}${s['unit'] != null ? ' ${s['unit']}' : ''}');
      }
    }
    // Elektro-Felder (falls als plain map geliefert).
    for (final e in specs.entries) {
      if (e.key == 'specs' || e.key == 'vehicleId' || e.key == 'source' || e.key == 'variant') continue;
      if (e.value != null) addSpec(e.key, '${e.value}');
    }

    return _section(i18n.gSpecs, entries.isEmpty
        ? [Text(i18n.gNoSpecs, style: const TextStyle(color: AppColors.textSecondaryDark))]
        : entries);
  }

  // -- Wartung ------------------------------------------------------------------

  Widget _buildMaintenance(I18n i18n) {
    final recs = _maintenance ?? const <GarageMaintenanceRecord>[];
    return _sectionWithAction(
      i18n.gMaintenance,
      IconButton(
        icon: const Icon(Icons.add_circle_outline, color: AppColors.accentPrimaryDark),
        onPressed: _addMaintenance,
      ),
      recs.isEmpty
          ? [Text(i18n.gNoMaintenance, style: const TextStyle(color: AppColors.textSecondaryDark))]
          : recs.map((m) {
              final date = m.performedAt;
              final dateStr = date != null ? '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}' : '';
              return Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.labelDe, style: const TextStyle(color: AppColors.textPrimaryDark, fontSize: 14, fontWeight: FontWeight.w600)),
                    Text(
                      [dateStr, '${_fmtKm(m.odometerKm)} km', if (m.shopName != null) m.shopName!].join(' · '),
                      style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 12),
                    ),
                  ]),
                ),
                if (m.costCents != null)
                  Text(_fmtEuro(m.costCents!), style: const TextStyle(color: AppColors.textPrimaryDark, fontSize: 14, fontWeight: FontWeight.w600)),
              ]);
            }).toList(),
    );
  }

  Future<void> _addMaintenance() async {
    final i18n = ref.read(i18nProvider);
    const types = ['OIL_CHANGE', 'OIL_FILTER', 'AIR_FILTER', 'BRAKE_PADS', 'BRAKE_DISCS', 'TIRES', 'BATTERY', 'COOLANT', 'BRAKE_FLUID', 'SPARK_PLUGS', 'CHAIN', 'CHAIN_OIL', 'TIMING_BELT', 'INSPECTION', 'HU', 'AU', 'OTHER'];
    var type = types.first;
    final dateCtrl = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));
    final kmCtrl = TextEditingController(text: '${_vehicle!.odometerKm}');
    final costCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: AppColors.bgSurfaceDark,
          title: Text(i18n.gAddMaintenance, style: const TextStyle(color: AppColors.textPrimaryDark)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: type,
              items: types.map((t) => DropdownMenuItem(value: t, child: Text(maintenanceTypeLabelDe(t), style: const TextStyle(color: AppColors.textPrimaryDark)))).toList(),
              onChanged: (v) => setDialog(() => type = v ?? type),
              dropdownColor: AppColors.bgSurfaceRaisedDark,
              decoration: _deco(),
            ),
            const SizedBox(height: 10),
            TextField(controller: dateCtrl, decoration: _deco(label: i18n.gDate)),
            const SizedBox(height: 10),
            TextField(controller: kmCtrl, keyboardType: TextInputType.number, decoration: _deco(label: i18n.gOdometer)),
            const SizedBox(height: 10),
            TextField(controller: costCtrl, keyboardType: TextInputType.number, decoration: _deco(label: '${i18n.gCost} (€)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(i18n.gCancel)),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.accentPrimaryDark),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(i18n.gSave),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final ctx = await _callCtx();
    final costEuro = double.tryParse(costCtrl.text.trim().replaceAll(',', '.'));
    await ref.read(garageRepositoryProvider).addMaintenance(
          ctx['baseUrl']!,
          ctx['token']!,
          widget.vehicleId,
          type: type,
          performedAt: dateCtrl.text.trim(),
          odometerKm: int.tryParse(kmCtrl.text.trim()) ?? _vehicle!.odometerKm,
          costCents: costEuro == null ? null : (costEuro * 100).round(),
        );
    await _reload();
  }

  // -- Tankbuch ------------------------------------------------------------------

  Widget _buildFuel(I18n i18n) {
    final stats = _fuelStats;
    final entries = _fuel ?? const <GarageFuelEntry>[];
    return _sectionWithAction(
      i18n.gFuel,
      IconButton(
        icon: const Icon(Icons.add_circle_outline, color: AppColors.accentPrimaryDark),
        onPressed: _addFuel,
      ),
      [
        if (stats != null && stats.averageConsumptionPer100km != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Text('⛽ ${stats.averageConsumptionPer100km!.toStringAsFixed(1)} l/100 km',
                  style: const TextStyle(color: AppColors.accentPrimaryDark, fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(width: 12),
              Text('· ${_fmtEuro(stats.totalCostCents)} ${i18n.gTotal}',
                  style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 13)),
            ]),
          ),
        if (entries.isEmpty)
          Text(i18n.gNoFuel, style: const TextStyle(color: AppColors.textSecondaryDark))
        else
          ...entries.take(5).map((f) {
            final date = f.date;
            final dateStr = date != null ? '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.' : '';
            return Row(children: [
              Text(dateStr, style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 13)),
              const SizedBox(width: 10),
              Expanded(child: Text('${_fmtKm(f.odometerKm)} km · ${f.liters.toStringAsFixed(1)} l', style: const TextStyle(color: AppColors.textPrimaryDark, fontSize: 13))),
              Text(_fmtEuro(f.priceCentsTotal), style: const TextStyle(color: AppColors.textPrimaryDark, fontSize: 13, fontWeight: FontWeight.w600)),
            ]);
          }),
      ],
    );
  }

  Future<void> _addFuel() async {
    final i18n = ref.read(i18nProvider);
    final dateCtrl = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));
    final kmCtrl = TextEditingController(text: '${_vehicle!.odometerKm}');
    final litersCtrl = TextEditingController();
    final euroCtrl = TextEditingController();
    final stationCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSurfaceDark,
        title: Text(i18n.gAddFuel, style: const TextStyle(color: AppColors.textPrimaryDark)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: dateCtrl, decoration: _deco(label: i18n.gDate)),
          const SizedBox(height: 10),
          TextField(controller: kmCtrl, keyboardType: TextInputType.number, decoration: _deco(label: i18n.gOdometer)),
          const SizedBox(height: 10),
          TextField(controller: litersCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _deco(label: i18n.gLiters)),
          const SizedBox(height: 10),
          TextField(controller: euroCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _deco(label: '${i18n.gCost} (€)')),
          const SizedBox(height: 10),
          TextField(controller: stationCtrl, decoration: _deco(label: i18n.gStation)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(i18n.gCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accentPrimaryDark),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(i18n.gSave),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final ctx = await _callCtx();
    final liters = double.tryParse(litersCtrl.text.trim().replaceAll(',', '.'));
    final euro = double.tryParse(euroCtrl.text.trim().replaceAll(',', '.'));
    if (liters == null || liters <= 0 || euro == null) return;
    await ref.read(garageRepositoryProvider).addFuel(
          ctx['baseUrl']!,
          ctx['token']!,
          widget.vehicleId,
          date: dateCtrl.text.trim(),
          odometerKm: int.tryParse(kmCtrl.text.trim()) ?? _vehicle!.odometerKm,
          liters: liters,
          priceCentsTotal: (euro * 100).round(),
          station: stationCtrl.text.trim().isEmpty ? null : stationCtrl.text.trim(),
        );
    await _reload();
  }

  // -- Reifen --------------------------------------------------------------------

  Widget _buildTires(I18n i18n) {
    final tires = _tires ?? const <GarageTireSet>[];
    return _section(
      i18n.gTires,
      tires.isEmpty
          ? [Text(i18n.gNoTires, style: const TextStyle(color: AppColors.textSecondaryDark))]
          : tires.map((t) => Row(children: [
                Text(t.position == 'front' ? '⬆️' : '⬇️', style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 8),
                Expanded(child: Text('${t.brand} ${t.modelName} · ${t.size}', style: const TextStyle(color: AppColors.textPrimaryDark, fontSize: 13))),
                if (t.treadDepthMm != null)
                  Text('${t.treadDepthMm!.toStringAsFixed(1)} mm', style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 13)),
              ])).toList(),
    );
  }

  // -- Dokumente -------------------------------------------------------------------

  Widget _buildDocuments(I18n i18n) {
    final docs = _documents ?? const <GarageDocument>[];
    return _section(
      i18n.gDocuments,
      docs.isEmpty
          ? [Text(i18n.gNoDocuments, style: const TextStyle(color: AppColors.textSecondaryDark))]
          : docs.map((d) => Row(children: [
                const Icon(Icons.description_outlined, color: AppColors.textSecondaryDark, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(d.title, style: const TextStyle(color: AppColors.textPrimaryDark, fontSize: 13))),
                Text(_docTypeLabel(d.type), style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 12)),
              ])).toList(),
    );
  }

  String _docTypeLabel(String type) => switch (type) {
        'invoice' => 'Rechnung',
        'inspection' => 'Inspektion',
        'tuv' => 'TÜV',
        'service_record' => 'Wartung',
        _ => 'Sonstiges',
      };

  // -- Kosten ----------------------------------------------------------------------

  Widget _buildCosts(I18n i18n) {
    final c = _costs;
    if (c == null) return const SizedBox.shrink();
    return _section(i18n.gCosts, [
      Row(children: [
        Expanded(child: _costTile(i18n.gThisYear, _fmtEuro(c.thisYearCents))),
        const SizedBox(width: 10),
        Expanded(child: _costTile(i18n.gTotal, _fmtEuro(c.totalCents))),
      ]),
    ]);
  }

  Widget _costTile(String label, String value) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.bgSurfaceRaisedDark, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: AppColors.textPrimaryDark, fontSize: 17, fontWeight: FontWeight.w700)),
        ]),
      );

  // -- Bausteine --------------------------------------------------------------------

  Widget _section(String title, List<Widget> children) => Card(
        color: AppColors.bgSurfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
            const SizedBox(height: 10),
            ...children,
          ]),
        ),
      );

  Widget _sectionWithAction(String title, Widget action, List<Widget> children) => Card(
        color: AppColors.bgSurfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.3))),
              action,
            ]),
            const SizedBox(height: 6),
            ...children,
          ]),
        ),
      );

  InputDecoration _deco({String? label}) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSecondaryDark),
        filled: true,
        fillColor: AppColors.bgSurfaceRaisedDark,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  static String _fmtKm(int km) {
    final s = km.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final rest = s.length - i;
      buf.write(s[i]);
      if (rest > 1 && (rest - 1) % 3 == 0) buf.write('.');
    }
    return buf.toString();
  }

  static String _fmtEuro(int cents) {
    final euro = cents / 100;
    return '${euro.toStringAsFixed(euro % 1 == 0 ? 0 : 2).replaceAll('.', ',')} €';
  }
}

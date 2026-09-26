import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import 'garage_repository.dart';
import 'garage_vehicle_screen.dart';

/// Garage-Tab: Login-Karte gegen die EIGENE Garage-API (unabhaengig vom
/// MotoRoute-Login) und die Fahrzeug-Übersicht (Motorraeder/Autos,
/// Ampel-Status der Wartungserinnerungen).
class GarageScreen extends ConsumerStatefulWidget {
  const GarageScreen({super.key});

  @override
  ConsumerState<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends ConsumerState<GarageScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    await ref.read(garageSessionProvider.notifier).login(_emailCtrl.text.trim(), _passwordCtrl.text);
    final state = ref.read(garageSessionProvider);
    setState(() {
      _busy = false;
      _error = state.hasError ? _friendly(state.error) : null;
    });
    if (!state.hasError) ref.invalidate(garageListProvider);
  }

  String _friendly(Object? e) {
    final msg = e.toString();
    if (msg.contains('GarageApiException')) {
      if (msg.contains('401') || msg.contains('AUTH')) return ref.read(i18nProvider).gLoginFailed;
    }
    return '${ref.read(i18nProvider).gServerUnreachable}: ${e.toString().split('\n').first}';
  }

  Future<void> _openCreateDialog() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _CreateVehicleSheet(),
    );
    ref.invalidate(garageListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final i18n = ref.watch(i18nProvider);
    final session = ref.watch(garageSessionProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBaseDark,
        elevation: 0,
        title: Text('🏍️ ${i18n.gTitle}', style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          session.value != null
              ? IconButton(
                  tooltip: i18n.gLogout,
                  icon: const Icon(Icons.logout, color: AppColors.textSecondaryDark),
                  onPressed: () async {
                    await ref.read(garageSessionProvider.notifier).logout();
                    ref.invalidate(garageListProvider);
                  },
                )
              : const SizedBox.shrink(),
        ],
      ),
      body: session.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(_friendly(e), style: const TextStyle(color: AppColors.textSecondaryDark))),
        data: (s) {
          if (s == null) return _buildLogin(i18n);
          return _buildGarage(i18n, s);
        },
      ),
    );
  }

  // -- Login-Karte -----------------------------------------------------------

  Widget _buildLogin(I18n i18n) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            color: AppColors.bgSurfaceDark,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('🏍️🚗', textAlign: TextAlign.center, style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 12),
                  Text(
                    i18n.gLoginTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textPrimaryDark, fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    i18n.gLoginHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(
                      labelText: i18n.gEmail,
                      filled: true,
                      fillColor: AppColors.bgSurfaceRaisedDark,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _login(),
                    decoration: InputDecoration(
                      labelText: i18n.gPassword,
                      filled: true,
                      fillColor: AppColors.bgSurfaceRaisedDark,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppColors.statusDanger, fontSize: 13)),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentPrimaryDark,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _busy ? null : _login,
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(i18n.gLoginButton, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -- Garage-Übersicht -------------------------------------------------------

  Widget _buildGarage(I18n i18n, GarageSession session) {
    final list = ref.watch(garageListProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(garageListProvider.future),
      child: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          children: [
            const SizedBox(height: 80),
            const Icon(Icons.cloud_off, color: AppColors.textMutedDark, size: 44),
            const SizedBox(height: 10),
            Center(
              child: Text(
                _friendly(e),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondaryDark),
              ),
            ),
          ],
        ),
        data: (vehicles) {
          final motos = vehicles.where((v) => v.category == GarageCategory.motorcycle).toList();
          final cars = vehicles.where((v) => v.category == GarageCategory.car).toList();
          if (vehicles.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 60),
                const Text('🏍️🚗', textAlign: TextAlign.center, style: TextStyle(fontSize: 44)),
                const SizedBox(height: 14),
                Text(
                  i18n.gEmpty,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondaryDark),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.accentPrimaryDark),
                  onPressed: _openCreateDialog,
                  icon: const Icon(Icons.add),
                  label: Text(i18n.gAddVehicle),
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentPrimaryDark,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _openCreateDialog,
                icon: const Icon(Icons.add),
                label: Text(i18n.gAddVehicle, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              if (motos.isNotEmpty) ...[
                const SizedBox(height: 18),
                _sectionHeader('🏍️ ${i18n.gMyMotos} (${motos.length})'),
                ...motos.map((v) => _VehicleCard(
                      vehicle: v,
                      i18n: i18n,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => GarageVehicleScreen(vehicleId: v.id),
                      )),
                    )),
              ],
              if (cars.isNotEmpty) ...[
                const SizedBox(height: 18),
                _sectionHeader('🚗 ${i18n.gMyCars} (${cars.length})'),
                ...cars.map((v) => _VehicleCard(
                      vehicle: v,
                      i18n: i18n,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => GarageVehicleScreen(vehicleId: v.id),
                      )),
                    )),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.textSecondaryDark, fontWeight: FontWeight.w700, fontSize: 15)),
      );
}

// -- Fahrzeug-Karte -------------------------------------------------------------

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.vehicle, required this.i18n, required this.onTap});

  final GarageVehicle vehicle;
  final I18n i18n;
  final VoidCallback onTap;

  Color get _statusColor {
    switch (vehicle.worstStatus) {
      case 'overdue':
        return AppColors.statusDanger;
      case 'dueSoon':
        return AppColors.statusWarning;
      default:
        return AppColors.statusSuccess;
    }
  }

  String _statusText(I18n i18n) {
    switch (vehicle.worstStatus) {
      case 'overdue':
        return i18n.gStatusOverdue;
      case 'dueSoon':
        return i18n.gStatusDueSoon;
      default:
        return i18n.gStatusOk;
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = this.i18n;
    return Card(
      color: AppColors.bgSurfaceDark,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.bgSurfaceRaisedDark,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(vehicle.category.emoji, style: const TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(vehicle.title,
                        style: const TextStyle(
                            color: AppColors.textPrimaryDark, fontWeight: FontWeight.w700, fontSize: 16),
                        overflow: TextOverflow.ellipsis),
                    if (vehicle.subtitle.isNotEmpty)
                      Text(vehicle.subtitle,
                          style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(
                      '${_fmtKm(vehicle.odometerKm)} km',
                      style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Icon(Icons.circle, size: 12, color: _statusColor),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 92,
                    child: Text(
                      _statusText(i18n),
                      textAlign: TextAlign.right,
                      style: TextStyle(color: _statusColor, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

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
}

// -- Fahrzeug anlegen (Bottom Sheet) ---------------------------------------------

class _CreateVehicleSheet extends ConsumerStatefulWidget {
  const _CreateVehicleSheet();

  @override
  ConsumerState<_CreateVehicleSheet> createState() => _CreateVehicleSheetState();
}

class _CreateVehicleSheetState extends ConsumerState<_CreateVehicleSheet> {
  GarageCategory _category = GarageCategory.motorcycle;
  List<GarageCatalogEntry>? _manufacturers;
  List<GarageCatalogEntry>? _models;
  List<GarageCatalogEntry>? _variants;
  GarageCatalogEntry? _manufacturer;
  GarageCatalogEntry? _model;
  GarageCatalogEntry? _variant;
  final _nicknameCtrl = TextEditingController();
  final _kmCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadManufacturers();
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _kmCtrl.dispose();
    _colorCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadManufacturers() async {
    final session = ref.read(garageSessionProvider).value;
    final baseUrl = await ref.read(garageBaseUrlProvider.future);
    if (session == null) return;
    try {
      final list = await ref
          .read(garageRepositoryProvider)
          .manufacturers(baseUrl, session.token, motorcycle: _category == GarageCategory.motorcycle);
      setState(() => _manufacturers = list);
    } catch (e) {
      setState(() => _error = e.toString().split('\n').first);
    }
  }

  Future<void> _pickCategory(GarageCategory c) async {
    setState(() {
      _category = c;
      _manufacturers = null;
      _models = null;
      _variants = null;
      _manufacturer = null;
      _model = null;
      _variant = null;
    });
    await _loadManufacturers();
  }

  Future<void> _pickManufacturer(GarageCatalogEntry? m) async {
    setState(() {
      _manufacturer = m;
      _models = null;
      _variants = null;
      _model = null;
      _variant = null;
    });
    if (m == null) return;
    final session = ref.read(garageSessionProvider).value;
    final baseUrl = await ref.read(garageBaseUrlProvider.future);
    if (session == null) return;
    final list = await ref.read(garageRepositoryProvider).models(baseUrl, session.token, m.id);
    setState(() => _models = list);
  }

  Future<void> _pickModel(GarageCatalogEntry? m) async {
    setState(() {
      _model = m;
      _variants = null;
      _variant = null;
    });
    if (m == null) return;
    final session = ref.read(garageSessionProvider).value;
    final baseUrl = await ref.read(garageBaseUrlProvider.future);
    if (session == null) return;
    final list = await ref.read(garageRepositoryProvider).variants(baseUrl, session.token, m.id);
    setState(() => _variants = list);
  }

  Future<void> _submit() async {
    final i18n = ref.read(i18nProvider);
    if (_model == null) {
      setState(() => _error = i18n.gErrPickModel);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = ref.read(garageSessionProvider).value!;
      final baseUrl = await ref.read(garageBaseUrlProvider.future);
      await ref.read(garageRepositoryProvider).createVehicle(
            baseUrl,
            session.token,
            category: _category,
            manufacturerName: _manufacturer?.name ?? '',
            modelName: _model!.name,
            variantId: _variant?.id,
            variantName: _variant?.name,
            odometerKm: int.tryParse(_kmCtrl.text.trim().replaceAll('.', '')),
            nickname: _nicknameCtrl.text.trim().isEmpty ? null : _nicknameCtrl.text.trim(),
            color: _colorCtrl.text.trim().isEmpty ? null : _colorCtrl.text.trim(),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString().split('\n').first;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = ref.watch(i18nProvider);
    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(i18n.gAddVehicle,
                style: const TextStyle(color: AppColors.textPrimaryDark, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            SegmentedButton<GarageCategory>(
              segments: [
                ButtonSegment(value: GarageCategory.motorcycle, label: Text('🏍️ ${i18n.gMoto}')),
                ButtonSegment(value: GarageCategory.car, label: Text('🚗 ${i18n.gCar}')),
              ],
              selected: {_category},
              onSelectionChanged: (s) => _pickCategory(s.first),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<GarageCatalogEntry>(
              initialValue: _manufacturer,
              hint: Text(_manufacturers == null ? i18n.gLoading : i18n.gManufacturer),
              items: (_manufacturers ?? [])
                  .map((m) => DropdownMenuItem(value: m, child: Text(m.name, style: const TextStyle(color: AppColors.textPrimaryDark))))
                  .toList(),
              onChanged: _pickManufacturer,
              dropdownColor: AppColors.bgSurfaceRaisedDark,
              decoration: _dropdownDeco(),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<GarageCatalogEntry>(
              initialValue: _model,
              hint: Text(_models == null ? ( _manufacturer == null ? i18n.gFirstManufacturer : i18n.gLoading) : i18n.gModel),
              items: (_models ?? [])
                  .map((m) => DropdownMenuItem(value: m, child: Text(m.name, style: const TextStyle(color: AppColors.textPrimaryDark))))
                  .toList(),
              onChanged: _pickModel,
              dropdownColor: AppColors.bgSurfaceRaisedDark,
              decoration: _dropdownDeco(),
            ),
            if (_variants != null && _variants!.isNotEmpty) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<GarageCatalogEntry>(
                initialValue: _variant,
                hint: Text(i18n.gVariant),
                items: _variants!
                    .map((v) => DropdownMenuItem(value: v, child: Text(v.name, style: const TextStyle(color: AppColors.textPrimaryDark))))
                    .toList(),
                onChanged: (v) => setState(() => _variant = v),
                dropdownColor: AppColors.bgSurfaceRaisedDark,
                decoration: _dropdownDeco(),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _nicknameCtrl,
              decoration: _fieldDeco(i18n.gNickname),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _kmCtrl,
                  keyboardType: TextInputType.number,
                  decoration: _fieldDeco('${i18n.gOdometer} (km)'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _colorCtrl,
                  decoration: _fieldDeco(i18n.gColor),
                ),
              ),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AppColors.statusDanger, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentPrimaryDark,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(i18n.gSave, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _dropdownDeco() => InputDecoration(
        filled: true,
        fillColor: AppColors.bgSurfaceRaisedDark,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  InputDecoration _fieldDeco(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSecondaryDark),
        filled: true,
        fillColor: AppColors.bgSurfaceRaisedDark,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/error_reporter.dart';
import '../../core/theme/app_colors.dart';
import '../auth/auth_providers.dart';
import 'garage_repository.dart';
import 'garage_vehicle_screen.dart';

/// Garage-Tab: Auto-Provisioning gegen die EIGENE Garage-API (mit dem
/// MotoRoute-Konto, ohne zweites Login) und die Fahrzeug-Übersicht
/// (Motorraeder/Autos, Ampel-Status der Wartungserinnerungen).
class GarageScreen extends ConsumerStatefulWidget {
  const GarageScreen({super.key});

  @override
  ConsumerState<GarageScreen> createState() => _GarageScreenState();
}

/// Einheitliche Garage-Fehlermeldung fuer Liste und Anlegen-Dialog.
///
/// 401/AUTH heisst "Anmeldung abgelaufen"; sonst traegt der erste
/// Zeilen-Text der Server-Meldung die Ursache - Stacktraces und
/// DioException-Header sind fuer Nutzer unlesbar.
String garageMessageFor(
  Object? e, {
  required String loginFailed,
  required String unreachable,
}) {
  final msg = e.toString();
  if (msg.contains('GarageApiException') &&
      (msg.contains('401') || msg.contains('AUTH'))) {
    return loginFailed;
  }
  return '$unreachable: ${msg.split('\n').first}';
}

/// Liest den Kilometerstand aus dem Eingabefeld.
///
/// `null` heisst "keine Angabe" oder "nicht lesbar" - der Aufrufer
/// unterscheidet die Faelle ueber den Feldtext, damit ein leeres Feld
/// weiterhin erlaubt bleibt, "12a" aber als Fehler gemeldet wird.
int? parseOdometerKm(String raw) {
  final cleaned = raw.trim().replaceAll('.', '').replaceAll(' ', '');
  if (cleaned.isEmpty) return null;
  final value = int.tryParse(cleaned);
  if (value == null || value < 0) return null;
  return value;
}

/// Liest das Baujahr aus dem Eingabefeld.
///
/// `null` heisst "keine Angabe" oder "nicht plausibel" - der Aufrufer
/// unterscheidet ueber den Feldtext. Erlaubt ist 1900 bis [maxYear]
/// (aktuelles Jahr + 1, weil neue Modelle oft im Vorjahr erscheinen).
int? parseModelYear(String raw, {required int maxYear}) {
  final cleaned = raw.trim();
  if (cleaned.isEmpty) return null;
  final value = int.tryParse(cleaned);
  if (value == null) return null;
  if (value < 1900 || value > maxYear) return null;
  return value;
}

class _GarageScreenState extends ConsumerState<GarageScreen> {
  bool _busy = false;

  String _friendly(Object? e) {
    final i18n = ref.read(i18nProvider);
    return garageMessageFor(e,
        loginFailed: i18n.gLoginFailed, unreachable: i18n.gServerUnreachable);
  }

  Future<void> _openCreateDialog() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.bgSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _CreateVehicleSheet(),
    );
    ref.invalidate(garageListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final i18n = ref.watch(i18nProvider);
    final session = ref.watch(garageSessionProvider);

    return Scaffold(
      backgroundColor: context.palette.bgBase,
      appBar: AppBar(
        backgroundColor: context.palette.bgBase,
        elevation: 0,
        title: Text(i18n.gTitle,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          session.value != null
              ? IconButton(
                  tooltip: i18n.gLogout,
                  icon: Icon(Icons.logout,
                      color: context.palette.textSecondary),
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
        error: (e, _) => Center(
            child: Text(_friendly(e),
                style: TextStyle(color: context.palette.textSecondary))),
        data: (s) {
          if (s == null) return _buildNeedsAccount(i18n);
          return _buildGarage(i18n, s);
        },
      ),
    );
  }

  // -- Login-Karte -----------------------------------------------------------

  Widget _buildNeedsAccount(I18n i18n) {
    // Die Garage verbindet sich automatisch mit dem MotoRoute-Konto; bei
    // kalter API bleibt die Oberfläche bedienbar und bietet einen Retry.
    final auth = ref.watch(authControllerProvider);
    final signedIn = auth.isAuthenticated;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            color: context.palette.bgSurface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.garage_outlined,
                      size: 44, color: context.palette.accentPrimary),
                  const SizedBox(height: 12),
                  Text(
                    signedIn ? i18n.gConnectTitle : i18n.gConnectNeedLogin,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: context.palette.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    signedIn ? i18n.gConnectHint : i18n.gConnectNeedLoginHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: context.palette.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 18),
                  if (signedIn)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: context.palette.accentPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _busy
                          ? null
                          : () async {
                              setState(() {
                                _busy = true;
                              });
                              await ref
                                  .read(garageSessionProvider.notifier)
                                  .provisionFromAuth();
                              if (mounted) setState(() => _busy = false);
                              ref.invalidate(garageListProvider);
                            },
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.sync),
                      label: Text(i18n.gConnectRetry,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
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
            Icon(Icons.cloud_off,
                color: context.palette.textMuted, size: 44),
            const SizedBox(height: 10),
            Center(
              child: Text(
                _friendly(e),
                textAlign: TextAlign.center,
                style: TextStyle(color: context.palette.textSecondary),
              ),
            ),
          ],
        ),
        data: (vehicles) {
          final motos = vehicles
              .where((v) => v.category == GarageCategory.motorcycle)
              .toList();
          final cars =
              vehicles.where((v) => v.category == GarageCategory.car).toList();
          if (vehicles.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 60),
                Icon(Icons.garage_outlined,
                    size: 48, color: context.palette.textSecondary),
                const SizedBox(height: 14),
                Text(
                  i18n.gEmpty,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.palette.textSecondary),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: context.palette.accentPrimary),
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
                  backgroundColor: context.palette.accentPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _openCreateDialog,
                icon: const Icon(Icons.add),
                label: Text(i18n.gAddVehicle,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              if (motos.isNotEmpty) ...[
                const SizedBox(height: 18),
                _sectionHeader('${i18n.gMyMotos} (${motos.length})'),
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
                _sectionHeader('${i18n.gMyCars} (${cars.length})'),
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
            style: TextStyle(
                color: context.palette.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 15)),
      );
}

// -- Fahrzeug-Karte -------------------------------------------------------------

class _VehicleCard extends StatelessWidget {
  const _VehicleCard(
      {required this.vehicle, required this.i18n, required this.onTap});

  final GarageVehicle vehicle;
  final I18n i18n;
  final VoidCallback onTap;

  /// Ampel-Farbe des Wartungsstatus - braucht die Palette des Schemas,
  /// deshalb als Methode statt Getter (ein Getter haette keinen context).
  Color _statusColor(AppPalette palette) {
    switch (vehicle.worstStatus) {
      case 'overdue':
        return palette.statusDanger;
      case 'dueSoon':
        return palette.statusWarning;
      default:
        return palette.statusSuccess;
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
      color: context.palette.bgSurface,
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
                  color: context.palette.bgSurfaceRaised,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(vehicle.category.emoji,
                    style: const TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(vehicle.title,
                        style: TextStyle(
                            color: context.palette.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 16),
                        overflow: TextOverflow.ellipsis),
                    if (vehicle.subtitle.isNotEmpty)
                      Text(vehicle.subtitle,
                          style: TextStyle(
                              color: context.palette.textSecondary,
                              fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(
                      '${_fmtKm(vehicle.odometerKm)} km',
                      style: TextStyle(
                          color: context.palette.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Icon(Icons.circle,
                      size: 12, color: _statusColor(context.palette)),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 92,
                    child: Text(
                      _statusText(i18n),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: _statusColor(context.palette),
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
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
  ConsumerState<_CreateVehicleSheet> createState() =>
      _CreateVehicleSheetState();
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
  final _yearCtrl = TextEditingController();
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
    _yearCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadManufacturers() async {
    final session = ref.read(garageSessionProvider).value;
    final baseUrl = await ref.read(garageBaseUrlProvider.future);
    if (session == null) return;
    try {
      final list = await ref.read(garageRepositoryProvider).manufacturers(
          baseUrl, session.token,
          motorcycle: _category == GarageCategory.motorcycle);
      setState(() => _manufacturers = list);
    } catch (e) {
      ErrorReporter.instance.report('garage.load', e);
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
    final list = await ref
        .read(garageRepositoryProvider)
        .models(baseUrl, session.token, m.id);
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
    final list = await ref
        .read(garageRepositoryProvider)
        .variants(baseUrl, session.token, m.id);
    setState(() => _variants = list);
  }

  Future<void> _submit() async {
    final i18n = ref.read(i18nProvider);
    if (_model == null) {
      setState(() => _error = i18n.gErrPickModel);
      return;
    }
    // Kilometerstand vor dem Absenden pruefen: ein Tippfehler soll hier
    // auffallen und nicht als Serverfehler zurueckkommen.
    final odometerKm = parseOdometerKm(_kmCtrl.text);
    if (_kmCtrl.text.trim().isNotEmpty && odometerKm == null) {
      setState(() =>
          _error = 'Kilometerstand bitte als ganze Zahl angeben, z. B. 12500.');
      return;
    }
    if (odometerKm != null && odometerKm > 999999) {
      setState(() => _error =
          'Kilometerstand ist zu hoch (höchstens 999.999 km). Bitte prüfe die Eingabe.');
      return;
    }
    // Baujahr: optional, aber plausibel. Das Vorjahr ist erlaubt, weil neue
    // Modelle dort schon auf dem Markt sind.
    final maxYear = DateTime.now().year + 1;
    final modelYear = parseModelYear(_yearCtrl.text, maxYear: maxYear);
    if (_yearCtrl.text.trim().isNotEmpty && modelYear == null) {
      setState(() => _error =
          'Baujahr bitte vierstellig zwischen 1900 und $maxYear angeben.');
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
            odometerKm: odometerKm,
            year: modelYear,
            nickname: _nicknameCtrl.text.trim().isEmpty
                ? null
                : _nicknameCtrl.text.trim(),
            color:
                _colorCtrl.text.trim().isEmpty ? null : _colorCtrl.text.trim(),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      ErrorReporter.instance.report('garage.write', e);
      final i18n = ref.read(i18nProvider);
      setState(() {
        _busy = false;
        _error = garageMessageFor(e,
            loginFailed: i18n.gLoginFailed,
            unreachable: i18n.gServerUnreachable);
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
                style: TextStyle(
                    color: context.palette.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            SegmentedButton<GarageCategory>(
              segments: [
                ButtonSegment(
                    value: GarageCategory.motorcycle, label: Text(i18n.gMoto)),
                ButtonSegment(
                    value: GarageCategory.car, label: Text(i18n.gCar)),
              ],
              selected: {_category},
              onSelectionChanged: (s) => _pickCategory(s.first),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<GarageCatalogEntry>(
              initialValue: _manufacturer,
              hint: Text(
                  _manufacturers == null ? i18n.gLoading : i18n.gManufacturer),
              items: (_manufacturers ?? [])
                  .map((m) => DropdownMenuItem(
                      value: m,
                      child: Text(m.name,
                          style: TextStyle(
                              color: context.palette.textPrimary))))
                  .toList(),
              onChanged: _pickManufacturer,
              dropdownColor: context.palette.bgSurfaceRaised,
              decoration: _dropdownDeco(),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<GarageCatalogEntry>(
              initialValue: _model,
              hint: Text(_models == null
                  ? (_manufacturer == null
                      ? i18n.gFirstManufacturer
                      : i18n.gLoading)
                  : i18n.gModel),
              items: (_models ?? [])
                  .map((m) => DropdownMenuItem(
                      value: m,
                      child: Text(m.name,
                          style: TextStyle(
                              color: context.palette.textPrimary))))
                  .toList(),
              onChanged: _pickModel,
              dropdownColor: context.palette.bgSurfaceRaised,
              decoration: _dropdownDeco(),
            ),
            if (_variants != null && _variants!.isNotEmpty) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<GarageCatalogEntry>(
                initialValue: _variant,
                hint: Text(i18n.gVariant),
                items: _variants!
                    .map((v) => DropdownMenuItem(
                        value: v,
                        child: Text(v.name,
                            style: TextStyle(
                                color: context.palette.textPrimary))))
                    .toList(),
                onChanged: (v) => setState(() => _variant = v),
                dropdownColor: context.palette.bgSurfaceRaised,
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
                  controller: _yearCtrl,
                  keyboardType: TextInputType.number,
                  decoration: _fieldDeco(i18n.gYear),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _colorCtrl,
              decoration: _fieldDeco(i18n.gColor),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: TextStyle(
                      color: context.palette.statusDanger, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: context.palette.accentPrimary,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(i18n.gSave,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _dropdownDeco() => InputDecoration(
        filled: true,
        fillColor: context.palette.bgSurfaceRaised,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  InputDecoration _fieldDeco(String label) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: context.palette.textSecondary),
        filled: true,
        fillColor: context.palette.bgSurfaceRaised,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );
}

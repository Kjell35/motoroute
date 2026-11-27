import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart';
import '../data/pairing_repository.dart';

/// M3-Feature, App-zu-App-Pairing: Die **gebende** App zeigt den QR-Code
/// (Pairing-Dialog); die **nehmende** App scannt ihn hier und übernimmt die
/// geplante Route in die Wegpunkt-Liste — über dieselbe Backend-Abruf-
/// Logik wie der PC-Planning-Link (QR-Host statt Env-Basis).
///
/// Erkannt wird eine MotoRoute-Plan-URL (`/plan/{token}`); fremde Codes
/// werden mit Hinweis verworfen, statt die Kamera zu schließen.
class RouteScanScreen extends ConsumerStatefulWidget {
  const RouteScanScreen({super.key, this.repository});

  /// Injektion für Tests; Produktion nutzt `null` und baut das Default-
  /// Repository.
  final PairingRepository? repository;

  @override
  ConsumerState<RouteScanScreen> createState() => _RouteScanScreenState();
}

class _RouteScanScreenState extends ConsumerState<RouteScanScreen> {
  MobileScannerController? _controller;
  bool _handled = false;
  String? _error;

  PairingRepository get repository => widget.repository ?? PairingRepository();

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final String? value = barcode.rawValue;
      if (value == null) continue;
      final String? token = PairingRepository.planTokenFromUrl(value);
      if (token == null) {
        if (mounted) {
          setState(() => _error = 'Das ist kein MotoRoute-Plan-QR-Code.');
        }
        continue;
      }
      _handled = true;
      await _controller?.stop();
      if (!mounted) return;
      // Volle gescannte URL übergeben: Der Host im QR (LAN/Hotspot) ist die
      // Backend-Basis für den Abruf, nicht die build-zeitliche Env-Basis.
      await _importPlan(value);
      return;
    }
  }

  Future<void> _importPlan(String scannedUrl) async {
    setState(() => _error = null);
    try {
      final points = await repository.fetchPlanFromScan(scannedUrl);
      if (!mounted) return;
      if (points == null || points.isEmpty) {
        setState(() {
          _error =
              'Am gescannten Gerät wurde noch nichts geplant (Token unbekannt oder abgelaufen).';
          _handled = false; // weiter scannen erlaubt
        });
        await _controller?.start();
        return;
      }
      // Bestehende Route nicht still überschreiben: vorher fragen. Der
      // Scanner ist hier bereits gestoppt - bei "Behalten" wieder starten.
      final bool replace = await _confirmReplace(points.length);
      if (!mounted) return;
      if (!replace) {
        setState(() {
          _error = 'Nichts übernommen - die bestehende Route bleibt unverändert.';
          _handled = false;
        });
        await _controller?.start();
        return;
      }
      // Brücke in die alte App: echte Wegpunkt-Liste der Touren.
      ref.read(waypointListProvider.notifier).state = points
          .map((p) => Waypoint(lat: p.lat, lng: p.lng, label: p.label))
          .toList(growable: false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: context.palette.accentPrimary,
          content: Text('Route mit ${points.length} Punkten übernommen.'),
        ),
      );
      // Zurück zum Aufrufer statt erneut '/waypoints' zu pushen: die Liste
      // liegt bereits darunter und zeigt die Punkte sofort an.
      Navigator.of(context).pop(true);
    } on PairingException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _handled = false;
        });
        await _controller?.start();
      }
    }
  }

  /// Fragt nach, bevor eine bestehende Route überschrieben wird.
  /// Leere Liste -> keine Rückfrage nötig.
  Future<bool> _confirmReplace(int incoming) async {
    final existing = ref.read(waypointListProvider);
    if (existing.isEmpty) return true;
    final bool? replace = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.palette.bgSurface,
        title: const Text('Bestehende Route ersetzen?'),
        content: Text(
          'Es sind bereits ${existing.length} Wegpunkte geplant. '
          'Der Plan mit $incoming Punkten ersetzt sie.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Behalten'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Ersetzen'),
          ),
        ],
      ),
    );
    return replace ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.bgBase,
      appBar: AppBar(
        backgroundColor: context.palette.bgBase,
        title: const Text('Route scannen'),
      ),
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            MobileScanner(
              controller: _controller ??= MobileScannerController(
                formats: const [BarcodeFormat.qrCode],
              ),
              onDetect: _onDetect,
            ),
            // Scan-Rahmen als visueller Fokus, ohne Eingriff in die
            // Kamera-Engine.
            Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border:
                      Border.all(color: context.palette.accentPrimary, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            _error ?? 'QR-Code der anderen App ins Feld halten.',
            style: AppTypography.caption.copyWith(
              color: _error != null
                  ? context.palette.statusDanger
                  : context.palette.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ]),
    );
  }
}

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

  /// Extrahiert das Plan-Token aus einer MotoRoute-Plan-URL; `null` bei
  /// fremden URLs. Öffentlich/statisch, damit die Erkennung ohne Kamera
  /// testbar ist.
  static String? planTokenFromUrl(String value) =>
      PairingRepository.planTokenFromUrl(value);

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
      final String? token = RouteScanScreen.planTokenFromUrl(value);
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
      // Brücke in die alte App: echte Wegpunkt-Liste der Touren.
      ref.read(waypointListProvider.notifier).state = points
          .map((p) => Waypoint(lat: p.lat, lng: p.lng, label: p.label))
          .toList(growable: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.accentPrimaryDark,
          content: Text('Route mit ${points.length} Punkten übernommen.'),
        ),
      );
      Navigator.of(context).pushReplacementNamed('/waypoints');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBaseDark,
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
                      Border.all(color: AppColors.accentPrimaryDark, width: 2),
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
                  ? AppColors.statusDanger
                  : AppColors.textSecondaryDark,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ]),
    );
  }
}

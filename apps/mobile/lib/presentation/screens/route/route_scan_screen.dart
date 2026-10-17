import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../application/route/waypoint_providers.dart';
import '../../../design/tokens/mr_colors.dart';
import '../../../design/tokens/mr_theme.dart';
import '../../../infrastructure/pairing/http_pairing_repository.dart';

/// QR-Scanner für App-zu-App-Pairing: Die **gebende** App zeigt den QR-Code
/// (Pairing-Dialog); die **nehmende** App scannt ihn hier und übernimmt die
/// geplante Route über dieselbe Backend-Abruf-Logik wie der PC-Planning-Link.
///
/// Erkannt wird eine MotoRoute-Plan-URL (`/plan/{token}`); fremde Codes
/// werden mit Hinweis verworfen, statt die Kamera zu schließen.
class RouteScanScreen extends ConsumerStatefulWidget {
  const RouteScanScreen({super.key, this.repository});

  /// Extrahiert das Plan-Token aus einer MotoRoute-Plan-URL; `null` bei fremden URLs.
  /// Öffentlich/statisch, damit die Erkennung ohne Kamera testbar ist.
  static String? planTokenFromUrl(String value) =>
      PairingRepository.planTokenFromUrl(value);

  /// Injektion für Tests; Produktion nutzt `null` und baut das Default-Repository.
  final PairingRepository? repository;

  @override
  ConsumerState<RouteScanScreen> createState() => _RouteScanScreenState();

  static const String routePath = '/scan';
}

class _RouteScanScreenState extends ConsumerState<RouteScanScreen> {
  MobileScannerController? _controller;
  bool _handled = false;
  String? _error;

  PairingRepository get repository =>
      widget.repository ?? PairingRepository();

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

  /// Extrahiert das Plan-Token aus einer MotoRoute-Plan-URL; `null` bei fremden URLs.

  Future<void> _importPlan(String scannedUrl) async {
    setState(() => _error = null);
    try {
      final places = await repository.fetchPlanFromScan(scannedUrl);
      if (!mounted) return;
      if (places == null || places.isEmpty) {
        setState(() {
          _error = 'Am gescannten Gerät wurde noch nichts geplant (Token unbekannt oder abgelaufen).';
          _handled = false; // weiter scannen erlaubt
        });
        await _controller?.start();
        return;
      }
      final notifier = ref.read(waypointsProvider.notifier);
      notifier.clear();
      notifier.addPlace(places.first);
      for (final place in places.skip(1)) {
        notifier.addPlace(place);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Route mit ${places.length} Punkten übernommen.')),
      );
      context.go('/route');
    } on PairingException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _handled = false;
        });
        await _controller?.start();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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
            // Scan-Rahmen als visueller Fokus, ohne Eingriff in die Kamera-Engine.
            Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: MrColors.accentPrimary, width: 2),
                  borderRadius: BorderRadius.circular(MrRadii.card),
                ),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(MrSpacing.md),
          child: Text(
            _error ?? 'QR-Code der anderen App ins Feld halten.',
            style: MrTypography.label.copyWith(
              color: _error != null ? MrColors.danger : MrColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ]),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../application/route/waypoint_providers.dart';
import '../../../design/tokens/mr_colors.dart';
import '../../../design/tokens/mr_theme.dart';
import '../../../domain/models/place.dart';
import '../../../infrastructure/pairing/http_pairing_repository.dart';

/// Dialog „Route am Computer planen“: erzeugt Pairing-Token, zeigt einen
/// QR-Code mit dem Plan-Link (Handy-Kamera statt Abtippen) und übernimmt den
/// geplanten Entwurf mit „Plan abrufen“ (Pull-Muster).
class ComputerPlanningSheet extends ConsumerStatefulWidget {
  const ComputerPlanningSheet({super.key, required this.repository});

  final PairingRepository repository;

  @override
  ConsumerState<ComputerPlanningSheet> createState() => _ComputerPlanningSheetState();
}

class _ComputerPlanningSheetState extends ConsumerState<ComputerPlanningSheet> {
  PairingStart? _start;
  String? _error;
  bool _busy = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _startPairing();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _startPairing() async {
    setState(() => _busy = true);
    try {
      final PairingStart start = await widget.repository.start();
      if (!mounted) return;
      setState(() => _start = start);
      // Auto-Poll alle 5 Sekunden, bis der Plan da ist oder das Dialog zuläuft.
      _poll = Timer.periodic(const Duration(seconds: 5), (_) => _fetchPlan(auto: true));
    } on PairingException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fetchPlan({bool auto = false}) async {
    final PairingStart? start = _start;
    if (start == null || _busy) return;
    setState(() => _busy = true);
    try {
      final List<Place>? places = await widget.repository.fetchPlan(start.token);
      if (!mounted) return;
      if (places == null) {
        if (!auto) setState(() => _error = 'Token unbekannt oder abgelaufen.');
        return;
      }
      if (places.isEmpty) {
        if (!auto) setState(() => _error = 'Am Computer wurde noch nichts geplant.');
        return;
      }
      _poll?.cancel();
      final WaypointController notifier = ref.read(waypointsProvider.notifier);
      notifier.clear();
      notifier.addPlace(places.first);
      for (final place in places.skip(1)) {
        notifier.addPlace(place);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Route mit ${places.length} Punkten übernommen.')),
      );
    } on PairingException catch (error) {
      if (mounted && !auto) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final PairingStart? start = _start;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(MrSpacing.md),
        // Scrollbar, damit QR+Link auch auf kleinen Displays inline passen.
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Route am Computer planen', style: MrTypography.title),
          const SizedBox(height: MrSpacing.xs),
          const Text(
            'Am Computer bequemer tippen? Öffne den Link, plane dort — mit „Plan abrufen“ landet die Route wieder hier.',
            style: MrTypography.label,
          ),
          const SizedBox(height: MrSpacing.md),
          if (start != null) ...[
            Center(
              child: Container(
                width: 220,
                height: 220,
                padding: const EdgeInsets.all(MrSpacing.sm),
                decoration: BoxDecoration(
                  color: MrColors.raised,
                  borderRadius: BorderRadius.circular(MrRadii.card),
                ),
                child: PrettyQrView.data(
                  data: start.planUrl,
                  errorCorrectLevel: QrErrorCorrectLevel.H,
                ),
              ),
            ),
            const SizedBox(height: MrSpacing.sm),
            const Text(
              'Mit der Handy-Kamera scannen — der Plan-Editor öffnet sich im Browser.',
              style: MrTypography.label,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: MrSpacing.sm),
            SelectableText(start.planUrl, style: MrTypography.title.copyWith(color: MrColors.accentPrimary)),
            if (start.planUrls.length > 1) ...[
              const SizedBox(height: MrSpacing.xs),
              Text(
                'Weitere Adressen (z. B. Hotspot): ${start.planUrls.skip(1).join(' · ')}',
                style: MrTypography.label.copyWith(color: MrColors.textSecondary),
              ),
            ],
            const SizedBox(height: MrSpacing.sm),
            Text('Token: ${start.token}', style: MrTypography.label),
            const SizedBox(height: MrSpacing.md),
          ],
          if (_error != null)
            Text(_error!, style: MrTypography.label.copyWith(color: MrColors.danger)),
          const SizedBox(height: MrSpacing.sm),
          FilledButton.icon(
            onPressed: _busy ? null : () => _fetchPlan(),
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            label: const Text('Plan abrufen'),
          ),
          const SizedBox(height: MrSpacing.sm),
          // App-zu-App: Wer selbst die Route EMPFANGEN will, scannt hier den
          // QR-Code der anderen App statt den Plan über das Backend zu ziehen.
          FilledButton.tonalIcon(
            onPressed: () {
              Navigator.of(context).pop();
              context.push('/scan');
            },
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Route von anderer App scannen'),
          ),
          const SizedBox(height: MrSpacing.sm),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Schließen'),
          ),
        ]),
        ),
      ),
    );
  }
}

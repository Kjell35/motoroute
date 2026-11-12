import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';
import 'package:motoroute_app/features/routing/domain/route_entities.dart';
import '../data/pairing_repository.dart';

/// M3-Feature „Route am Computer planen": erzeugt Pairing-Token, zeigt einen
/// QR-Code mit dem Plan-Link (Handy-Kamera statt Abtippen) und übernimmt den
/// geplanten Entwurf mit „Plan abrufen" in die echte Wegpunkt-Liste der
/// App (waypointListProvider). Adaptiert aus dem neuen Codebasis-Stand auf
/// die Optik/Ebene dieser App (AppColors/AppTypography).
class ComputerPlanningSheet extends ConsumerStatefulWidget {
  const ComputerPlanningSheet({super.key, required this.repository});

  final PairingRepository repository;

  @override
  ConsumerState<ComputerPlanningSheet> createState() =>
      _ComputerPlanningSheetState();
}

class _ComputerPlanningSheetState extends ConsumerState<ComputerPlanningSheet> {
  PairingStart? _start;
  String? _error;
  bool _busy = false;
  bool _fetching = false;
  Timer? _poll;
  Timer? _expiry;
  DateTime? _expiresAt;

  @override
  void initState() {
    super.initState();
    _startPairing();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _expiry?.cancel();
    super.dispose();
  }

  Future<void> _startPairing() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final PairingStart start = await widget.repository.start();
      if (!mounted) return;
      setState(() {
        _start = start;
        _expiresAt = DateTime.now().add(
          Duration(seconds: start.expiresInSeconds),
        );
        _error = null;
      });
      _poll?.cancel();
      _expiry?.cancel();
      // Poll mit geschützter Einzelflug-Sperre bis Ablauf der Session.
      _poll = Timer.periodic(
          const Duration(seconds: 4), (_) => _fetchPlan(auto: true));
      _expiry = Timer(
        Duration(seconds: start.expiresInSeconds),
        () {
          if (!mounted) return;
          _poll?.cancel();
          setState(() =>
              _error = 'Der Plan-Link ist abgelaufen. Bitte neu starten.');
        },
      );
    } on PairingException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Pairing konnte nicht gestartet werden.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fetchPlan({bool auto = false}) async {
    final PairingStart? start = _start;
    if (start == null || _fetching) return;
    if (_expiresAt != null && !DateTime.now().isBefore(_expiresAt!)) {
      _poll?.cancel();
      if (mounted) {
        setState(
            () => _error = 'Der Plan-Link ist abgelaufen. Bitte neu starten.');
      }
      return;
    }
    _fetching = true;
    if (!auto && mounted) setState(() => _busy = true);
    try {
      final List<PairingPoint>? points =
          await widget.repository.fetchPlan(start.token);
      if (!mounted) return;
      if (points == null) {
        _poll?.cancel();
        if (!auto) setState(() => _error = 'Token unbekannt oder abgelaufen.');
        return;
      }
      if (points.isEmpty) {
        if (!auto && mounted) {
          setState(() => _error = 'Am Computer wurde noch nichts geplant.');
        }
        return;
      }
      _poll?.cancel();
      _expiry?.cancel();
      // Brücke in die alte App: die echten Wegpunkte der Touren-Liste.
      ref.read(waypointListProvider.notifier).state = points
          .map((p) => Waypoint(lat: p.lat, lng: p.lng, label: p.label))
          .toList(growable: false);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: context.palette.accentPrimary,
          content: Text('Route mit ${points.length} Punkten übernommen.'),
        ),
      );
      Navigator.of(context).pushNamed('/waypoints');
    } on PairingException catch (error) {
      if (mounted && !auto) setState(() => _error = error.message);
    } finally {
      _fetching = false;
      if (mounted && !auto) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final PairingStart? start = _start;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        // Scrollbar, damit QR+Link auch auf kleinen Displays inline passen.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Route am Computer planen',
                  style: AppTypography.title),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Am Computer bequemer tippen? Öffne den Link, plane dort — mit „Plan abrufen" landet die Route wieder hier.',
                style: AppTypography.captionOf(context),
              ),
              const SizedBox(height: AppSpacing.md),
              if (start != null) ...[
                Center(
                  child: Container(
                    width: 220,
                    height: 220,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: context.palette.bgSurfaceRaised,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: PrettyQrView.data(
                      data: start.planUrl,
                      errorCorrectLevel: QrErrorCorrectLevel.H,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Mit der Handy-Kamera scannen — der Plan-Editor öffnet sich im Browser.',
                  style: AppTypography.captionOf(context),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                SelectableText(start.planUrl,
                    style: AppTypography.title
                        .copyWith(color: context.palette.accentText)),
                if (start.planUrls.length > 1) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Weitere Adressen (z. B. Hotspot): ${start.planUrls.skip(1).join(' · ')}',
                    style: AppTypography.captionOf(context)
                        .copyWith(color: context.palette.textSecondary),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Text('Token: ${start.token}', style: AppTypography.captionOf(context)),
                const SizedBox(height: AppSpacing.md),
              ],
              if (_error != null)
                Text(_error!,
                    style: AppTypography.captionOf(context)
                        .copyWith(color: context.palette.statusDanger)),
              const SizedBox(height: AppSpacing.sm),
              FilledButton.icon(
                onPressed: _busy || start == null ? null : () => _fetchPlan(),
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                label: const Text('Plan abrufen'),
              ),
              const SizedBox(height: AppSpacing.sm),
              // App-zu-App: Wer selbst die Route EMPFANGEN will, scannt hier
              // den QR-Code der anderen App statt den Plan über das Backend
              // zu ziehen.
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pushNamed('/scan');
                },
                // Weiss auf der Teal-Flaeche kaeme nur auf 3,46:1; der
                // Primaertext des Schemas schafft im hellen Schema 5,29:1.
                style: FilledButton.styleFrom(
                    foregroundColor: context.palette.textPrimary),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Route von anderer App scannen'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: !_busy &&
                        (_start == null ||
                            _expiresAt == null ||
                            !DateTime.now().isBefore(_expiresAt!))
                    ? _startPairing
                    : null,
                child: const Text('Neuen Plan-Link erstellen'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Schließen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../application/location/location_providers.dart';
import '../../../../design/tokens/mr_colors.dart';
import '../../../../design/tokens/mr_theme.dart';
import '../../../../domain/repositories/location_repository.dart';

/// Status-Banner für Location-Berechtigung/Service (docs/06-ux-safety.md §5–6).
class GrantBanner extends ConsumerWidget {
  const GrantBanner({super.key, required this.grant});

  final LocationGrant grant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LocationGrantController controller =
        ref.read(locationGrantProvider.notifier);

    final IconData icon = switch (grant) {
      LocationGrant.granted => Icons.check_circle_outline,
      LocationGrant.serviceDisabled => Icons.location_off,
      LocationGrant.deniedForever => Icons.block,
      LocationGrant.denied => Icons.location_disabled,
      LocationGrant.undetermined => Icons.help_outline,
    };

    final String title = switch (grant) {
      LocationGrant.granted => 'Standort aktiv',
      LocationGrant.serviceDisabled => 'Standortdienste aus',
      LocationGrant.deniedForever => 'Berechtigung dauerhaft abgelehnt',
      LocationGrant.denied => 'Standort-Berechtigung fehlt',
      LocationGrant.undetermined => 'Standort-Status unklar',
    };

    final String body = switch (grant) {
      LocationGrant.granted => '',
      LocationGrant.serviceDisabled =>
        'Aktiviere den Standort in den Systemeinstellungen, damit MotoRoute dich führen kann.',
      LocationGrant.deniedForever =>
        'Ohne Berechtigung keine Navigation. In den App-Einstellungen aktivieren.',
      LocationGrant.denied =>
        'MotoRoute braucht den Standort für Turn-by-Turn-Guidance.',
      LocationGrant.undetermined =>
        'Wir konnten den Standort-Status nicht ermitteln. Bitte erneut versuchen.',
    };

    final String cta = switch (grant) {
      LocationGrant.granted => '',
      LocationGrant.serviceDisabled => 'Einstellungen öffnen',
      LocationGrant.deniedForever => 'App-Einstellungen öffnen',
      LocationGrant.denied => 'Berechtigung erteilen',
      LocationGrant.undetermined => 'Erneut prüfen',
    };

    return Material(
      color: MrColors.card,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(MrSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, color: MrColors.warning),
                const SizedBox(width: MrSpacing.sm),
                Expanded(child: Text(title, style: MrTypography.title)),
              ],
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: MrSpacing.xs),
              Text(body, style: MrTypography.body),
            ],
            if (cta.isNotEmpty) ...[
              const SizedBox(height: MrSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        if (grant == LocationGrant.serviceDisabled) {
                          await controller.openSettings();
                        } else {
                          await controller.requestWithRationale();
                        }
                      },
                      child: Text(cta),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

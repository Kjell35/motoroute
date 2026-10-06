import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../design/components/mr_logo.dart';
import '../../../design/tokens/mr_colors.dart';
import '../../../design/tokens/mr_theme.dart';

/// Splash (Screen 1 laut docs/06-ux-safety.md): Wortmarke + Init,
/// danach automatische Weiterleitung zur Karte.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // M0: keine echten Init-Schritte nötig (Kartenstil lädt im Map-Screen).
    // Ab M1: Berechtigungs-Precheck, Style-Cache-Warmup.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MrColors.base,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MrLogo(size: 96),
            const SizedBox(height: MrSpacing.md),
            const Text('MotoRoute', style: MrTypography.title),
            const SizedBox(height: MrSpacing.xs),
            Text(
              'Ride the fun way.',
              style: MrTypography.label.copyWith(color: MrColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

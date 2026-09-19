import 'package:flutter/material.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';

/// Screen 1: Splash - reines Markenmoment, < 1 Sekunde Zielwert.
/// Vollflächig bg/base, zentriertes Wortmarken-Logo, keine Ladebalken-
/// Animation. Leitet nach kurzer Fade-Zeit zur Karte weiter.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/onboarding');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'MOTOROUTE',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: AppColors.accentPrimaryDark,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('Fahrspaß statt nur ankommen', style: AppTypography.caption),
          ],
        ),
      ),
    );
  }
}

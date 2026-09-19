import 'package:flutter/material.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';

/// Screen 1: Splash - reines Markenmoment, < 1 Sekunde Zielwert.
/// Vollflächig bg/base; Wortmarke + Motorrad-Silhouette faden und
/// skalieren sanft ein, eine dünne Akzentlinie läuft als dezenter
/// Fortschritt. Navigation danach wie gehabt (Timer 900 ms - der
/// Widget-Test pumpt danach).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _scale = Tween<double>(begin: 0.86, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();

    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/onboarding');
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Motorrad-Silhouette im Akzent-Orbit: das Marken-symbol
                // vor dem Wort - "Fahrspaß" wird sofort sichtbar.
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accentPrimaryDark.withValues(alpha: 0.12),
                    border: Border.all(
                      color: AppColors.accentPrimaryDark.withValues(alpha: 0.35),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.two_wheeler,
                    size: 52,
                    color: AppColors.accentPrimaryDark,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'MOTOROUTE',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimaryDark,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text('Fahrspaß statt nur ankommen', style: AppTypography.caption),
                const SizedBox(height: AppSpacing.xxl),
                // Dünne Fortschrittslinie: hetzt nicht, zeigt aber Leben.
                SizedBox(
                  width: 132,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: const LinearProgressIndicator(
                      minHeight: 2,
                      backgroundColor: AppColors.bgSurfaceRaisedDark,
                      valueColor: AlwaysStoppedAnimation(AppColors.accentPrimaryDark),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

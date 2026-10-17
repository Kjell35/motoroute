import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../design/legacy/app_colors.dart';
import '../../../design/legacy/app_typography.dart';

/// Screen 1 (Look der v1.0.x-App): Markenmoment + Entscheider. Nach
/// Minimum 900 ms geht es beim ersten Start in Willkommen/Onboarding,
/// sonst direkt in die Tab-Shell. (Der Auth-Zweig der alten App ist hier
/// bewusst nicht aktiv — die neue Codebasis hat keine Anmeldung; „Look &
/// Start" wird 1:1 übernommen, Auth später.)
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
  bool _navigated = false;

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

    // Mindestdauer 900 ms (Marke + Test-Timing), dann EINMALIG weiterleiten.
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 900)).then(
        (_) => _navigateOnce(),
      ),
    );
  }

  Future<void> _navigateOnce() async {
    if (_navigated || !mounted) return;
    _navigated = true;
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboarding.done') ?? false;
    if (!mounted) return;
    if (!onboardingDone) {
      context.go('/welcome');
    } else {
      context.go('/home');
    }
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
                const Text(
                  'MOTOROUTE',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimaryDark,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text('Fahrspaß statt nur ankommen',
                    style: AppTypography.caption),
                const SizedBox(height: AppSpacing.xxl),
                SizedBox(
                  width: 132,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: const LinearProgressIndicator(
                      minHeight: 2,
                      backgroundColor: AppColors.bgSurfaceRaisedDark,
                      valueColor:
                          AlwaysStoppedAnimation(AppColors.accentPrimaryDark),
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

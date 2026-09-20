import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:motoroute_app/core/network/api_client.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';
import 'package:motoroute_app/features/auth/auth_providers.dart';

/// Screen 1: Splash - Markenmoment + Entscheider. Während der Animation
/// läuft parallel die Auth-Wiederherstellung; nach Minimum 900 ms und
/// abgeschlossenem Restore geht es zur Willkommens-/Login-Seite (nicht
/// angemeldet), ins Onboarding (erstes Starten) oder in die Tab-Shell
/// (angemeldet - die Shell begrüßt den Nutzer namentlich).
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  Future<void>? _restoreFuture;
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

    // Restore parallel zur Animation starten.
    _restoreFuture = ref.read(authControllerProvider.notifier).restore();

    // Kaltstart-Warmup: Die Free-Tier-Instanz des Backends schläft nach
    // ~15 min Leerlauf ein (30-60 s Aufwachzeit). Der Fire-and-Forget-
    // Ping weckt sie JETZT - während der Nutzer Begrüßung/Formular
    // sieht, ist der Server schon wach. Scheitern ist egal; der echte
    // Request hat zusätzlich den Auto-Retry.
    unawaited(_warmupServer());

    // Mindestdauer 900 ms (Marke + Test-Timing) UND Restore fertig,
    // dann EINMALIG weiterleiten (Navigation nie im Build auslösen).
    Future.wait([
      _restoreFuture!,
      Future<void>.delayed(const Duration(milliseconds: 900)),
    ]).then((_) => _navigateOnce());
  }

  /// Fire-and-Forget-Warmup (siehe initState). try/catch statt
  /// catchError: Bei Future<void> muss der catchError-Handler selbst
  /// void zurückgeben - eine lambda-Kurzfassung tut das nicht immer
  /// (ArgumentError im Test-Frame). So ist es eindeutig.
  Future<void> _warmupServer() async {
    try {
      await ApiClient.create().get<void>('/v1/health');
    } catch (_) {
      // Bewusst ignoriert - der Ping dient nur dem Aufwecken.
    }
  }

  Future<void> _navigateOnce() async {
    if (_navigated || !mounted) return;
    _navigated = true;

    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboarding.done') ?? false;
    final authenticated = ref.read(authControllerProvider).isAuthenticated;
    if (!mounted) return;

    if (!authenticated) {
      Navigator.of(context).pushReplacementNamed('/welcome');
    } else if (!onboardingDone) {
      Navigator.of(context).pushReplacementNamed('/onboarding');
    } else {
      Navigator.of(context).pushReplacementNamed('/home');
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

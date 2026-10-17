import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../design/legacy/app_colors.dart';
import '../../../design/legacy/app_typography.dart';

/// Willkommens-Moment wie in der v1.0.x-App — nur ohne die Anmelde-
/// Maske: Die neue Codebasis hat (noch) keine Auth, daher begrüßt
/// der Screen und führt an die Fahrspass-Start über „Los geht's"
/// Richtung Onboarding. Der optische Rahmen (Farben/Typo/Layout)
/// ist 1:1 aus dem v1.0.3-Stand übernommen.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 104,
                height: 104,
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
                  size: 56,
                  color: AppColors.accentPrimaryDark,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const Text(
                'Willkommen bei\nMotoRoute',
                textAlign: TextAlign.center,
                style: AppTypography.title,
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Fahrspaß statt nur ankommen — Routing nach Kurvigkeit, '
                'Belag und Charakter, nicht nur nach Distanz und Zeit.',
                textAlign: TextAlign.center,
                style: AppTypography.caption,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: AppSpacing.touchTargetPlanning,
                child: ElevatedButton(
                  onPressed: () => context.go('/onboarding'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentPrimaryDark,
                    foregroundColor: AppColors.textPrimaryLight,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Los geht\'s',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../application/route/route_preferences_provider.dart';
import '../../../design/legacy/app_colors.dart';
import '../../../design/legacy/app_typography.dart';
import '../../../domain/models/route_preferences.dart';

/// Screen 2 (v1.0.x-Look): 3 knappe Onboarding-Seiten. Seite 3 schreibt die
/// Fahrzeug-Auswahl direkt in den Routen-Präferenzen-Provider — die erste
/// Interaktion ist gleichzeitig schon Produktlogik. Ohne Auth-Bridge.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding.done', true);
    if (mounted) context.go('/home');
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  void _skip() {
    _finish();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _skip,
                child: const Text('Überspringen', style: AppTypography.caption),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _currentPage = index),
                children: [
                  _buildPage(
                    icon: Icons.explore_outlined,
                    title: 'Fahrspaß statt nur ankommen',
                    description:
                        'MotoRoute bewertet Straßen nach Kurvigkeit, Belag und Charakter - nicht nur nach Distanz und Zeit. Nimm die Route, die dir gefällt.',
                  ),
                  _buildPage(
                    icon: Icons.location_on_outlined,
                    title: 'Standort nur während Nutzung',
                    description:
                        'Wir nutzen deinen Standort nur für Routing und Kartenanzeige. Deine Position wird nicht dauerhaft serverseitig gespeichert.',
                  ),
                  _buildVehiclePage(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  3,
                  (index) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                    width: _currentPage == index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? AppColors.accentPrimaryDark
                          : AppColors.textMutedDark,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
              child: SizedBox(
                width: double.infinity,
                height: AppSpacing.touchTargetPlanning,
                child: ElevatedButton(
                  onPressed: _nextPage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentPrimaryDark,
                    foregroundColor: AppColors.textPrimaryLight,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    _currentPage < 2 ? 'Weiter' : 'Los geht\'s',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _buildPage({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: AppColors.accentPrimaryDark),
          const SizedBox(height: AppSpacing.xl),
          Text(title, textAlign: TextAlign.center, style: AppTypography.title),
          const SizedBox(height: AppSpacing.md),
          Text(
            description,
            textAlign: TextAlign.center,
            style: AppTypography.body,
          ),
        ],
      ),
    );
  }

  Widget _buildVehiclePage() {
    final VehicleType selected =
        ref.watch(routePreferencesProvider).vehicle;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.two_wheeler, size: 64, color: AppColors.accentPrimaryDark),
          const SizedBox(height: AppSpacing.xl),
          const Text('Womit fährst du?', style: AppTypography.title),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Legt das Routing-Verhalten fest - später in der Route-Planung jederzeit änderbar.',
            textAlign: TextAlign.center,
            style: AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.lg),
          ...VehicleType.values.map(
            (value) => RadioListTile<VehicleType>(
              value: value,
              groupValue: selected,
              onChanged: (value) => value != null
                  ? ref.read(routePreferencesProvider.notifier).setVehicle(value)
                  : null,
              title: Text(value.label, style: AppTypography.bodyStrong),
              activeColor: AppColors.accentPrimaryDark,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

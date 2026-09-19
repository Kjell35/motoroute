import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:motoroute_app/core/constants/route_enums.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';

/// Screen 2: Onboarding - 3 knappe Screens. (3) schreibt die Fahrzeug-
/// Auswahl direkt in den globalen Provider - die erste echte
/// Interaktion ist damit gleichzeitig schon Produktlogik.
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
    // Onboarding als erledigt markieren: Der Splash leitet beim
    // nächsten Start direkt in die Tab-Shell.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding.done', true);
    if (mounted) Navigator.of(context).pushReplacementNamed('/home');
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
                child: Text('Überspringen', style: AppTypography.caption),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          Text(title, style: AppTypography.title, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.md),
          Text(description, style: AppTypography.body, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildVehiclePage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.motorcycle, size: 64, color: AppColors.accentPrimaryDark),
          const SizedBox(height: AppSpacing.xl),
          Text('Fahrzeug wählen', style: AppTypography.title, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Motorrad, Auto oder Fahrrad - jedes Fahrzeug hat eigene Routing-Regeln. Welches soll dein Standard sein?',
            style: AppTypography.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          Consumer(builder: (context, ref, _) {
            final current = ref.watch(vehicleTypeProvider);
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final type in VehicleType.values) ...[
                  _buildVehicleChoice(ref, type, current == type),
                  const SizedBox(width: AppSpacing.md),
                ],
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildVehicleChoice(WidgetRef ref, VehicleType type, bool selected) {
    return GestureDetector(
      onTap: () => ref.read(vehicleTypeProvider.notifier).state = type,
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentPrimaryDark.withValues(alpha: 0.2)
              : AppColors.bgSurfaceDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.accentPrimaryDark : AppColors.borderHairlineDark,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              switch (type) {
                VehicleType.motorcycle => Icons.two_wheeler,
                VehicleType.car => Icons.directions_car,
                VehicleType.bicycle => Icons.pedal_bike,
              },
              color: selected ? AppColors.accentPrimaryDark : AppColors.textSecondaryDark,
              size: 32,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              switch (type) {
                VehicleType.motorcycle => 'Motorrad',
                VehicleType.car => 'Auto',
                VehicleType.bicycle => 'Fahrrad',
              },
              style: AppTypography.caption,
            ),
          ],
        ),
      ),
    );
  }
}

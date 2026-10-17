import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:go_router/go_router.dart';

import '../../../design/legacy/app_colors.dart';
import '../map/map_screen.dart';
import '../map_data/map_data_screen.dart';
import '../route/route_planner_screen.dart';

/// Tab-Shell adaptiert aus der v1.0.x-App: 4 Navigationspunkte + „Mehr"-
/// Sheet, IndexedStack hält die Screens alive (Karte überlebt Tab-Wechsel).
/// Statt Garage/Marktplatz/Chat führt der neue Stack die M0–M2-Funktionen:
/// Karte, Route-Planung, Kartendaten. Das M3-Scannen bleibt dezent als
/// Zugang im „Mehr"-Sheet („unsichtbar integriert").
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  void _openMoreSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.map_outlined,
                  color: AppColors.accentPrimaryDark, size: 28),
              title: const Text(
                'Kartendaten',
                style: TextStyle(
                  color: AppColors.textPrimaryDark,
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                ),
              ),
              trailing: const Icon(Icons.chevron_right,
                  color: AppColors.textSecondaryDark),
              onTap: () {
                Navigator.of(sheetContext).pop();
                setState(() => _tab = 3);
              },
            ),
            // M3-Funktion, dezenter Zugang („unsichtbar integriert").
            ListTile(
              leading: const Icon(Icons.qr_code_scanner,
                  color: AppColors.accentSecondary, size: 28),
              title: const Text(
                'Route scannen',
                style: TextStyle(
                  color: AppColors.textPrimaryDark,
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                ),
              ),
              trailing: const Icon(Icons.chevron_right,
                  color: AppColors.textSecondaryDark),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push('/scan');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      // IndexedStack wie in der v1.0.x-Shell: beide Tabs überleben den
      // Wechsel, Kamera/Stil der Karte laden nicht neu.
      body: IndexedStack(
        index: _tab,
        children: const [
          MapScreen(),
          RoutePlannerScreen(),
          SizedBox.shrink(), // Index 2 = „Mehr"-Sheet, kein eigener Screen
          MapDataScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.borderHairlineDark),
          ),
        ),
        child: NavigationBar(
          backgroundColor: AppColors.bgSurfaceDark,
          indicatorColor: AppColors.accentPrimaryDark.withValues(alpha: 0.22),
          height: 64,
          selectedIndex: _tab,
          onDestinationSelected: (index) {
            HapticFeedback.selectionClick();
            if (index == 2) {
              _openMoreSheet();
              return;
            }
            if (index != _tab) setState(() => _tab = index);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.map_outlined, color: AppColors.textSecondaryDark),
              selectedIcon: Icon(Icons.map, color: AppColors.accentPrimaryDark),
              label: 'Karte',
            ),
            NavigationDestination(
              icon: Icon(Icons.alt_route, color: AppColors.textSecondaryDark),
              selectedIcon:
                  Icon(Icons.alt_route, color: AppColors.accentPrimaryDark),
              label: 'Route',
            ),
            NavigationDestination(
              icon: Icon(Icons.apps, color: AppColors.textSecondaryDark),
              selectedIcon: Icon(Icons.apps, color: AppColors.accentPrimaryDark),
              label: 'Mehr',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined,
                  color: AppColors.textSecondaryDark),
              selectedIcon:
                  Icon(Icons.settings, color: AppColors.accentPrimaryDark),
              label: 'Einstellungen',
            ),
          ],
        ),
      ),
    );
  }
}

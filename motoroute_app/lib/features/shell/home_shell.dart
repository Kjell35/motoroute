import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/i18n/i18n.dart';
import 'package:motoroute_app/core/state/app_providers.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/features/auth/auth_providers.dart';
import 'package:motoroute_app/features/chat/chat_providers.dart';
import 'package:motoroute_app/features/chat/presentation/chat_hub_screen.dart';
import 'package:motoroute_app/features/map/presentation/map_screen.dart';
import 'package:motoroute_app/features/garage/garage_screen.dart';
import 'package:motoroute_app/features/marketplace/marketplace_screen.dart';
import 'package:motoroute_app/features/settings/settings_screen.dart';
import 'package:motoroute_app/features/waypoints/waypoint_management_screen.dart';

/// Tab-Shell: Karte, Marktplatz, Touren (Wegpunkt-Planung), Chat und
/// Einstellungen als echte Bottom-Navigation. IndexedStack hält alle
/// Screens alive - Karten- und Chat-Verbindungen überleben Tab-Wechsel.
class HomeShell extends ConsumerStatefulWidget {
  final int initialTab;

  const HomeShell({super.key, this.initialTab = 0});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late int _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab.clamp(0, 4);
    // Begrüßung beim Start (Anforderung: App begrüßt den Nutzer), nur
    // wenn eine Sitzung existiert - einmal pro Shell-Instanz.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = ref.read(authControllerProvider);
      if (auth.isAuthenticated) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            backgroundColor: AppColors.bgSurfaceRaisedDark,
            content: Text(
              'Moin zurück, ${auth.user?.name ?? 'Rider'}! 🏍️',
              style: const TextStyle(
                color: AppColors.textPrimaryDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Auth-Chat-Brücke am Leben halten (schreibt den Token in den Chat).
    ref.watch(authChatBridgeProvider);

    // In-App-"Benachrichtigung": Ungelesen-Badge am Chat-Tab. Der
    // Nutzer kann ihn in den Einstellungen abschalten - es gibt bewusst
    // keinen Google-Push-Dienst.
    final notifications = ref.watch(notificationsEnabledProvider);
    final totalUnread = ref.watch(chatOverviewProvider).totalUnread;
    final showChatBadge = notifications && totalUnread > 0;
    final i18n = ref.watch(i18nProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      body: IndexedStack(
        index: _tab,
        children: const [
          MapScreen(),
          MarketplaceScreen(),
          GarageScreen(),
          WaypointManagementScreen(),
          ChatHubScreen(),
          SettingsScreen(),
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
            if (index != _tab) {
              HapticFeedback.selectionClick();
            }
            setState(() => _tab = index);
          },
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.map_outlined, color: AppColors.textSecondaryDark),
              selectedIcon: const Icon(Icons.map, color: AppColors.accentPrimaryDark),
              label: i18n.mapTab,
            ),
            NavigationDestination(
              icon: const Icon(Icons.storefront_outlined, color: AppColors.textSecondaryDark),
              selectedIcon: const Icon(Icons.storefront, color: AppColors.accentPrimaryDark),
              label: i18n.marketplaceTab,
            ),
            NavigationDestination(
              icon: const Icon(Icons.garage_outlined, color: AppColors.textSecondaryDark),
              selectedIcon: const Icon(Icons.garage, color: AppColors.accentPrimaryDark),
              label: i18n.garageTab,
            ),
            NavigationDestination(
              icon: const Icon(Icons.route_outlined, color: AppColors.textSecondaryDark),
              selectedIcon: const Icon(Icons.route, color: AppColors.accentPrimaryDark),
              label: i18n.toursTab,
            ),
            NavigationDestination(
              icon: showChatBadge
                  ? Badge(
                      label: Text('$totalUnread'),
                      backgroundColor: AppColors.statusDanger,
                      child: const Icon(Icons.forum_outlined, color: AppColors.textSecondaryDark),
                    )
                  : const Icon(Icons.forum_outlined, color: AppColors.textSecondaryDark),
              selectedIcon: const Icon(Icons.forum, color: AppColors.accentPrimaryDark),
              label: i18n.chatTab,
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined, color: AppColors.textSecondaryDark),
              selectedIcon: const Icon(Icons.settings, color: AppColors.accentPrimaryDark),
              label: i18n.settingsTab,
            ),
          ],
        ),
      ),
    );
  }
}

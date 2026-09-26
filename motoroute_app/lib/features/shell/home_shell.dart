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

/// Tab-Shell: 4 Navigationspunkte - Home (Karte), Garage, "Mehr" (Sheet
/// mit Marktplatz/Touren/Chat) und Einstellungen. IndexedStack hält alle
/// Screens alive - Karten- und Chat-Verbindungen überleben Tab-Wechsel.
class HomeShell extends ConsumerStatefulWidget {
  final int initialTab;

  const HomeShell({super.key, this.initialTab = 0});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late int _tab;

  /// Index in der 4-Punkt-Navigationsleiste für den aktuellen Stack-Tab.
  int get _navIndex => switch (_tab) {
    0 => 0, // Karte -> Home
    2 => 1, // Garage
    1 || 3 || 4 => 2, // Marktplatz/Touren/Chat -> "Mehr"
    _ => 3, // Einstellungen
  };

  /// "Mehr"-Sheet: Marktplatz, Touren und Chat als große Touch-Ziele.
  void _openMoreSheet() {
    final i18n = ref.read(i18nProvider);
    final notif = ref.read(notificationsEnabledProvider);
    final unread = ref.read(chatOverviewProvider).totalUnread;
    final chatBadge = notif && unread > 0;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            for (final entry in [
              (1, Icons.storefront, i18n.marketplaceTab),
              (3, Icons.route, i18n.toursTab),
              (4, Icons.forum, i18n.chatTab),
            ])
              ListTile(
                leading: Icon(entry.$2, color: AppColors.accentPrimaryDark, size: 28),
                title: Text(
                  entry.$3,
                  style: const TextStyle(
                    color: AppColors.textPrimaryDark,
                    fontWeight: FontWeight.w600,
                    fontSize: 17,
                  ),
                ),
                trailing: entry.$1 == 4 && chatBadge
                    ? Badge(
                        label: Text('$unread'),
                        backgroundColor: AppColors.statusDanger,
                      )
                    : const Icon(Icons.chevron_right, color: AppColors.textSecondaryDark),
                onTap: () {
                  Navigator.of(context).pop();
                  if (_tab != entry.$1) setState(() => _tab = entry.$1);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab.clamp(0, 5);
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
          // Navigationsleiste hat 4 Punkte; die Stack-Indizes 1 (Markt-
          // platz), 3 (Touren) und 4 (Chat) werden über das "Mehr"-Sheet
          // erreicht und highlighten ebenfalls den "Mehr"-Punkt.
          selectedIndex: _navIndex,
          onDestinationSelected: (index) {
            HapticFeedback.selectionClick();
            if (index == 2) {
              _openMoreSheet();
              return;
            }
            final target = switch (index) {
              0 => 0, // Home -> Karte
              1 => 2, // Garage
              _ => 5, // Einstellungen
            };
            if (target != _tab) setState(() => _tab = target);
          },
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.map_outlined, color: AppColors.textSecondaryDark),
              selectedIcon: const Icon(Icons.map, color: AppColors.accentPrimaryDark),
              label: i18n.mapTab,
            ),
            NavigationDestination(
              icon: const Icon(Icons.garage_outlined, color: AppColors.textSecondaryDark),
              selectedIcon: const Icon(Icons.garage, color: AppColors.accentPrimaryDark),
              label: i18n.garageTab,
            ),
            NavigationDestination(
              icon: showChatBadge
                  ? Badge(
                      label: Text('$totalUnread'),
                      backgroundColor: AppColors.statusDanger,
                      child: const Icon(Icons.apps, color: AppColors.textSecondaryDark),
                    )
                  : const Icon(Icons.apps, color: AppColors.textSecondaryDark),
              selectedIcon: const Icon(Icons.apps, color: AppColors.accentPrimaryDark),
              label: i18n.moreTab,
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

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
import 'package:motoroute_app/features/tour_diary/presentation/tour_diary_screen.dart';
import 'package:motoroute_app/features/garage/garage_screen.dart';
import 'package:motoroute_app/features/marketplace/marketplace_screen.dart';
import 'package:motoroute_app/features/settings/settings_screen.dart';

/// Tab-Shell: Karte, Touren, Garage, Community und Einstellungen.
/// IndexedStack hält die Hauptbereiche beim Tab-Wechsel.
class HomeShell extends ConsumerStatefulWidget {
  final int initialTab;

  const HomeShell({super.key, this.initialTab = 0});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late int _tab;

  /// Index in der Hauptnavigation für den aktuellen Bereich.
  int get _navIndex => switch (_tab) {
        0 => 0, // Karte
        3 => 1, // Touren
        2 => 2, // Garage
        1 || 4 => 3, // Community
        _ => 4, // Einstellungen
      };

  /// Community-Menü: Marktplatz, Chat, Routenplanung und Badges.
  void _openMoreSheet() {
    final i18n = ref.read(i18nProvider);
    final notif = ref.read(notificationsEnabledProvider);
    final unread = ref.read(chatOverviewProvider).totalUnread;
    final chatBadge = notif && unread > 0;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurfaceDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.stateIdleDark,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Deine Community',
                    style: TextStyle(
                        color: AppColors.textPrimaryDark,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 8),
              for (final entry in [
                (1, Icons.storefront, i18n.marketplaceTab),
                (4, Icons.forum, i18n.chatTab),
                (6, Icons.emoji_events, i18n.tr('badges.shelfEntry')),
              ])
                ListTile(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color:
                          AppColors.accentPrimaryDark.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(entry.$2,
                        color: AppColors.accentPrimaryDark, size: 24),
                  ),
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
                      : const Icon(Icons.arrow_forward_ios_rounded,
                          size: 16, color: AppColors.textSecondaryDark),
                  onTap: () {
                    Navigator.of(context).pop();
                    if (entry.$1 == 6) {
                      Navigator.of(this.context).pushNamed('/badges');
                    } else if (_tab != entry.$1) {
                      setState(() => _tab = entry.$1);
                    }
                  },
                ),
              // M3-Feature, dezenter Zugang: Route von anderer App scannen.
              ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.accentSecondary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.qr_code_scanner,
                      color: AppColors.accentSecondary, size: 24),
                ),
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
                  Navigator.of(context).pop();
                  Navigator.of(context).pushNamed('/scan');
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
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
    // Auth-Chat-Brücke bereits am Shell-Start aktivieren, bevor ein Chat-
    // oder Marktplatz-Tab im IndexedStack seinen Auth-State auswertet.
    ref.watch(authChatBridgeProvider);
    final auth = ref.watch(authControllerProvider);
    final token = ref.watch(chatSessionTokenProvider);
    if (auth.isAuthenticated && token == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final current = ref.read(authControllerProvider);
        ref.read(chatSessionTokenProvider.notifier).state =
            current.isAuthenticated
                ? ref.read(authControllerProvider.notifier).accessToken
                : null;
      });
    }

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
          TourDiaryScreen(),
          ChatHubScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bgSurfaceDark.withValues(alpha: 0.98),
            border: const Border(
              top: BorderSide(color: AppColors.borderHairlineDark),
            ),
          ),
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            indicatorColor: AppColors.accentPrimaryDark.withValues(alpha: 0.16),
            height: 70,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            selectedIndex: _navIndex,
            onDestinationSelected: (index) {
              HapticFeedback.selectionClick();
              if (index == 3) {
                _openMoreSheet();
                return;
              }
              final target = switch (index) {
                0 => 0,
                1 => 3,
                2 => 2,
                _ => 5,
              };
              if (target != _tab) setState(() => _tab = target);
            },
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.explore_outlined),
                selectedIcon: const Icon(Icons.explore),
                label: i18n.mapTab,
              ),
              NavigationDestination(
                icon: const Icon(Icons.route_outlined),
                selectedIcon: const Icon(Icons.route),
                label: i18n.toursTab,
              ),
              NavigationDestination(
                icon: const Icon(Icons.two_wheeler_outlined),
                selectedIcon: const Icon(Icons.two_wheeler),
                label: i18n.garageTab,
              ),
              NavigationDestination(
                icon: showChatBadge
                    ? Badge(
                        label: Text('$totalUnread'),
                        backgroundColor: AppColors.statusDanger,
                        child: const Icon(Icons.grid_view_rounded),
                      )
                    : const Icon(Icons.grid_view_rounded),
                selectedIcon: const Icon(Icons.grid_view_rounded),
                label: i18n.moreTab,
              ),
              const NavigationDestination(
                icon: Icon(Icons.tune_rounded),
                selectedIcon: Icon(Icons.tune_rounded),
                label: 'Konto',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

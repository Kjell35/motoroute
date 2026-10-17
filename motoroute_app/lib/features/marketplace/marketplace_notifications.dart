import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'marketplace_repository.dart';

/// In-App-Benachrichtigungen für Verkäufer: jemand hat dein Angebot
/// gemerkt, gemeldet oder bewertet. Polling statt Push-Dienst - die App
/// bleibt frei von Google Play Services (bewusste Architektur-Entscheidung
/// aus Phase "Keine Abhängigkeit vom Play Store").
///
/// Poll-Intervall 60 s: aktiviert sich nur, wenn eine Auth-Sitzung
/// existiert; ohne Anmeldung läuft kein Timer. Das Badge an der
/// Marketplace-Inbox liest [unreadCountProvider].
class MarketplaceNotificationsController
    extends StateNotifier<MpNotifications> {
  final Ref _ref;
  Timer? _timer;
  String? _lastToken;

  MarketplaceNotificationsController(this._ref) : super(const MpNotifications(items: [], unread: 0)) {
    // Auf Token-Wechsel reagieren (Login/Logout).
    _ref.listen<String?>(marketplaceTokenProvider, (_, token) {
      _syncTimer(token);
      if (token != null) refresh(token);
    });
    final initial = _ref.read(marketplaceTokenProvider);
    _syncTimer(initial);
    if (initial != null) refresh(initial);
  }

  void _syncTimer(String? token) {
    if (token == _lastToken) return;
    _lastToken = token;
    _timer?.cancel();
    if (token == null) {
      state = const MpNotifications(items: [], unread: 0);
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => refresh(token));
  }

  Future<void> refresh(String token) async {
    try {
      final data = await _ref
          .read(marketplaceRepositoryProvider)
          .notifications(token: token);
      if (_ref.read(marketplaceTokenProvider) != token) return;
      state = data;
    } catch (_) {
      // Netz-Fehler still ignorieren - nächster Poll versucht es erneut.
    }
  }

  /// Alles gelesen markieren + State sofort spiegeln (Badge verschwindet).
  Future<void> markAllRead() async {
    final token = _ref.read(marketplaceTokenProvider);
    if (token == null) return;
    try {
      await _ref.read(marketplaceRepositoryProvider).markNotificationsRead(token: token);
      state = MpNotifications(
        items: state.items
            .map((n) => MpNotification(
                  id: n.id,
                  type: n.type,
                  body: n.body,
                  readAt: n.readAt ?? DateTime.now().toIso8601String(),
                  createdAt: n.createdAt,
                  actor: n.actor,
                  listingTitle: n.listingTitle,
                ))
            .toList(growable: false),
        unread: 0,
      );
    } catch (_) {
      // Beim nächsten Poll konsistieren.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final marketplaceNotificationsProvider =
    StateNotifierProvider<MarketplaceNotificationsController, MpNotifications>(
  (ref) => MarketplaceNotificationsController(ref),
);

/// Kurz-Handle für Badges (Shell + Inbox).
final unreadCountProvider = Provider<int>(
  (ref) => ref.watch(marketplaceNotificationsProvider).unread,
);

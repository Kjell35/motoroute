import 'dart:async';

import 'package:flutter/widgets.dart';

import 'api_client.dart';

/// Hält das Render-Free-Tier-Backend WACH, solange die App im Vordergrund
/// ist. Hintergrund: GitHub-Actions-Crons werden von GitHub massiv
/// verzögert (Beobachtung: statt alle 5 min nur alle 3-6 Stunden) - der
/// Server schläft dadurch ständig ein und die App zeigt beim ersten
/// Request "Verbindung prüfen" (30-60 s Kaltstart).
///
/// Dieser Timer pingt alle 4 MINUTEN /v1/health (unter der 15-min-
/// Schlaf-Schwelle, mit reichlich Puffer). Das ist bewusst UNabhängig
/// von der Session: Auch auf dem Login-Screen bleibt der Server wach.
///
/// Akku-Bilanz: Ein 200-Byte-Request alle 4 min ist vernachlässigbar;
/// im Hintergrund (App minimiert) stoppt der Timer komplett
/// (didChangeAppLifecycleState), es läuft also NICHTs im Standby weiter.
class ServerKeepAlive with WidgetsBindingObserver {
  ServerKeepAlive._();
  static final instance = ServerKeepAlive._();

  Timer? _timer;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _ping();
    _timer = Timer.periodic(const Duration(minutes: 4), (_) => _ping());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Nur im VORDERGRUND pingen - minimiert/gesperrt kein Traffic.
    if (state == AppLifecycleState.resumed) {
      _ping(); // sofort nach Rückkehr (weckt ggf. auf, bevor der Nutzer tippt)
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(minutes: 4), (_) => _ping());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _ping() async {
    try {
      await ApiClient.create().get<void>('/v1/health');
    } catch (_) {
      // Bewusst ignoriert - der Ping dient nur dem Aufwecken.
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
    _started = false;
  }
}

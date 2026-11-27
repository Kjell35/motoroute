import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pairing_repository.dart';

/// Laufender Pairing-Vorgang („Route am Computer planen").
///
/// Der Token lebt bewusst in einem Provider und nicht im Dialog-State: sonst
/// stirbt der Vorgang, sobald der Dialog geschlossen wird, und ein danach am
/// Rechner gespeicherter Plan wäre verwaist. Beim erneuten Öffnen wird die
/// Session wiederverwendet, bis sie abläuft.
///
/// Nicht auf Platte persistiert: der Token ist ein kurzlebiges Geheimnis
/// (2 Stunden) und soll einen App-Neustart nicht überleben.
class PairingSessionState {
  const PairingSessionState({this.start, this.expiresAt});

  final PairingStart? start;
  final DateTime? expiresAt;

  /// Token vorhanden und noch nicht abgelaufen.
  bool get isActive {
    final DateTime? until = expiresAt;
    final PairingStart? current = start;
    return current != null && until != null && DateTime.now().isBefore(until);
  }

  /// Noch gültige Restlaufzeit in Sekunden (0, wenn abgelaufen/leer).
  int get remainingSeconds {
    final DateTime? until = expiresAt;
    if (until == null) return 0;
    final int seconds = until.difference(DateTime.now()).inSeconds;
    return seconds > 0 ? seconds : 0;
  }
}

class PairingSessionController extends StateNotifier<PairingSessionState> {
  PairingSessionController() : super(const PairingSessionState());

  /// Merkt sich einen frisch gestarteten Vorgang samt Ablaufzeitpunkt.
  void remember(PairingStart start) {
    state = PairingSessionState(
      start: start,
      expiresAt: DateTime.now().add(Duration(seconds: start.expiresInSeconds)),
    );
  }

  /// Nach der Übernahme oder wenn der Plan abgelaufen ist.
  void clear() => state = const PairingSessionState();
}

final pairingSessionProvider =
    StateNotifierProvider<PairingSessionController, PairingSessionState>(
  (ref) => PairingSessionController(),
);

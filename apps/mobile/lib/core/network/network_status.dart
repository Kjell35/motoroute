import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Hat das Geraet eine Netz-Schnittstelle (WLAN, Mobilfunk, LAN, VPN)?
///
/// Bewusst nur die Schnittstelle: eine echte Erreichbarkeitspruefung macht
/// der Chat selbst ueber seinen Socket. Ein Captive Portal zaehlt hier also
/// als "online" - dort faellt dann die Socket-Meldung an.
bool connectivityHasNetwork(List<ConnectivityResult> results) => results.any(
      (r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.vpn,
    );

/// Aktueller Netz-Zustand aus connectivity_plus (Schnittstelle vorhanden
/// oder nicht), inklusive spaeterer Umschaltungen.
final networkOnlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  yield connectivityHasNetwork(await connectivity.checkConnectivity());
  await for (final results in connectivity.onConnectivityChanged) {
    yield connectivityHasNetwork(results);
  }
});

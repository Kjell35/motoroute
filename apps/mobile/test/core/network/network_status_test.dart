import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/core/network/network_status.dart';

/// Das Chat-Banner soll "kein Internet" nur sagen, wenn wirklich keine
/// Schnittstelle da ist - diese Zuordnung entscheidet darueber.
void main() {
  test('kein Ergebnis bzw. nur "none" heisst offline', () {
    expect(connectivityHasNetwork(const []), isFalse);
    expect(connectivityHasNetwork(const [ConnectivityResult.none]), isFalse);
  });

  test('WLAN, Mobilfunk, LAN und VPN zaehlen als online', () {
    expect(connectivityHasNetwork(const [ConnectivityResult.wifi]), isTrue);
    expect(connectivityHasNetwork(const [ConnectivityResult.mobile]), isTrue);
    expect(connectivityHasNetwork(const [ConnectivityResult.ethernet]), isTrue);
    expect(connectivityHasNetwork(const [ConnectivityResult.vpn]), isTrue);
  });

  test('eine vorhandene Schnittstelle genuegt, auch neben "none"', () {
    expect(
      connectivityHasNetwork(
          const [ConnectivityResult.none, ConnectivityResult.wifi]),
      isTrue,
    );
  });

  test('Bluetooth allein ist kein Internet', () {
    expect(connectivityHasNetwork(const [ConnectivityResult.bluetooth]),
        isFalse);
  });
}

import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Energiesparmodus (Phase 1/2 Abschnitt 12, Phase 3 Screen 11,
/// Sprint 11 des MVP-Plans): während der aktiven Navigation GPS-
/// Abfragefrequenz und Genauigkeit drosseln, damit Lange Strecken
/// nicht am Akku scheitern.
///
/// Drei Stufen:
/// - aus: volle Genauigkeit (Standard)
/// - on: reduzierte Genauigkeit + größerer Distanz-Filter
/// - critical: GPS praktisch stillgelegt (gröbster Filter, min.
///   Updates) + Verhalten im UI offensiv gemeldet - ab dieser Stufe
///   ist verlässliche Off-Route-Erkennung NICHT mehr garantiert.
enum EnergySaverMode { off, on, critical }

class EnergySaverState {
  final EnergySaverMode mode;
  final int batteryLevelPercent;
  final bool isMonitoringBattery;

  const EnergySaverState({
    this.mode = EnergySaverMode.off,
    this.batteryLevelPercent = 100,
    this.isMonitoringBattery = false,
  });

  EnergySaverState copyWith({
    EnergySaverMode? mode,
    int? batteryLevelPercent,
    bool? isMonitoringBattery,
  }) =>
      EnergySaverState(
        mode: mode ?? this.mode,
        batteryLevelPercent: batteryLevelPercent ?? this.batteryLevelPercent,
        isMonitoringBattery: isMonitoringBattery ?? this.isMonitoringBattery,
      );
}

class EnergySaverController extends StateNotifier<EnergySaverState> {
  final Battery _battery;
  StreamSubscription<BatteryState>? _batterySubscription;
  Timer? _criticalDebounce;

  /// Broadcast-Stream aller Modus-Wechsel - der Navigation-Controller
  /// abonniert ihn, um den GPS-Stream live umzustellen (riverpod 2.x
  /// hat kein listenManual auf Ref; ein eigener Stream ist robust und
  /// schichtenisoliert).
  final StreamController<EnergySaverMode> _modeChanges =
      StreamController<EnergySaverMode>.broadcast();

  Stream<EnergySaverMode> get modeChanges => _modeChanges.stream;

  EnergySaverController(this._battery) : super(const EnergySaverState());

  /// GPS-Parameter für den LocationRepository-Lookup - wird vom
  /// Navigation-Controller beim Stream-Aufbau gelesen. Der Controller
  /// selbst kennt kein geolocator (Isolation der Schichten).
  LocationTuning get locationTuning => switch (state.mode) {
        EnergySaverMode.off =>
          const LocationTuning(accuracy: LocationAccuracyPreset.high, distanceFilterMeters: 3),
        EnergySaverMode.on => const LocationTuning(
            accuracy: LocationAccuracyPreset.medium, distanceFilterMeters: 15),
        EnergySaverMode.critical => const LocationTuning(
            accuracy: LocationAccuracyPreset.low, distanceFilterMeters: 50),
      };

  /// Vom Settings-Screen (Screen 11) getoggelt.
  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      state = state.copyWith(mode: EnergySaverMode.on);
      _modeChanges.add(EnergySaverMode.on);
      await _startBatteryMonitoring();
    } else {
      _stopBatteryMonitoring();
      state = state.copyWith(mode: EnergySaverMode.off);
      _modeChanges.add(EnergySaverMode.off);
    }
  }

  Future<void> _startBatteryMonitoring() async {
    if (state.isMonitoringBattery) return;
    try {
      state = state.copyWith(batteryLevelPercent: await _battery.batteryLevel);
    } catch (_) {
      // battery_plus auf Plattform ohne Akku-Zugriff (Desktop/Test):
      // Sparmodus bleibt manuell ein/ausschaltbar, nur ohne Auto-Stufen.
    }
    state = state.copyWith(isMonitoringBattery: true);
    _batterySubscription?.cancel();
    _batterySubscription = _battery.onBatteryStateChanged.listen(_onBatteryState);
  }

  void _stopBatteryMonitoring() {
    _batterySubscription?.cancel();
    _batterySubscription = null;
    _criticalDebounce?.cancel();
    _criticalDebounce = null;
    state = state.copyWith(isMonitoringBattery: false);
  }

  void _onBatteryState(BatteryState batteryState) {
    // Auto-Stufe NUR wenn der Modus bewusst eingeschaltet wurde: Ein
    // Ladegerät-Anschluss darf den manuell ausgeschalteten Sparmodus
    // nicht einschalten (und umgekehrt).
    if (state.mode == EnergySaverMode.off) return;

    Future<void> update() async {
      try {
        final level = await _battery.batteryLevel;
        final previousMode = state.mode;
        if (batteryState == BatteryState.charging) {
          // Am Lader: volle Genauigkeit ist wieder zulässig.
          state = state.copyWith(
            batteryLevelPercent: level,
            mode: state.mode == EnergySaverMode.critical
                ? EnergySaverMode.on
                : state.mode,
          );
        } else if (level <= 15) {
          // Debounce: Akkustand-Messungen können kurz schwanken.
          _criticalDebounce?.cancel();
          _criticalDebounce = Timer(const Duration(seconds: 10), () {
            state = state.copyWith(
              batteryLevelPercent: level,
              mode: EnergySaverMode.critical,
            );
          });
        } else {
          state = state.copyWith(batteryLevelPercent: level);
        }
        if (previousMode != state.mode) _modeChanges.add(state.mode);
      } catch (_) {
        // Messung fehlgeschlagen: nichts tun, Modus bleibt.
      }
    }
    update();
  }

  @override
  void dispose() {
    _batterySubscription?.cancel();
    _criticalDebounce?.cancel();
    _modeChanges.close();
    super.dispose();
  }
}

/// GPS-Parameter-Set, das der LocationRepository-Konsumiert - als
/// eigener Typ statt geolocator-Enums, damit core/ nicht von
/// geolocator abhängt (Schichten-Isolation).
enum LocationAccuracyPreset { high, medium, low }

class LocationTuning {
  final LocationAccuracyPreset accuracy;
  final int distanceFilterMeters;

  const LocationTuning({
    required this.accuracy,
    required this.distanceFilterMeters,
  });
}

final energySaverControllerProvider =
    StateNotifierProvider<EnergySaverController, EnergySaverState>((ref) {
  return EnergySaverController(Battery());
});

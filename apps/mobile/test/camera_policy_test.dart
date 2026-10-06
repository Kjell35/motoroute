import 'package:flutter_test/flutter_test.dart';

import 'package:motoroute/domain/services/camera_policy.dart';

void main() {
  group('CameraPolicy', () {
    const CameraPolicy policy = CameraPolicy();

    test('kleine Pan-Bewegung bleibt im Follow-Modus', () {
      final CameraDecision d =
          policy.onUserPan(panDistanceMeters: 10);
      expect(d.mode, CameraMode.follow);
      expect(d.shouldAnimate, isFalse);
    });

    test('große Pan-Bewegung wechselt in den manuellen Modus', () {
      final CameraDecision d =
          policy.onUserPan(panDistanceMeters: 50);
      expect(d.mode, CameraMode.manual);
    });

    test('exakt an der Schwelle (35 m) wechselt in manual', () {
      final CameraDecision d =
          policy.onUserPan(panDistanceMeters: 35);
      expect(d.mode, CameraMode.manual);
    });

    test('Recenter-Tap geht zurück in follow mit Animation', () {
      final CameraDecision d = policy.onRecenterTap();
      expect(d.mode, CameraMode.follow);
      expect(d.shouldAnimate, isTrue);
    });

    test('Navigation startet immer im Follow-Modus', () {
      expect(policy.onNavigationStarted().mode, CameraMode.follow);
    });
  });
}

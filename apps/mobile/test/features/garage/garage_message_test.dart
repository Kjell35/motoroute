import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/garage/garage_screen.dart';

/// Die Garage meldet Fehler an zwei Stellen (Liste und Anlegen-Dialog).
/// Beide muessen denselben Text zeigen, sonst sieht der Nutzer je nach
/// Einstieg eine rohe Exception oder eine verstaendliche Meldung.
void main() {
  const loginFailed = 'Anmeldung abgelaufen';
  const unreachable = 'Server nicht erreichbar';

  test('401 aus der Garage-API wird zur Anmelde-Meldung', () {
    final e = Exception(
        'GarageApiException(401): {"error":"token_expired"}');
    expect(
      garageMessageFor(e, loginFailed: loginFailed, unreachable: unreachable),
      loginFailed,
    );
  });

  test('AUTH-Kennung wird ebenfalls als Anmeldeproblem behandelt', () {
    final e = Exception('GarageApiException(403): AUTH_SCOPE');
    expect(
      garageMessageFor(e, loginFailed: loginFailed, unreachable: unreachable),
      loginFailed,
    );
  });

  test('Andere Fehler bekommen die Server-Meldung, ohne Stacktrace', () {
    final e = Exception('GarageApiException(500): kaputt\n#0 mehr Zeilen');
    final msg =
        garageMessageFor(e, loginFailed: loginFailed, unreachable: unreachable);
    expect(msg, startsWith(unreachable));
    expect(msg, contains('GarageApiException(500): kaputt'));
    expect(msg, isNot(contains('#0')));
  });

  test('Bereits formatierte Meldungen ohne GarageException bleiben lesbar', () {
    final msg = garageMessageFor(
      StateError('kein Netz'),
      loginFailed: loginFailed,
      unreachable: unreachable,
    );
    expect(msg, startsWith(unreachable));
    expect(msg, contains('kein Netz'));
  });
}

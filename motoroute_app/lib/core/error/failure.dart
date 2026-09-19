/// Fehler-Hierarchie für Repository-Aufrufe. Bewusst eigene Typen statt
/// rohe Exceptions/DioException nach oben durchzureichen, damit die
/// Presentation-Schicht (Riverpod-Controller) nie wissen muss, dass Dio
/// überhaupt existiert - siehe Architekturvorgabe "keine unnötige
/// Vermischung" aus Phase 1/2, Abschnitt 16.
sealed class Failure {
  final String message;
  const Failure(this.message);
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Keine Verbindung zum Server']);
}

class RoutingFailure extends Failure {
  const RoutingFailure(super.message);
}

class UnexpectedFailure extends Failure {
  const UnexpectedFailure([super.message = 'Unerwarteter Fehler']);
}

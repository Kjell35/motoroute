enum VehicleType { car, motorcycle, bicycle }

enum RideStyle { fast, curvy, extraCurvy, fastAndCurvy }

enum RouteAvoidance { highway, ferry, toll, unpaved, cycleway }

extension VehicleTypeLabel on VehicleType {
  String get label => switch (this) {
        VehicleType.car => 'Auto',
        VehicleType.motorcycle => 'Motorrad',
        VehicleType.bicycle => 'Fahrrad',
      };
}

extension RideStyleLabel on RideStyle {
  String get label => switch (this) {
        RideStyle.fast => 'Schnell',
        RideStyle.curvy => 'Kurvig',
        RideStyle.extraCurvy => 'Extra kurvig',
        RideStyle.fastAndCurvy => 'Schnell & kurvig',
      };
}

extension RouteAvoidanceLabel on RouteAvoidance {
  String get label => switch (this) {
        RouteAvoidance.highway => 'Autobahn',
        RouteAvoidance.ferry => 'Fähren',
        RouteAvoidance.toll => 'Mautstraßen',
        RouteAvoidance.unpaved => 'Unbefestigte Straßen',
        RouteAvoidance.cycleway => 'Fahrradwege',
      };
}

/// Präferenzen reisen mit jedem Routing-Request und werden nicht getrackt.
class RoutePreferences {
  const RoutePreferences({
    this.vehicle = VehicleType.motorcycle,
    this.rideStyle = RideStyle.fastAndCurvy,
    this.avoidances = const {},
  });

  final VehicleType vehicle;
  final RideStyle rideStyle;
  final Set<RouteAvoidance> avoidances;

  RoutePreferences copyWith({
    VehicleType? vehicle,
    RideStyle? rideStyle,
    Set<RouteAvoidance>? avoidances,
  }) => RoutePreferences(
        vehicle: vehicle ?? this.vehicle,
        rideStyle: rideStyle ?? this.rideStyle,
        avoidances: avoidances ?? this.avoidances,
      );
}

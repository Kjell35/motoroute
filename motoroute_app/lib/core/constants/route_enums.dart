/// Spiegelt exakt die Enums aus dem Backend
/// (motoroute_api/src/modules/routing/dto/create-route.dto.ts) -
/// bewusst als eigene Datei statt verstreut in Widgets, damit Backend
/// und App nie unbemerkt auseinanderlaufen (z. B. bei einem neuen
/// Fahrstil müssen beide Seiten geändert werden, aber an klar
/// auffindbarer Stelle).

enum VehicleType { motorcycle, car, bicycle }

enum RouteStyle { fast, curvy, extraCurvy, fastAndCurvy, unpaved }

enum AvoidOption { highway, ferry, toll }

extension VehicleTypeApi on VehicleType {
  String get apiValue => switch (this) {
        VehicleType.motorcycle => 'MOTORCYCLE',
        VehicleType.car => 'CAR',
        VehicleType.bicycle => 'BICYCLE',
      };
}

extension RouteStyleApi on RouteStyle {
  String get apiValue => switch (this) {
        RouteStyle.fast => 'FAST',
        RouteStyle.curvy => 'CURVY',
        RouteStyle.extraCurvy => 'EXTRA_CURVY',
        RouteStyle.fastAndCurvy => 'FAST_AND_CURVY',
        RouteStyle.unpaved => 'UNPAVED',
      };
}

extension AvoidOptionApi on AvoidOption {
  String get apiValue => switch (this) {
        AvoidOption.highway => 'HIGHWAY',
        AvoidOption.ferry => 'FERRY',
        AvoidOption.toll => 'TOLL',
      };
}

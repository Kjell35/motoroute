import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/group_routes/group_route_repository.dart';

void main() {
  group('GroupRouteStatus (Abschnitt 15)', () {
    test('parst alle Statuswerte aus dem DB-Constraint', () {
      expect(groupRouteStatusFrom('planning'), GroupRouteStatus.planning);
      expect(groupRouteStatusFrom('final'), GroupRouteStatus.finalized);
      expect(groupRouteStatusFrom('riding'), GroupRouteStatus.riding);
      expect(groupRouteStatusFrom('completed'), GroupRouteStatus.completed);
      expect(groupRouteStatusFrom('locked'), GroupRouteStatus.locked);
      expect(groupRouteStatusFrom(null), GroupRouteStatus.planning);
    });

    test("apiValue schreibt 'final' zurück (DB-Constraint)", () {
      expect(GroupRouteStatus.finalized.apiValue, 'final');
    });
  });

  group('EditingPermission (Abschnitt 4)', () {
    test('owner_only und all_members', () {
      expect(editingPermissionFrom('owner_only'), EditingPermission.ownerOnly);
      expect(editingPermissionFrom('all_members'), EditingPermission.allMembers);
      // Defensiv: unbekannt -> restriktiv wäre falsch; Default ist offen,
      // da der Server ohnehin entscheidet (Abschnitt 32).
      expect(editingPermissionFrom(null), EditingPermission.allMembers);
    });
  });

  group('StopCategory', () {
    test('alle 7 Kategorien mit Label', () {
      expect(stopCategoryFrom('fuel'), StopCategory.fuel);
      expect(stopCategoryFrom('moto_hotel'), StopCategory.motoHotel);
      expect(stopCategoryFrom('biker_meetup'), StopCategory.bikerMeetup);
      expect(stopCategoryFrom('ice_cream'), StopCategory.iceCream);
      expect(stopCategoryFrom('viewpoint'), StopCategory.viewpoint);
      expect(stopCategoryFrom('campsite'), StopCategory.campsite);
      expect(stopCategoryFrom('other').label, '📍 Stopp');
    });
  });

  group('GroupRoute.fromJson', () {
    test('parst alle Spalten inkl. Metriken und Version', () {
      final r = GroupRoute.fromJson({
        'id': 'r1',
        'group_id': 'g1',
        'created_by': 'u1',
        'name': 'Alpenrunde',
        'status': 'planning',
        'editing_permission': 'all_members',
        'start_lat': 48.14,
        'start_lng': 11.58,
        'dest_lat': 47.42,
        'dest_lng': 11.07,
        'vehicle_type': 'MOTORCYCLE',
        'routing_style': 'EXTRA_CURVY',
        'avoid_highways': true,
        'avoid_ferries': true,
        'avoid_tolls': true,
        'distance_meters': 245000,
        'duration_seconds': 13200,
        'curve_score': 92,
        'version': 7,
      });
      expect(r.name, 'Alpenrunde');
      expect(r.routingStyle, 'EXTRA_CURVY');
      expect(r.avoidHighways, isTrue);
      expect(r.curveScore, 92);
      expect(r.version, 7);
    });
  });

  group('GroupRouteDetail.fromJson', () {
    test('parst Route + sortierte Stopps + Verlauf', () {
      final d = GroupRouteDetail.fromJson({
        'route': {
          'id': 'r1',
          'group_id': 'g1',
          'created_by': 'u1',
          'name': 'Alpenrunde',
          'start_lat': 48.14,
          'start_lng': 11.58,
          'dest_lat': 47.42,
          'dest_lng': 11.07,
        },
        'stops': [
          {
            'id': 's2',
            'route_id': 'r1',
            'position': 1,
            'lat': 48.2,
            'lng': 11.5,
            'name': 'Tankstelle Shell',
            'category': 'fuel',
            'created_by': 'u2',
            'created_at': '2026-09-18T10:00:00Z',
          },
        ],
        'history': [
          {
            'action': 'stop_added',
            'detail': 'Tankstelle Shell',
            'created_at': '2026-09-18T10:00:00Z',
            'users': {'display_name': 'Lisa'},
          },
        ],
      });
      expect(d.stops.first.category, StopCategory.fuel);
      expect(d.history.first.userName, 'Lisa');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/chat/data/chat_repository.dart';

void main() {
  group('ChatUser.fromJson', () {
    test('parst alle Felder inkl. display_name-Kette', () {
      final user = ChatUser.fromJson({
        'id': 'u1',
        'username': 'maxrider',
        'display_name': 'Max',
        'avatar_url': null,
        'vehicle_desc': 'BMW R1250GS',
      });
      expect(user.effectiveName, 'Max');
      expect(user.vehicleDesc, 'BMW R1250GS');
    });

    test('Fallback auf „Biker“ ohne Namen (Abschnitt 3)', () {
      final user = ChatUser.fromJson({'id': 'u1'});
      expect(user.effectiveName, 'Biker');
    });
  });

  group('ChatMessage.fromJson', () {
    test('parst snake_case-Felder und eingebetteten Sender', () {
      final msg = ChatMessage.fromJson({
        'id': 'm1',
        'conversation_id': 'c1',
        'sender_id': 'u1',
        'content': 'Hallo 👋',
        'created_at': '2026-09-18T10:00:00Z',
        'sender': {'id': 'u1', 'display_name': 'Max'},
      });
      expect(msg.content, 'Hallo 👋');
      expect(msg.isDeleted, isFalse);
      expect(msg.sender?.effectiveName, 'Max');
    });

    test('Soft-Delete (Abschnitt 21): deleted_at -> isDeleted', () {
      final msg = ChatMessage.fromJson({
        'id': 'm1',
        'conversation_id': 'c1',
        'sender_id': 'u1',
        'content': '',
        'deleted_at': '2026-09-18T11:00:00Z',
        'created_at': '2026-09-18T10:00:00Z',
      });
      expect(msg.isDeleted, isTrue);
    });
  });

  group('ConversationSummary', () {
    test('parst Typ, Rolle, Unread-Zähler', () {
      final c = ConversationSummary.fromJson({
        'id': 'c1',
        'type': 'group',
        'role': 'owner',
        'group': {'name': 'Alpen Tour 2026'},
        'unreadCount': 5,
      });
      expect(c.type, ConversationType.group);
      expect(c.role, 'owner');
      expect(c.unreadCount, 5);
      expect(c.group?['name'], 'Alpen Tour 2026');
    });
  });

  group('ChatAttachment (Abschnitt 38: Route/Standort teilen)', () {
    test('Route-Attachment mit Kurven-Score', () {
      final a = ChatAttachment.route(
        name: 'Alpenrunde',
        distanceKm: 245,
        durationSeconds: 13200,
        curvyScore: 92,
      );
      expect(a['type'], 'route');
      expect(a['curvyScore'], 92);
      expect(a['distanceKm'], 245);
    });

    test('Standort-Attachment', () {
      final a = ChatAttachment.location(lat: 47.42, lng: 11.07, label: 'Treffpunkt');
      expect(a['type'], 'location');
      expect(a['lat'], 47.42);
    });
  });
}

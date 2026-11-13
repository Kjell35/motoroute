import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/error_reporter.dart';
import 'chat_repository.dart';

/// Eine Nachricht, die nicht rausging und auf die naechste Verbindung wartet.
class PendingChatMessage {
  final String localId;
  final String conversationId;
  final String text;
  final DateTime queuedAt;

  const PendingChatMessage({
    required this.localId,
    required this.conversationId,
    required this.text,
    required this.queuedAt,
  });

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'conversationId': conversationId,
        'text': text,
        'queuedAt': queuedAt.toIso8601String(),
      };

  factory PendingChatMessage.fromJson(Map<String, dynamic> json) =>
      PendingChatMessage(
        localId: json['localId'] as String? ?? '',
        conversationId: json['conversationId'] as String? ?? '',
        text: json['text'] as String? ?? '',
        queuedAt: DateTime.tryParse(json['queuedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// Warteschlange fuer fehlgeschlagene Chat-Nachrichten.
///
/// Sie liegt in shared_preferences und ueberlebt damit App-Neustarts: was
/// offline getippt wurde, geht nicht verloren, sondern wird gesendet, sobald
/// die Verbindung steht.
class ChatOutbox extends StateNotifier<List<PendingChatMessage>> {
  ChatOutbox({SharedPreferences? prefs}) : _prefs = prefs, super(const []);

  static const storageKey = 'chat.outbox.v1';

  SharedPreferences? _prefs;
  bool _flushing = false;

  /// Laedt den gespeicherten Stand (App-Start bzw. erster Zugriff).
  Future<void> load() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => PendingChatMessage.fromJson(e.cast<String, dynamic>()))
          .where((m) => m.conversationId.isNotEmpty && m.text.isNotEmpty)
          .toList();
      state = list;
    } catch (e) {
      ErrorReporter.instance.report('chat.outbox.load', e);
      // Ein kaputter Stand darf die Warteschlange nicht dauerhaft blockieren.
      await prefs.remove(storageKey);
    }
  }

  /// Wartende Nachrichten einer Unterhaltung (fuer die Anzeige im Chat).
  List<PendingChatMessage> forConversation(String conversationId) => state
      .where((m) => m.conversationId == conversationId)
      .toList(growable: false);

  Future<void> enqueue(String conversationId, String text) async {
    if (text.trim().isEmpty) return;
    final message = PendingChatMessage(
      localId:
          '${DateTime.now().microsecondsSinceEpoch}-${conversationId.hashCode}',
      conversationId: conversationId,
      text: text,
      queuedAt: DateTime.now(),
    );
    state = [...state, message];
    await _save();
  }

  Future<void> remove(String localId) async {
    state = state.where((m) => m.localId != localId).toList(growable: false);
    await _save();
  }

  /// Versucht, alle wartenden Nachrichten zu senden.
  ///
  /// Gibt zurueck, wie viele tatsaechlich rausgingen. Beim ersten Fehlschlag
  /// wird abgebrochen: ohne Verbindung bringt der naechste Versuch nichts,
  /// er kommt beim naechsten Reconnect. Gesendete Nachrichten werden erst
  /// entfernt, nachdem der Server sie bestaetigt hat.
  Future<int> flush(ChatRepository repo, String token) async {
    if (_flushing || state.isEmpty) return 0;
    _flushing = true;
    var sent = 0;
    try {
      for (final message in [...state]) {
        try {
          await repo.send(token, message.conversationId, message.text);
          sent += 1;
          await remove(message.localId);
        } catch (e) {
          ErrorReporter.instance.report('chat.outbox.flush', e);
          break;
        }
      }
    } finally {
      _flushing = false;
    }
    return sent;
  }

  Future<void> _save() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setString(
        storageKey, jsonEncode(state.map((m) => m.toJson()).toList()));
  }
}

final chatOutboxProvider =
    StateNotifierProvider<ChatOutbox, List<PendingChatMessage>>((ref) {
  final outbox = ChatOutbox();
  // Laden beim ersten Zugriff; die UI zeigt den Stand, sobald er da ist.
  outbox.load();
  return outbox;
});

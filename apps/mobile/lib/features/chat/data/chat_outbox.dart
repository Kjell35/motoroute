import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/error_reporter.dart';
import 'chat_repository.dart';

/// Wie lange nach dem Einreihen eine schon angekommene Nachricht noch als
/// dieselbe gilt. Handy- und Serveruhr gehen selten gleich, deshalb ein
/// Fenster statt eines exakten Zeitpunkts.
const chatOutboxDeliveryWindow = Duration(minutes: 2);

/// Eine Nachricht, die nicht rausging und auf die naechste Verbindung wartet.
class PendingChatMessage {
  final String localId;
  final String conversationId;
  final String text;
  final DateTime queuedAt;

  /// Wie oft senden schon versucht wurde. Alles ueber 0 heisst: der Versuch
  /// kann beim Server angekommen sein, nur die Antwort ging verloren.
  final int attempts;

  final DateTime? lastAttemptAt;

  const PendingChatMessage({
    required this.localId,
    required this.conversationId,
    required this.text,
    required this.queuedAt,
    this.attempts = 0,
    this.lastAttemptAt,
  });

  PendingChatMessage copyWith({int? attempts, DateTime? lastAttemptAt}) =>
      PendingChatMessage(
        localId: localId,
        conversationId: conversationId,
        text: text,
        queuedAt: queuedAt,
        attempts: attempts ?? this.attempts,
        lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      );

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'conversationId': conversationId,
        'text': text,
        'queuedAt': queuedAt.toIso8601String(),
        'attempts': attempts,
        'lastAttemptAt': lastAttemptAt?.toIso8601String(),
      };

  factory PendingChatMessage.fromJson(Map<String, dynamic> json) =>
      PendingChatMessage(
        localId: json['localId'] as String? ?? '',
        conversationId: json['conversationId'] as String? ?? '',
        text: json['text'] as String? ?? '',
        queuedAt: DateTime.tryParse(json['queuedAt'] as String? ?? '') ??
            DateTime.now(),
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        lastAttemptAt: DateTime.tryParse(json['lastAttemptAt'] as String? ?? ''),
      );
}

/// Warteschlange fuer fehlgeschlagene Chat-Nachrichten.
///
/// Sie liegt in shared_preferences und ueberlebt damit App-Neustarts: was
/// offline getippt wurde, geht nicht verloren, sondern wird gesendet, sobald
/// die Verbindung steht.
///
/// Doppelte Nachrichten verhindert die Warteschlange selbst: bevor eine
/// Nachricht erneut rausgeht, deren letzter Versuch unbekannt ausging, wird
/// die Historie der Unterhaltung geprueft. Steht die Nachricht dort schon,
/// wird der Eintrag verworfen statt ein zweites Mal gesendet.
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

  /// [attempted] setzt den Zaehler auf 1: die Nachricht wurde schon einmal
  /// losgeschickt und kam nicht bestaetigt zurueck.
  Future<void> enqueue(String conversationId, String text,
      {bool attempted = false}) async {
    if (text.trim().isEmpty) return;
    final message = PendingChatMessage(
      localId:
          '${DateTime.now().microsecondsSinceEpoch}-${conversationId.hashCode}',
      conversationId: conversationId,
      text: text,
      queuedAt: DateTime.now(),
      attempts: attempted ? 1 : 0,
      lastAttemptAt: attempted ? DateTime.now() : null,
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
  /// Gibt zurueck, wie viele tatsaechlich rausgingen (ohne die, die schon
  /// angekommen waren). Beim ersten Fehlschlag wird abgebrochen: ohne
  /// Verbindung bringt der naechste Versuch nichts, er kommt beim naechsten
  /// Reconnect. [myUserId] aktiviert die Pruefung gegen die Historie; ohne
  /// sie wird wie vorher gesendet, nie still verworfen.
  Future<int> flush(ChatRepository repo, String token,
      {String? myUserId}) async {
    if (_flushing || state.isEmpty) return 0;
    _flushing = true;
    var sent = 0;
    // Einmal pro Unterhaltung laden, nicht pro Nachricht.
    final history = <String, List<ChatMessage>>{};
    try {
      for (final message in [...state]) {
        if (message.attempts > 0 && myUserId != null) {
          final delivered = await _alreadyDelivered(
              repo, token, message, myUserId, history);
          if (delivered) {
            // Kam beim Server an, nur die Antwort ging verloren.
            await remove(message.localId);
            continue;
          }
        }
        try {
          await repo.send(token, message.conversationId, message.text);
          sent += 1;
          await remove(message.localId);
        } catch (e) {
          ErrorReporter.instance.report('chat.outbox.flush', e);
          await _bumpAttempts(message.localId);
          break;
        }
      }
    } finally {
      _flushing = false;
    }
    return sent;
  }

  /// Steht diese Nachricht schon in der Historie? Nur dann darf sie nicht
  /// noch einmal rausgehen.
  Future<bool> _alreadyDelivered(
    ChatRepository repo,
    String token,
    PendingChatMessage message,
    String myUserId,
    Map<String, List<ChatMessage>> history,
  ) async {
    var messages = history[message.conversationId];
    if (messages == null) {
      try {
        final page = await repo.messages(token, message.conversationId,
            limit: 30);
        messages = page.messages;
        history[message.conversationId] = messages;
      } catch (e) {
        // Keine Historie heisst keine Aussage: dann lieber erneut senden
        // (das Verhalten von vorher) als die Nachricht still zu verlieren.
        ErrorReporter.instance.report('chat.outbox.reconcile', e);
        return false;
      }
    }
    final text = message.text.trim();
    final notBefore = message.queuedAt.subtract(chatOutboxDeliveryWindow);
    for (final existing in messages) {
      if (existing.senderId != myUserId) continue;
      if (existing.content.trim() != text) continue;
      final created = DateTime.tryParse(existing.createdAt);
      if (created != null && created.isBefore(notBefore)) continue;
      return true;
    }
    return false;
  }

  Future<void> _bumpAttempts(String localId) async {
    final now = DateTime.now();
    state = [
      for (final message in state)
        message.localId == localId
            ? message.copyWith(
                attempts: message.attempts + 1, lastAttemptAt: now)
            : message,
    ];
    await _save();
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

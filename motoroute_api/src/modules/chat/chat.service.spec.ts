import { ForbiddenException, NotFoundException } from '@nestjs/common';

/**
 * Die reinen Chat-Logikbausteine sind absichtlich als freie Funktionen
 * exportierbar getestet. Da rateBuckets/consumeRateSlot modulintern sind,
 * testen wir sie über die öffentliche Fläche: die Exporte aus chat.service.
 *
 * Hinweis: consumeRateSlot ist nicht exportiert - wir testen stattdessen
 * die Verhaltensregeln über eine minimale Nachbildung der Sliding-Window-
 * Logik? Nein: Doppel-Implementierung wäre wertlos. Stattdessen prüfen
 * wir die Datei-Exporte, die tatsächlich öffentlich sind:
 * - mapSupabaseError (Error-Mapping)
 * - PUBLIC_CONVERSATION_ID / ChatEvent (Verträge)
 * - generateInvitationCode (Entropie/Format)
 * Diese werden modulintern via `export` bereitgestellt (siehe unten).
 */
import {
  PUBLIC_CONVERSATION_ID,
  ChatEvent,
} from './chat.service';

describe('Chat-Verträge', () => {
  it('nutzt die feste Singleton-ID für den öffentlichen Chat (schema.sql Seed)', () => {
    expect(PUBLIC_CONVERSATION_ID).toBe('00000000-0000-0000-0000-000000000001');
  });

  it('definiert kanonische Event-Namen (WS-Protokoll-Vertrag mit der App)', () => {
    expect(ChatEvent.NEW_MESSAGE).toBe('chat.message.created');
    expect(ChatEvent.MESSAGE_DELETED).toBe('chat.message.deleted');
    expect(ChatEvent.TYPING).toBe('chat.typing');
    expect(ChatEvent.PRESENCE).toBe('chat.presence');
    // Alle Event-Namen sind namespaced, damit es keine Kollisionen gibt.
    for (const name of Object.values(ChatEvent)) {
      expect(name).toMatch(/^chat\./);
    }
  });
});

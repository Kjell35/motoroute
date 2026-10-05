/**
 * Automatische KI-Moderation fuer den Chat (Nutzeranforderung: "eine
 * automatische KI, welche unangemessenes Verhalten bemerkt").
 *
 * Ablauf nach jeder gesendeten Nachricht (post-hoc, NICHT blockierend):
 *  1. Gemini (Flash) bewertet den Nachrichtentext.
 *  2. Bei klarem Verstoss (Beleidigung, Hass, Spam, Belaestigung) wird
 *     die Nachricht serverseitig als geloescht markiert (Tombstone) und
 *     ein Meldungs-Eintrag in `reports` erzeugt.
 *  3. Der Meldende ist die KI selbst; die Konvention reporter_id ==
 *     reported_user_id markiert einen Eintrag als KI-Meldung - so bleibt
 *     das Schema unveraendert und der Admin-Filter "nur echte
 *     Nutzer-Meldungen" ist ein einfacher Vergleich (siehe
 *     adminListReports).
 *
 * Fehler degradieren still: Moderation ist ein Sicherheitsnetz, kein
 * Gate. Schlägt Gemini fehl, bleibt die Nachricht einfach stehen.
 * Rate-Limit: pro Nutzer max. 1 Gemini-Call je 30 s - Kosten bleiben
 * minimal (Flash ist günstig), Missbrauch ausgeschlossen.
 */

import { Inject, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SupabaseClient } from '@supabase/supabase-js';
import axios from 'axios';
import { SUPABASE_CLIENT } from '../../supabase/supabase.module';

const GEMINI_MODEL = 'gemini-1.5-flash';
const GEMINI_TIMEOUT_MS = 15_000;

/** Mindestabstand zwischen zwei KI-Pruefungen desselben Nutzers. */
const PER_USER_COOLDOWN_MS = 30_000;

const MODERATION_PROMPT = [
  'You are a content moderator for a motorcycle rider community chat app.',
  'Judge the following chat message. Flag it ONLY when you are confident it',
  'violates community rules: insults directed at people, hate speech,',
  'discrimination, threats, sexual harassment, or obvious spam/scams',
  '(ads, phishing links). Rudeness, crude jokes or swearing that is not',
  'directed at a person is NOT a violation. Answer with JSON only:',
  '{"violation": true | false, "category": "insult" | "harassment" | "hate" | "spam" | "inappropriate" | "none",',
  '"excerpt": "<short quote of the offending part, max 100 chars>", "explanation": "<one short German sentence>"}',
].join('\n');

export interface ModerationVerdict {
  violation: boolean;
  category: string;
  excerpt?: string;
  explanation?: string;
}

@Injectable()
export class ChatModerationService {
  private readonly logger = new Logger(ChatModerationService.name);
  private readonly apiKey: string | null;
  private readonly lastCheck = new Map<string, number>();

  constructor(
    config: ConfigService,
    // Service-Role-Client: Moderation wirkt serverseitig (Loeschen +
    // reports-Insert), unabhaengig von RLS des Verfassers.
    @Inject(SUPABASE_CLIENT) private readonly adminClient: SupabaseClient | null,
  ) {
    const key = config.get<string>('GEMINI_API_KEY');
    this.apiKey = key && key.length >= 20 ? key : null;
  }

  get configured(): boolean {
    return this.apiKey != null;
  }

  /**
   * Prueft eine gerade gesendete Nachricht. Wirft NIE - Fehler enden als
   * Log-Eintrag, die Nachricht bleibt unangetastet.
   */
  async reviewMessage(params: {
    messageId: string;
    senderId: string;
    conversationId: string;
    content: string;
  }): Promise<void> {
    if (!this.apiKey || !this.adminClient) return;
    if (params.content.trim().length < 8) return; // Kurzmsgs ("ok", "lol") nicht pruefen

    // Cooldown pro Verfasser: mehrfache SendMessage-Events (Retries,
    // Fanout) nicht mehrfach pruefen.
    const last = this.lastCheck.get(params.senderId) ?? 0;
    if (Date.now() - last < PER_USER_COOLDOWN_MS) return;
    this.lastCheck.set(params.senderId, Date.now());

    let verdict: ModerationVerdict | null = null;
    try {
      verdict = await this.askGemini(params.content);
    } catch (err) {
      this.logger.warn(`KI-Moderation fehlgeschlagen: ${axios.isAxiosError(err) ? err.message : err}`);
      return;
    }
    if (!verdict?.violation) return;

    await this.hideMessage(params, verdict);
  }

  private async askGemini(content: string): Promise<ModerationVerdict | null> {
    const res = await axios.post(
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${this.apiKey}`,
      {
        contents: [{ parts: [{ text: `${MODERATION_PROMPT}\n\nMessage: ${content.slice(0, 2000)}` }] }],
        generationConfig: { temperature: 0, responseMimeType: 'application/json' },
      },
      { timeout: GEMINI_TIMEOUT_MS },
    );
    const text: string | undefined = res.data?.candidates?.[0]?.content?.parts
      ?.map((p: { text?: string }) => p.text ?? '')
      .join('');
    if (!text) return null;
    const parsed = JSON.parse(text.trim()) as ModerationVerdict;
    return {
      violation: parsed.violation === true,
      category: typeof parsed.category === 'string' ? parsed.category : 'none',
      excerpt: parsed.excerpt,
      explanation: parsed.explanation,
    };
  }

  /** Nachricht verstecken (Tombstone) + KI-Meldung (reporter == reported). */
  private async hideMessage(
    params: { messageId: string; senderId: string; conversationId: string },
    verdict: ModerationVerdict,
  ): Promise<void> {
    const db = this.adminClient!;
    const details = [
      verdict.explanation ?? null,
      verdict.excerpt ? `Auszug: "${verdict.excerpt.slice(0, 100)}"` : null,
      'automatisch erkannt',
    ]
      .filter(Boolean)
      .join(' · ');

    const { error: upErr } = await db
      .from('messages')
      .update({ content: '', attachment: null, deleted_at: new Date().toISOString() })
      .eq('id', params.messageId);
    if (upErr) {
      this.logger.warn(`KI-Moderation: Verstecken fehlgeschlagen: ${upErr.message}`);
      return;
    }

    // KI-Meldung: reporter == reported markiert den Eintrag als KI-Ergebnis
    // (Schema unveraendert - reason ist Enum-konform).
    const { error: repErr } = await db.from('reports').insert({
      reporter_id: params.senderId,
      reported_user_id: params.senderId,
      message_id: params.messageId,
      reason: ['insult', 'harassment', 'inappropriate', 'spam'].includes(verdict.category)
        ? verdict.category
        : 'inappropriate',
      details: `KI-Moderation · ${details}`,
    });
    if (repErr) {
      this.logger.warn(`KI-Moderation: Meldung fehlgeschlagen: ${repErr.message}`);
    } else {
      this.logger.log(`KI-Moderation: Nachricht ${params.messageId} versteckt (${verdict.category})`);
    }
  }
}

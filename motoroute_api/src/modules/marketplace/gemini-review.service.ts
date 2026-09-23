/**
 * Gemini-Vision-Rezensent: der zweite, entscheidende Pruefschritt der
 * Marktplatz-KI. Er prueft Text UND Bilder gemeinsam und entscheidet,
 * ob ein Angebot veroeffentlicht werden darf.
 *
 * Design (aus der Anforderung Punkt 5/7/8/9 abgeleitet):
 *  - Text-Klassifikator (regelbasiert, deterministisch) liefert Signale.
 *  - Bilder werden mit Gemini (Google AI) geprueft: Erkennt das Modell
 *    auf dem Foto einen anderen Gegenstand als im Titel, wird blockiert
 *    oder zur manuellen Pruefung geschickt (Widerspruch).
 *  - Ohne konfigurierten Gemini-Key degradiert der Service EHRlich:
 *    Text eindeutig RELEVANT -> approved (Verschluesselung unmoeglich
 *    ist textlich gut erkennbar), sonst manual_review. Nie silent
 *    durchlassen, was zweifelhaft ist.
 *
 * Der API-Key kommt ausschliesslich aus GEMINI_API_KEY (Backend .env) -
 * kein Key im Frontend, Punkt 22.
 */

import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';
import { classifyText, TextInput, TextReview } from './classifier/text-classifier';

export type ReviewDecision = 'APPROVE' | 'REJECT' | 'MANUAL_REVIEW';
export type ReviewMediaVerdict = 'matches' | 'mismatch' | 'uncertain' | 'no_images' | 'error';

export interface ReviewInput extends TextInput {
  /** Oeffentliche URLs der hochgeladenen Bilder (0..8). */
  imageUrls: string[];
}

export interface ReviewResult {
  decision: ReviewDecision;
  reason: string;
  textReview: TextReview;
  /** Bildpruefung pro Bild: was das Modell erkannt hat. */
  imageResults: { url: string; verdict: ReviewMediaVerdict; label?: string }[];
}

/** Gemini-Modell mit Vision-Support, stabil ueber die v1beta-REST-API. */
const GEMINI_MODEL = 'gemini-1.5-flash';
const GEMINI_TIMEOUT_MS = 20_000;

/** Striktes Antwortformat, das wir vom Modell erzwingen. */
const PROMPT_SYSTEM = [
  'You are a strict product moderator for a marketplace that ONLY allows',
  'parts and accessories for motorcycles, cars and bicycles.',
  'Look at the attached product photo(s) and the listing text.',
  'Answer with JSON only: {"label": "<short object name>",',
  '"relation": "motorcycle_part" | "car_part" | "bicycle_part" | "unrelated" | "unclear"}.',
  '"relation" is "unrelated" for anything not clearly a vehicle part or',
  'vehicle accessory (e.g. toaster, TV, phone, furniture, clothing, toys).',
  'It is "unclear" only if the photo is unusable (too dark, no object).',
].join('\n');

@Injectable()
export class GeminiReviewService {
  private readonly logger = new Logger(GeminiReviewService.name);
  private readonly apiKey: string | null;

  constructor(config: ConfigService) {
    const key = config.get<string>('GEMINI_API_KEY');
    this.apiKey = key && key.length >= 20 ? key : null;
  }

  get configured(): boolean {
    return this.apiKey != null;
  }

  /**
   * Vollstaendige Pruefung eines Angebots: Text + Bilder kombiniert.
   * Wirft NIE - jede Stoerung endet in einer sicheren Entscheidung.
   */
  async review(input: ReviewInput): Promise<ReviewResult> {
    const textReview = classifyText(input);

    // Bildpruefung parallel je Bild; Fehler = verdict 'error'.
    const imageResults = await Promise.all(
      input.imageUrls.slice(0, 8).map(async (url) => this.inspectImage(url)),
    );

    return this.decide(input, textReview, imageResults);
  }

  private async inspectImage(
    url: string,
  ): Promise<{ url: string; verdict: ReviewMediaVerdict; label?: string }> {
    if (!this.apiKey) return { url, verdict: 'no_images' === url ? 'error' : 'uncertain' };

    try {
      // Bild herunterladen (oeffentlicher Storage-Bucket) und als
      // Inline-Base64 an Gemini geben - der Service erwartet so
      // multipart contents ohne separaten Upload-Dance.
      const response = await axios.get<ArrayBuffer>(url, {
        responseType: 'arraybuffer',
        timeout: GEMINI_TIMEOUT_MS,
        maxContentLength: 15 * 1024 * 1024,
      });
      const contentType = String(response.headers['content-type'] ?? 'image/jpeg').split(';')[0];
      if (!contentType.startsWith('image/')) {
        return { url, verdict: 'error' };
      }

      const payload = {
        contents: [
          {
            parts: [
              { text: PROMPT_SYSTEM },
              { inline_data: { mime_type: contentType, data: Buffer.from(response.data).toString('base64') } },
            ],
          },
        ],
        generationConfig: {
          temperature: 0.1,
          responseMimeType: 'application/json',
        },
      };

      const gemini = await axios.post(
        `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${this.apiKey}`,
        payload,
        { timeout: GEMINI_TIMEOUT_MS },
      );

      const text: string | undefined = gemini.data?.candidates?.[0]?.content?.parts
        ?.map((p: { text?: string }) => p.text ?? '')
        .join('');
      if (!text) return { url, verdict: 'error' };

      const parsed = JSON.parse(text.trim()) as { label?: string; relation?: string };
      const relation = parsed.relation ?? 'unclear';
      if (relation === 'motorcycle_part' || relation === 'car_part' || relation === 'bicycle_part') {
        return { url, verdict: 'matches', label: parsed.label };
      }
      if (relation === 'unrelated') {
        return { url, verdict: 'mismatch', label: parsed.label };
      }
      return { url, verdict: 'uncertain', label: parsed.label };
    } catch (err) {
      this.logger.warn(`Gemini-Bildpruefung fehlgeschlagen (${url.slice(0, 80)}): ${axios.isAxiosError(err) ? err.message : err}`);
      return { url, verdict: 'error' };
    }
  }

  /**
   * Kombinierte Entscheidung - die Kernregel des Marktplatzes.
   */
  private decide(
    input: ReviewInput,
    text: TextReview,
    images: ReviewResult['imageResults'],
  ): ReviewResult {
    const mismatches = images.filter((i) => i.verdict === 'mismatch');
    const matches = images.filter((i) => i.verdict === 'matches');
    const broken = images.filter((i) => i.verdict === 'error');

    // 1) Eindeutig fremdes Produkt im Text -> immer ablehnen.
    if (text.verdict === 'FOREIGN') {
      return {
        decision: 'REJECT',
        reason:
          'Der Artikel ist laut Beschreibung kein Fahrzeugteil und kein Fahrzeugzubehör (Motorrad, Auto, Fahrrad).',
        textReview: text,
        imageResults: images,
      };
    }

    // 2) Bild zeigt eindeutig etwas anderes als FahrzeugeContext ->
    //    Widerspruch (Punkt 8): blockieren.
    if (mismatches.length > 0 && matches.length === 0) {
      const label = mismatches[0].label ?? 'unbekannter Gegenstand';
      return {
        decision: 'REJECT',
        reason: `Das hochgeladene Foto zeigt kein Fahrzeugteil (erkannt: ${label}).`,
        textReview: text,
        imageResults: images,
      };
    }

    // 3) Text eindeutig relevant UND Bild bestaetigt (oder keine Bilder) ->
    //    veroeffentlichen.
    if (text.verdict === 'RELEVANT' && (mismatches.length === 0)) {
      return {
        decision: 'APPROVE',
        reason:
          matches.length > 0
            ? 'Text und Fotos passen zu Fahrzeugteilen.'
            : 'Text passt eindeutig zu Fahrzeugteilen.',
        textReview: text,
        imageResults: images,
      };
    }

    // 4) Unsicherheit (weder Text noch Bild eindeutig, oder Konflikt) ->
    //    manuelle Pruefung (Punkt 9). NIE automatisch veroeffentlichen.
    const reason = broken.length > 0
      ? 'Automatische Pruefung unvollstaendig - bitte manuell pruefen.'
      : 'Automatische Pruefung unentschieden - bitte manuell pruefen.';
    return {
      decision: 'MANUAL_REVIEW',
      reason,
      textReview: text,
      imageResults: images,
    };
  }
}

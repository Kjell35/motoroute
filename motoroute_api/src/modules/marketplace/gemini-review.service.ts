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
import { MARKETPLACE_CATEGORIES } from './marketplace.taxonomy';

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
  /** KI-Urteil ueber den Text selbst (null = nicht verfuegbar/Fehler). */
  textAiReview: TextAiReview | null;
  /** Bildpruefung pro Bild: was das Modell erkannt hat. */
  imageResults: { url: string; verdict: ReviewMediaVerdict; label?: string }[];
}

/**
 * Ergebnis der Gemini-TEXTPRUEFUNG: passt der Text zum Marktplatz - und
 * passt der beschriebene Gegenstand zur gewaehlten (Unter-)Kategorie?
 * Der Regel-Klassifikator erkennt nur Fremd-Wortschatz; Gemini versteht
 * auch Zusammenhaenge ("Originales Teil, selten benutzt" + Kategorie
 * Auspuff -> plausibel; Titel "Kuehlschrank" + Kategorie Bremsen -> falsch).
 */
export interface TextAiReview {
  vehicleRelated: 'yes' | 'no' | 'unclear';
  categoryMatch: 'yes' | 'no' | 'unclear' | 'not_evaluated';
  item?: string;
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

/** Striktes Format fuer die reine TEXTPRUEFUNG (Titel/Beschreibung). */
const PROMPT_TEXT = 'You moderate text listings for a marketplace that ONLY allows parts and ' +
  'accessories for motorcycles, cars and bicycles. Judge ONLY the text ' +
  '(title, description, brand/model), no photos are attached. ' +
  '1) Does the text describe a vehicle part or vehicle accessory? ' +
  '2) If a category is given: does the described item plausibly belong to it? ' +
  'A wrong category is a mismatch even when the item itself is a vehicle part. ' +
  'Answer with JSON only: {"vehicle_related": "yes" | "no" | "unclear", ' +
  '"category_match": "yes" | "no" | "unclear", "item": "<short object name>"}. ' +
  'Use "no" only when you are confident (e.g. household items, electronics, ' +
  'clothing, toys); otherwise use "unclear".';

/** Aufloesung der Kategorie-Keys in lesbare Labels fuer den Prompt. */
function categoryLabels(category?: string, subcategory?: string): { category?: string; subcategory?: string } {
  const def = MARKETPLACE_CATEGORIES.find((c) => c.key === category);
  if (!def) return {};
  const sub = def.subcategories.find((s) => s.key === subcategory);
  return { category: def.labelDe, subcategory: sub?.labelDe };
}

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

    // Text-KI und Bildpruefung laufen parallel; Fehler = null bzw. 'error'.
    const [textAiReview, imageResults] = await Promise.all([
      this.inspectText(input),
      Promise.all(input.imageUrls.slice(0, 8).map(async (url) => this.inspectImage(url))),
    ]);

    return this.decide(input, textReview, textAiReview, imageResults);
  }

  /**
   * Gemini-TEXTPRUEFUNG: versteht der Text zusammenhaengend, was angeboten
   * wird - und passt das zur gewaehlten Kategorie? Liefert null bei
   * fehlender Konfiguration oder Fehler (degradiert auf Regelwerk).
   */
  private async inspectText(input: TextInput): Promise<TextAiReview | null> {
    if (!this.apiKey) return null;
    const labels = categoryLabels(input.category, input.subcategory);
    const evaluateCategory = !!(labels.category && labels.subcategory);

    const userText = [
      `Title: ${input.title}`,
      input.description ? `Description: ${input.description}` : null,
      input.brand ? `Brand: ${input.brand}` : null,
      input.model ? `Model: ${input.model}` : null,
      labels.category ? `Category: ${labels.category}` : null,
      labels.subcategory ? `Subcategory: ${labels.subcategory}` : null,
      evaluateCategory ? '' : 'Category: (none given - judge category_match as "unclear")',
    ]
      .filter((line): line is string => line !== null)
      .join('\n');

    try {
      const gemini = await axios.post(
        `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${this.apiKey}`,
        {
          contents: [{ parts: [{ text: `${PROMPT_TEXT}\n\n${userText}` }] }],
          generationConfig: { temperature: 0.1, responseMimeType: 'application/json' },
        },
        { timeout: GEMINI_TIMEOUT_MS },
      );

      const text: string | undefined = gemini.data?.candidates?.[0]?.content?.parts
        ?.map((p: { text?: string }) => p.text ?? '')
        .join('');
      if (!text) return null;

      const parsed = JSON.parse(text.trim()) as {
        vehicle_related?: string;
        category_match?: string;
        item?: string;
      };
      const vehicleRelated = ['yes', 'no', 'unclear'].includes(parsed.vehicle_related ?? '')
        ? (parsed.vehicle_related as TextAiReview['vehicleRelated'])
        : 'unclear';
      const categoryMatch = evaluateCategory && ['yes', 'no', 'unclear'].includes(parsed.category_match ?? '')
        ? (parsed.category_match as TextAiReview['categoryMatch'])
        : 'not_evaluated';
      return { vehicleRelated, categoryMatch, item: parsed.item };
    } catch (err) {
      this.logger.warn(`Gemini-Textpruefung fehlgeschlagen: ${axios.isAxiosError(err) ? err.message : err}`);
      return null;
    }
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
    textAi: TextAiReview | null,
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
        textAiReview: textAi,
        imageResults: images,
      };
    }

    // 1b) Gemini erkennt im TEXT ein fremdes Produkt (auch wenn der
    //     Regel-Klassifikator es verpasst hat) -> ablehnen.
    if (textAi?.vehicleRelated === 'no') {
      const item = textAi.item ?? 'unbekannter Gegenstand';
      return {
        decision: 'REJECT',
        reason: `Der Artikel ist kein Fahrzeugteil und kein Fahrzeugzubehör (erkannt: ${item}).`,
        textReview: text,
        textAiReview: textAi,
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
        textAiReview: textAi,
        imageResults: images,
      };
    }

    // 2b) Kategorie-Konsistenz: Titel/Beschreibung beschreiben NICHT das,
    //     was die gewaehlte (Unter-)Kategorie verspricht -> nicht automatisch
    //     veroeffentlichen, sondern dem Admin zeigen (korrigierbar).
    if (textAi?.categoryMatch === 'no') {
      return {
        decision: 'MANUAL_REVIEW',
        reason: 'Titel/Beschreibung passen nicht zur gewählten Kategorie - bitte manuell prüfen.',
        textReview: text,
        textAiReview: textAi,
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
        textAiReview: textAi,
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
      textAiReview: textAi,
      imageResults: images,
    };
  }
}

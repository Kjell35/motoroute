import { readFileSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Dateien der Plan-Seite: HTML-Vorlagen und die statischen Assets (CSS,
 * Skript). Sie liegen neben diesem Modul und werden von `nest build` nach
 * `dist/` kopiert (siehe `assets` in `nest-cli.json`) - `__dirname` zeigt
 * deshalb in Tests und im Build auf denselben Ordner.
 */
export type PlanAsset = 'page.html' | 'expired.html' | 'static/plan.css' | 'static/plan.js';

const cache = new Map<PlanAsset, string>();

export function readPlanAsset(name: PlanAsset): string {
  const cached = cache.get(name);
  if (cached !== undefined) return cached;

  const content = readFileSync(join(__dirname, name), 'utf8');
  cache.set(name, content);
  return content;
}

/**
 * Ersetzt `{{NAME}}`-Platzhalter. Ein fehlender Wert ist ein Fehler, kein
 * leerer String: sonst ginge z. B. ein vergessener QR-Code als kaputtes Bild
 * live, ohne dass es jemandem auffällt.
 */
export function renderTemplate(template: string, values: Record<string, string>): string {
  return template.replace(/\{\{([A-Z][A-Z0-9_]*)\}\}/g, (match, key: string) => {
    const value = values[key];
    if (value === undefined) {
      throw new Error(`Platzhalter ${key} in ${match} hat keinen Wert`);
    }
    return value;
  });
}

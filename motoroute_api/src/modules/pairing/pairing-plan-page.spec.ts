import { ConfigService } from '@nestjs/config';
import type { Request, Response } from 'express';
import { readPlanAsset, renderTemplate } from './plan-page/assets';
import { PairingPlanPageController } from './pairing-plan-page.controller';
import { PairingService } from './pairing.service';

/**
 * Sichert die Plan-Seite ab: das gerenderte HTML (Werte pro Plan) und die
 * ausgelagerten Dateien (CSS, Skript), die vorher als Template-String im
 * Controller steckten.
 *
 * Zwei Fehler waren bisher nur beim Rumklicken zu sehen und sollen hier
 * hängenbleiben:
 *  1. ein Syntaxfehler im Skript - die Seite lud, reagierte aber nicht mehr;
 *  2. ein Prefill mit literalen `\n` - das Textfeld zeigte nach dem Laden den
 *     Backslash statt Zeilenumbrüchen.
 */
type Point = { label: string; detail: string | null; lat: number; lon: number };

async function renderPlan(points: Point[] | null): Promise<{ status: number; html: string }> {
  const controller = new PairingPlanPageController(
    { getPoints: async () => points } as unknown as PairingService,
    new ConfigService({ PAIRING_PUBLIC_BASE_URL: 'https://api.example.org' }),
  );
  const req = { headers: {}, protocol: 'https' } as unknown as Request;
  const res = {
    status: jest.fn().mockReturnThis(),
    type: jest.fn().mockReturnThis(),
    send: jest.fn(),
  } as unknown as Response;

  await controller.page('K7G7YY', req, res);

  const send = res.send as unknown as jest.Mock;
  return {
    status: (res.status as unknown as jest.Mock).mock.calls[0]?.[0] ?? 200,
    html: send.mock.calls[0][0] as string,
  };
}

function textareaOf(html: string): string {
  const textarea = /<textarea[^>]*>([\s\S]*?)<\/textarea>/.exec(html)?.[1];
  expect(textarea).toBeDefined();
  return textarea!;
}

describe('Plan-Seite: gerendertes HTML', () => {
  const points: Point[] = [
    { lat: 47.4211, lon: 10.9848, label: 'Eibsee', detail: null },
    { lat: 47.5, lon: 11.5, label: 'Zugspitze', detail: null },
  ];

  it('schreibt den Prefill mit echten Zeilenumbrüchen ins Textfeld', async () => {
    const { html } = await renderPlan(points);
    const textarea = textareaOf(html);

    expect(textarea.split('\n')).toEqual([
      '47.4211, 10.9848, Eibsee',
      '47.5, 11.5, Zugspitze',
    ]);
    // Der alte Fehler: Backslash-n statt Umbruch -> alles klebte in einer Zeile.
    expect(textarea).not.toContain('\\n');
  });

  it('escaped Namen im Prefill, statt HTML einzuschleusen', async () => {
    const { html } = await renderPlan([
      { lat: 47.5, lon: 11.5, label: 'Zugspitze & Co <b>', detail: null },
    ]);

    expect(textareaOf(html)).toBe('47.5, 11.5, Zugspitze &amp; Co &lt;b&gt;');
  });

  it('setzt Code, Anzahl und QR-Bild in die Vorlage ein', async () => {
    const { html } = await renderPlan(points);

    expect(html).toContain('data-token="K7G7YY"');
    expect(html).toContain('id="count">2<');
    expect(html).toContain('<img src="data:image/png;base64,');
    expect(html).toContain('https://api.example.org/plan/K7G7YY');
    // Keine unaufgelösten Platzhalter - sonst stünde das im Browser.
    expect(html).not.toMatch(/\{\{[A-Z_]+\}\}/);
  });

  it('bindet CSS und Skript als statische Dateien ein', async () => {
    const { html } = await renderPlan(points);

    expect(html).toContain('<link rel="stylesheet" href="/plan/assets/plan.css">');
    expect(html).toContain('<script src="/plan/assets/plan.js"></script>');
    // Nichts mehr inline: weder <style> noch ein zweiter Skriptblock.
    expect(html).not.toContain('<style>');
    expect(html.match(/<script/g)).toHaveLength(2); // Leaflet + plan.js
    // Die Liste, in die das Skript seine Zeilen schreibt, muss da sein.
    expect(html).toContain('<ul id="pointlist"></ul>');
  });

  it('liefert für abgelaufene Pläne die 404-Seite', async () => {
    const { status, html } = await renderPlan(null);

    expect(status).toBe(404);
    expect(html).toContain('Dieser Plan ist abgelaufen');
    expect(html).toContain('https://api.example.org/plan/K7G7YY');
    expect(html).not.toMatch(/\{\{[A-Z_]+\}\}/);
  });
});

describe('Plan-Seite: ausgelagerte Dateien', () => {
  it('baut Punktliste, nummerierte Marker und Sortier-/Löschknöpfe im Skript auf', () => {
    const script = readPlanAsset('static/plan.js');

    // Die Zeile: Nummer, Namensfeld, Knöpfe.
    expect(script).toMatch(/function renderList\(points\)\s*\{[\s\S]*?nr\.className = 'nr';/);
    expect(script).toMatch(/name\.className = 'name';/);
    expect(script).toContain("listButton('▲', 'Nach oben', index === 0,");
    expect(script).toContain("listButton('▼', 'Nach unten', index === points.length - 1,");
    expect(script).toContain("listButton('×', 'Punkt löschen', false,");
    // Die Knöpfe müssen auch etwas tun, nicht nur da sein.
    expect(script).toMatch(/movePoint\(index, -1\)/);
    expect(script).toMatch(/movePoint\(index, 1\)/);
    expect(script).toMatch(/removePoint\(index\)/);

    // Marker: divIcon mit der Position in der Tour als Zahl.
    expect(script).toMatch(/className: 'numbered-pin'/);
    expect(script).toMatch(/html: '<span>' \+ \(index \+ 1\) \+ '<\/span>'/);
    // Start und Ziel sind farblich markiert (grün/rot) und benannt; die
    // Nummerierung und damit die Reihenfolge bleibt unverändert.
    expect(script).toMatch(/isStart \? ' start' : ''/);
    expect(script).toMatch(/isEnd \? ' end' : ''/);
    expect(script).toContain("title: isStart ? 'Start' : isEnd ? 'Ziel' : 'Wegpunkt ' + (index + 1),");
    expect(script).toMatch(/var isEnd = points\.length > 1 && index === points\.length - 1;/);
    // Und die Liste wird beim Zeichnen der Marker mit aufgebaut, sonst
    // entstünde sie nur beim Laden und nach Aktionen nie wieder.
    expect(script).toMatch(/function drawMarkers\(points\)\s*\{\s*syncRoute\(points\);\s*renderList\(points\);/);

    // Löschen gibt es nur einmal: Liste und Marker-Popup rufen dieselbe
    // Funktion, damit beide die Statusmeldung zeigen.
    expect(script.match(/current\.splice\(/g)).toHaveLength(1);
    expect(script).toMatch(/removePoint\(index\); \}\);/); // × in der Liste
    expect(script).toMatch(/remove\.addEventListener\('click', function \(\) \{ removePoint\(index\); \}\);/);
    expect(script).toContain("writePoints(current, 'Punkt gelöscht.');");

    // Der Plan-Code kommt aus dem data-Attribut, das Skript ist statisch.
    expect(script).toContain("document.body.getAttribute('data-token')");
  });

  it('liefert ein syntaktisch gültiges Skript aus', () => {
    const script = readPlanAsset('static/plan.js');

    expect(script).toContain('function drawMarkers');
    // Kompiliert, ohne es auszuführen: meldet Syntaxfehler wie den, der die
    // Seite zuvor still lahmlegte.
    expect(() => new Function(script)).not.toThrow();
  });

  it('enthält das Stylesheet der Seite', () => {
    const css = readPlanAsset('static/plan.css');

    expect(css).toContain('#pointlist .nr');
    expect(css).toContain('.numbered-pin span');
    expect(css).toContain('.numbered-pin.start span { background: #15803d; }');
    expect(css).toContain('.numbered-pin.end span { background: #b91c1c; }');
    expect(css).toContain('#map {');
    expect(css).not.toContain('<style>');
  });
});

describe('Plan-Seite: Vorlagen füllen', () => {
  it('ersetzt Platzhalter und meldet fehlende Werte', () => {
    expect(renderTemplate('a {{X}} b', { X: '1' })).toBe('a 1 b');
    expect(() => renderTemplate('a {{FEHLT}} b', { X: '1' })).toThrow(/FEHLT/);
  });
});

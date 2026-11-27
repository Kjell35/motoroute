import { ConfigService } from '@nestjs/config';
import type { Request, Response } from 'express';
import { PairingPlanPageController } from './pairing-plan-page.controller';
import { PairingService } from './pairing.service';

/**
 * Sichert das gerenderte HTML der Plan-Seite ab.
 *
 * Zwei Fehler sind bisher nur beim Rumklicken aufgefallen und sollen die Suite
 * künftig abfangen:
 *  1. ein Syntaxfehler im Inline-Skript - die Seite lud, aber kein Marker,
 *     keine Liste und kein Klick wurde mehr verarbeitet;
 *  2. ein Prefill mit literalen `\n` - das Textfeld zeigte nach dem Laden den
 *     Backslash statt Zeilenumbrüchen, also einen einzigen kaputten Eintrag.
 *
 * Deshalb prüft dieser Test die ausgelieferte Zeichenkette: echte Umbrüche im
 * <textarea>, die Bausteine der Punktliste (Nummer, Namensfeld, ▲/▼/×) und den
 * nummerierten divIcon der Marker. Das Inline-Skript wird zusätzlich durch
 * `new Function` kompiliert (ohne es auszuführen) - genau das hätte Fehler 1
 * gemeldet.
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

function inlineScript(html: string): string {
  const start = html.indexOf('<script>');
  const end = html.indexOf('</script>', start);
  expect(start).toBeGreaterThan(-1);
  expect(end).toBeGreaterThan(start);
  return html.slice(start + '<script>'.length, end);
}

describe('Plan-Seite: gerendertes HTML', () => {
  const points: Point[] = [
    { lat: 47.4211, lon: 10.9848, label: 'Eibsee', detail: null },
    { lat: 47.5, lon: 11.5, label: 'Zugspitze', detail: null },
  ];

  it('schreibt den Prefill mit echten Zeilenumbrüchen ins Textfeld', async () => {
    const { html } = await renderPlan(points);
    const textarea = /<textarea[^>]*>([\s\S]*?)<\/textarea>/.exec(html)?.[1];

    expect(textarea).toBeDefined();
    expect(textarea!.split('\n')).toEqual([
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
    const textarea = /<textarea[^>]*>([\s\S]*?)<\/textarea>/.exec(html)![1];

    expect(textarea).toBe('47.5, 11.5, Zugspitze &amp; Co &lt;b&gt;');
  });

  it('liefert Punktliste, nummerierte Marker und die Sortier-/Löschknöpfe aus', async () => {
    const { html } = await renderPlan(points);

    // Die Liste selbst und der Aufbau ihrer Zeilen: Nummer, Namensfeld, Knöpfe.
    expect(html).toContain('<ul id="pointlist"></ul>');
    expect(html).toMatch(/function renderList\(points\)\s*\{[\s\S]*?nr\.className = 'nr';/);
    expect(html).toMatch(/name\.className = 'name';/);
    expect(html).toContain("listButton('▲', 'Nach oben', index === 0,");
    expect(html).toContain("listButton('▼', 'Nach unten', index === points.length - 1,");
    expect(html).toContain("listButton('×', 'Punkt löschen', false,");
    // Die Knöpfe müssen auch etwas tun, nicht nur da sein.
    expect(html).toMatch(/movePoint\(index, -1\)/);
    expect(html).toMatch(/movePoint\(index, 1\)/);
    expect(html).toMatch(/removePoint\(index\)/);

    // Marker: divIcon mit der Position in der Tour als Zahl.
    expect(html).toMatch(/className: 'numbered-pin'/);
    expect(html).toMatch(/html: '<span>' \+ \(index \+ 1\) \+ '<\/span>'/);
    // Und die Liste wird beim Zeichnen der Marker mit aufgebaut, sonst
    // entstünde sie nur beim Laden und nach Aktionen nie wieder.
    expect(html).toMatch(/function drawMarkers\(points\)\s*\{\s*syncRoute\(points\);\s*renderList\(points\);/);
  });

  it('rendert ohne Punkte ein leeres Textfeld', async () => {
    const { html } = await renderPlan([]);
    const textarea = /<textarea[^>]*>([\s\S]*?)<\/textarea>/.exec(html)![1];

    expect(textarea).toBe('');
    expect(html).toContain('id="count">0<');
  });

  it('liefert ein syntaktisch gültiges Inline-Skript aus', async () => {
    const { html } = await renderPlan(points);
    const script = inlineScript(html);

    expect(script).toContain('"K7G7YY"');
    // Kompiliert, ohne es auszuführen: meldet Syntaxfehler wie den, der die
    // Seite zuvor still lahmlegte.
    expect(() => new Function(script)).not.toThrow();
  });
});

import { ConfigService } from '@nestjs/config';
import type { Request, Response } from 'express';
import { JSDOM } from 'jsdom';
import { readPlanAsset, renderTemplate } from './plan-page/assets';
import { PairingPlanPageController } from './pairing-plan-page.controller';
import { PairingService } from './pairing.service';

/**
 * Sichert die Plan-Seite ab, indem das ausgelieferte HTML mit dem echten
 * Skript in jsdom läuft: Klick auf die Karte, Sortieren, Umbenennen, Löschen
 * (Liste und Marker-Popup) und Speichern werden wirklich ausgeführt.
 *
 * Vorher prüfte dieser Spec nur den Quelltext per Regex - ein verdrehter
 * Handler fiel dabei nicht auf. Zwei Fehler waren zuvor nur beim Rumklicken
 * sichtbar: ein Syntaxfehler im Skript und ein Prefill mit literalen `\n`.
 *
 * Leaflet fehlt in jsdom; `installLeaflet()` stellt eine minimale Attrappe
 * bereit, die genau die Aufrufe der Seite beantwortet und die erzeugten
 * Marker samt Popup-Knoten festhält. Damit lässt sich der Popup-Knopf echt
 * anklicken.
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

/** Minimale Leaflet-Attrappe: sammelt Marker, Popup-Knoten und den Kartenklick. */
function installLeaflet(win: any) {
  const markers: any[] = [];
  const state: { clickHandler: ((event: any) => void) | null; closePopup: number } = {
    clickHandler: null,
    closePopup: 0,
  };

  const layerGroup = {
    addTo: () => layerGroup,
    clearLayers: () => {
      markers.length = 0;
    },
  };

  const map: any = {
    setView: () => map,
    on: (event: string, cb: (event: any) => void) => {
      if (event === 'click') state.clickHandler = cb;
      return map;
    },
    fitBounds: () => map,
    closePopup: () => {
      state.closePopup += 1;
    },
  };

  const polyline = { addTo: () => polyline, setLatLngs: () => polyline };

  win.L = {
    map: () => map,
    tileLayer: () => ({ addTo: () => ({}) }),
    layerGroup: () => layerGroup,
    polyline: () => polyline,
    latLngBounds: (points: any) => ({ points }),
    divIcon: (options: any) => options,
    marker: (latlng: any, options: any) => {
      const marker: any = {
        latlng,
        options,
        addTo: () => marker,
        bindPopup: (node: any) => {
          marker.popup = node;
          return marker;
        },
        on: (event: string, cb: (event: any) => void) => {
          marker[`on_${event}`] = cb;
          return marker;
        },
        getLatLng: () => marker.latlng,
      };
      markers.push(marker);
      return marker;
    },
  };

  return { map, markers, state };
}

type Mounted = {
  dom: JSDOM;
  win: any;
  doc: any;
  markers: any[];
  state: { clickHandler: ((event: any) => void) | null; closePopup: number };
  fetchMock: jest.Mock;
};

async function mountPage(points: Point[] | null): Promise<Mounted> {
  const { html } = await renderPlan(points);
  const dom = new JSDOM(html, {
    url: 'https://api.example.org/plan/K7G7YY',
    runScripts: 'outside-only',
  });
  const win = dom.window as any;
  const { markers, state } = installLeaflet(win);

  const fetchMock = jest.fn(async () => ({ ok: true, status: 200 }));
  win.fetch = fetchMock;

  // Das Seiten-Stylesheet lädt jsdom nicht selbst nach; einfügen, damit
  // getComputedStyle die Farben der Badges kennt.
  const style = win.document.createElement('style');
  style.textContent = readPlanAsset('static/plan.css');
  win.document.head.appendChild(style);

  win.eval(readPlanAsset('static/plan.js'));

  return { dom, win, doc: win.document, markers, state, fetchMock };
}

const threePoints: Point[] = [
  { lat: 47.4211, lon: 10.9848, label: 'Eibsee', detail: null },
  { lat: 47.5, lon: 11.5, label: 'Zugspitze', detail: null },
  { lat: 47.6, lon: 12.1, label: 'Kufstein', detail: null },
];

function rows(doc: any): any[] {
  return [...doc.querySelectorAll('#pointlist li')];
}

function labels(doc: any): string[] {
  return rows(doc).map((row: any) => row.querySelector('input.name').value);
}

function lines(doc: any): string[] {
  return doc.getElementById('points').value.split('\n');
}

function pressEnter(win: any, input: any): void {
  input.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
}

function renameInList(win: any, doc: any, row: number, name: string): void {
  const input = rows(doc)[row].querySelector('input.name');
  input.value = name;
  pressEnter(win, input);
}

describe('Plan-Seite in jsdom: Laden', () => {
  it('zeigt die gespeicherten Punkte als Liste und Marker', async () => {
    const { doc, markers } = await mountPage(threePoints);

    expect(labels(doc)).toEqual(['Eibsee', 'Zugspitze', 'Kufstein']);
    expect(lines(doc)).toEqual([
      '47.4211, 10.9848, Eibsee',
      '47.5, 11.5, Zugspitze',
      '47.6, 12.1, Kufstein',
    ]);
    expect(markers).toHaveLength(3);
    expect(markers.map((m) => m.options.icon.html)).toEqual(['<span>1</span>', '<span>2</span>', '<span>3</span>']);
    expect(markers.map((m) => m.options.title)).toEqual(['Start', 'Wegpunkt 2', 'Ziel']);
  });

  it('schreibt echte Zeilenumbrüche ins Textfeld', async () => {
    const { doc } = await mountPage(threePoints);

    expect(doc.getElementById('points').value).toContain('\n');
    expect(doc.getElementById('points').value).not.toContain('\\n');
  });

  it('markiert Start grün und Ziel rot - in Liste und Marker', async () => {
    const { doc, win, markers } = await mountPage(threePoints);
    const badges = rows(doc).map((row: any) => row.querySelector('.nr'));

    expect(badges.map((b: any) => b.className)).toEqual(['nr start', 'nr', 'nr end']);
    expect(win.getComputedStyle(badges[0]).backgroundColor).toBe('rgb(21, 128, 61)');
    expect(win.getComputedStyle(badges[2]).backgroundColor).toBe('rgb(185, 28, 28)');
    expect(markers[0].options.icon.className).toContain('start');
    expect(markers[2].options.icon.className).toContain('end');
  });

  it('rendert ohne Punkte eine leere Liste', async () => {
    const { doc, markers } = await mountPage([]);

    expect(rows(doc)).toHaveLength(0);
    expect(doc.getElementById('points').value).toBe('');
    expect(markers).toHaveLength(0);
    // Die Zusammenfassung bleibt beim leeren Start leer (sie wird erst beim
    // ersten Zeichnen bzw. nach dem Löschen des letzten Punktes gesetzt).
  });
});

describe('Plan-Seite in jsdom: Bedienung', () => {
  it('setzt per Kartenklick einen Punkt ans Ende', async () => {
    const { doc, markers, state } = await mountPage(threePoints);

    state.clickHandler!({ latlng: { lat: 47.7, lng: 11.9 } });

    expect(labels(doc)).toEqual(['Eibsee', 'Zugspitze', 'Kufstein', 'Wegpunkt 4']);
    expect(lines(doc)[3]).toBe('47.70000, 11.90000, Wegpunkt 4');
    expect(markers).toHaveLength(4);
    expect(doc.getElementById('status').textContent).toBe('Punkt gesetzt - die Textzeile ist ergänzt.');
  });

  it('sortiert über die ▲▼-Knöpfe und zieht Start/Ziel mit', async () => {
    const { doc } = await mountPage(threePoints);

    rows(doc)[0].querySelectorAll('button')[1].click(); // ▼ auf Zeile 1

    expect(labels(doc)).toEqual(['Zugspitze', 'Eibsee', 'Kufstein']);
    expect(lines(doc)[0]).toBe('47.50000, 11.50000, Zugspitze');
    expect(rows(doc).map((row: any) => row.querySelector('.nr').className)).toEqual([
      'nr start',
      'nr',
      'nr end',
    ]);
    expect(doc.getElementById('status').textContent).toBe('Reihenfolge geändert.');
  });

  it('benennt über die Liste um (Enter)', async () => {
    const { doc, win } = await mountPage(threePoints);

    renameInList(win, doc, 1, 'Gipfel');

    expect(labels(doc)).toEqual(['Eibsee', 'Gipfel', 'Kufstein']);
    expect(lines(doc)[1]).toBe('47.50000, 11.50000, Gipfel');
    expect(doc.getElementById('status').textContent).toBe('Punkt umbenannt: Gipfel');
  });

  it('benennt im Marker-Popup um', async () => {
    const { doc, win, markers } = await mountPage(threePoints);
    const popupInput = markers[1].popup.querySelector('input.popup-name');

    popupInput.value = 'Zugspitzgipfel';
    pressEnter(win, popupInput);

    expect(labels(doc)).toEqual(['Eibsee', 'Zugspitzgipfel', 'Kufstein']);
    expect(lines(doc)[1]).toBe('47.50000, 11.50000, Zugspitzgipfel');
    expect(doc.getElementById('status').textContent).toBe('Punkt umbenannt: Zugspitzgipfel');
  });

  it('lässt einen leeren Namen nicht zu', async () => {
    const { doc, win } = await mountPage(threePoints);
    const input = rows(doc)[0].querySelector('input.name');

    input.value = '   ';
    pressEnter(win, input);

    expect(input.value).toBe('Eibsee');
    expect(lines(doc)[0]).toBe('47.4211, 10.9848, Eibsee');
  });

  it('speichert die Punkte über die API des Plans', async () => {
    const { doc, fetchMock, win } = await mountPage(threePoints);

    doc.getElementById('save').click();
    await new Promise((resolve) => win.setTimeout(resolve, 0));

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, options] = fetchMock.mock.calls[0];
    // Der Plan-Code kommt aus data-token am <body>, nicht aus dem Skript.
    expect(url).toBe('/api/v1/pairing/K7G7YY/points');
    expect(options.method).toBe('PUT');
    expect(JSON.parse(options.body).points).toHaveLength(3);
    expect(doc.getElementById('status').textContent).toBe('3 Punkt(e) gespeichert – in der App abholen.');
    expect(doc.getElementById('count').textContent).toBe('3');
  });
});

describe('Plan-Seite in jsdom: Löschen', () => {
  it('löscht über den ×-Knopf der Liste', async () => {
    const { doc, markers } = await mountPage(threePoints);

    rows(doc)[1].querySelectorAll('button')[2].click();

    expect(labels(doc)).toEqual(['Eibsee', 'Kufstein']);
    expect(markers).toHaveLength(2);
    expect(doc.getElementById('status').textContent).toBe('Punkt gelöscht.');
  });

  it('zeigt beim Löschen im Marker-Popup dieselbe Statusmeldung', async () => {
    const { doc, markers } = await mountPage(threePoints);

    markers[1].popup.querySelector('button').click();

    const popupMessage = doc.getElementById('status').textContent;
    expect(popupMessage).toBe('Punkt gelöscht.');
    expect(labels(doc)).toEqual(['Eibsee', 'Kufstein']);

    // Gegenprobe: der Weg über die Liste meldet wortgleich dasselbe.
    rows(doc)[0].querySelectorAll('button')[2].click();
    expect(doc.getElementById('status').textContent).toBe(popupMessage);
    expect(labels(doc)).toEqual(['Kufstein']);
  });

  it('nimmt den letzten Punkt über den Undo-Knopf zurück', async () => {
    const { doc } = await mountPage(threePoints);

    doc.getElementById('undo').click();

    expect(labels(doc)).toEqual(['Eibsee', 'Zugspitze']);
    expect(doc.getElementById('status').textContent).toBe('Letzten Punkt zurückgenommen.');
  });
});

describe('Plan-Seite: ausgeliefertes HTML', () => {
  it('bindet CSS und Skript als statische Dateien ein', async () => {
    const { html } = await renderPlan(threePoints);

    expect(html).toContain('<link rel="stylesheet" href="/plan/assets/plan.css">');
    expect(html).toContain('<script src="/plan/assets/plan.js"></script>');
    expect(html).not.toContain('<style>');
    expect(html).toContain('data-token="K7G7YY"');
    // Keine unaufgelösten Platzhalter - sonst stünde das im Browser.
    expect(html).not.toMatch(/\{\{[A-Z_]+\}\}/);
  });

  it('liefert für abgelaufene Pläne die 404-Seite', async () => {
    const { status, html } = await renderPlan(null);

    expect(status).toBe(404);
    expect(html).toContain('Dieser Plan ist abgelaufen');
    expect(html).toContain('https://api.example.org/plan/K7G7YY');
    expect(html).not.toMatch(/\{\{[A-Z_]+\}\}/);
  });

  it('ersetzt Platzhalter und meldet fehlende Werte', () => {
    expect(renderTemplate('a {{X}} b', { X: '1' })).toBe('a 1 b');
    expect(() => renderTemplate('a {{FEHLT}} b', { X: '1' })).toThrow(/FEHLT/);
  });
});

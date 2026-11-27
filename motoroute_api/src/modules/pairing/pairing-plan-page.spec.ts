import { ConfigService } from '@nestjs/config';
import type { Request, Response } from 'express';
import { JSDOM } from 'jsdom';
import QRCode from 'qrcode';
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

async function renderQr(token: string): Promise<{ contentType: unknown; body: unknown }> {
  const controller = new PairingPlanPageController(
    { getPoints: async () => [] } as unknown as PairingService,
    new ConfigService({ PAIRING_PUBLIC_BASE_URL: 'https://api.example.org' }),
  );
  const res = {
    type: jest.fn().mockReturnThis(),
    send: jest.fn(),
  } as unknown as Response;

  await controller.qr(token, { headers: {}, protocol: 'https' } as unknown as Request, res);

  const type = res.type as unknown as jest.Mock;
  const send = res.send as unknown as jest.Mock;
  return { contentType: type.mock.calls[0]?.[0], body: send.mock.calls[0]?.[0] };
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

type MountOptions = { draft?: unknown; fetch?: jest.Mock };

async function mountPage(
  points: Point[] | null,
  options: MountOptions = {},
): Promise<Mounted> {
  const { html } = await renderPlan(points);
  const dom = new JSDOM(html, {
    url: 'https://api.example.org/plan/K7G7YY',
    runScripts: 'outside-only',
  });
  const win = dom.window as any;
  const { markers, state } = installLeaflet(win);

  const fetchMock = options.fetch ?? jest.fn(async () => ({ ok: true, status: 200 }));
  win.fetch = fetchMock;

  // Entwurf vor dem Laden setzen: das Skript liest ihn beim Start.
  if (options.draft !== undefined) {
    win.localStorage.setItem(
      'motoroute.plan.K7G7YY',
      JSON.stringify({ version: 1, at: Date.now(), points: options.draft }),
    );
  }

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

/** Laesst die Promise-Ketten der Seite durchlaufen (mehrere then-Ebenen). */
async function flush(win: any, ticks = 8): Promise<void> {
  for (let i = 0; i < ticks; i += 1) {
    await new Promise((resolve) => win.setTimeout(resolve, 0));
  }
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
    // Schon beim Laden gefüllt, damit unter der Karte keine leere Zeile steht.
    expect(doc.getElementById('summary').textContent).toBe('Noch keine Punkte.');
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

describe('Plan-Seite in jsdom: Etappen', () => {
  // Punkte auf dem Äquator: 1 Längengrad sind 111,19 km - gut nachzurechnen.
  const equator: Point[] = [
    { lat: 0, lon: 0, label: 'A', detail: null },
    { lat: 0, lon: 1, label: 'B', detail: null },
    { lat: 0, lon: 3, label: 'C', detail: null },
  ];

  function legs(doc: any): string[] {
    return [...doc.querySelectorAll('#pointlist .leg')].map((leg: any) => leg.textContent);
  }

  it('zeigt je Zeile die Luftlinie bis zum nächsten Punkt', async () => {
    const { doc, win } = await mountPage(equator);
    const leg = doc.querySelector('#pointlist .leg');

    // A→B ein Längengrad, B→C zwei.
    expect(legs(doc)).toEqual(['→ 111,2 km', '→ 222,4 km']);
    // Die Zeile hat auch ihre eigene Auszeichnung (klein, gedämpft).
    expect(win.getComputedStyle(leg).fontSize).toBe('12px');
    expect(win.getComputedStyle(leg).color).toBe('rgb(82, 82, 91)');
  });

  it('lässt die letzte Zeile ohne Etappe', async () => {
    const { doc } = await mountPage(equator);

    expect(rows(doc)[2].querySelector('.leg')).toBeNull();
    expect(rows(doc)[0].querySelector('.leg')).not.toBeNull();
    expect(rows(doc)[0].querySelector('.leg').getAttribute('title')).toBe(
      'Luftlinie zum nächsten Punkt',
    );
  });

  it('rechnet nach dem Sortieren neu', async () => {
    const { doc } = await mountPage(equator);

    rows(doc)[0].querySelectorAll('button')[1].click(); // ▼: A und B tauschen

    expect(labels(doc)).toEqual(['B', 'A', 'C']);
    expect(legs(doc)).toEqual(['→ 111,2 km', '→ 333,6 km']);
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

  it('dreht die Reihenfolge um - Start/Ziel, Etappen und Textzeilen mit', async () => {
    const { doc, markers } = await mountPage(threePoints);
    const summary = doc.getElementById('summary').textContent;

    doc.getElementById('reverse').click();

    expect(labels(doc)).toEqual(['Kufstein', 'Zugspitze', 'Eibsee']);
    expect(lines(doc)).toEqual([
      '47.60000, 12.10000, Kufstein',
      '47.50000, 11.50000, Zugspitze',
      '47.42110, 10.98480, Eibsee',
    ]);
    // Start/Ziel wandern mit: erster Punkt grün, letzter rot - Liste und Marker.
    expect(rows(doc).map((row: any) => row.querySelector('.nr').className)).toEqual([
      'nr start',
      'nr',
      'nr end',
    ]);
    expect(markers.map((m) => m.options.title)).toEqual(['Start', 'Wegpunkt 2', 'Ziel']);
    expect(markers[0].options.icon.className).toContain('start');
    expect(markers[2].options.icon.className).toContain('end');
    // Etappen in der neuen Richtung, Gesamtstrecke bleibt gleich.
    expect(rows(doc)[0].querySelector('.leg').textContent).toBe('→ 46,4 km');
    expect(rows(doc)[1].querySelector('.leg').textContent).toBe('→ 39,7 km');
    expect(rows(doc)[2].querySelector('.leg')).toBeNull();
    expect(doc.getElementById('summary').textContent).toBe(summary);
    expect(doc.getElementById('status').textContent).toBe(
      'Reihenfolge umgedreht - Ziel ist jetzt Start.',
    );
  });

  it('speichert Änderungen entprellt von selbst', async () => {
    try {
      const { doc, state, fetchMock } = await mountPage(threePoints);
      jest.useFakeTimers();
      const warte = async () => { await Promise.resolve(); await Promise.resolve(); };

      state.clickHandler!({ latlng: { lat: 47.7, lng: 11.9 } });
      state.clickHandler!({ latlng: { lat: 47.8, lng: 12.0 } });
      jest.advanceTimersByTime(300);
      // Noch nichts gespeichert: die Entprellung wartet die Pause ab.
      expect(fetchMock).toHaveBeenCalledTimes(0);

      jest.advanceTimersByTime(500);
      await warte();
      expect(fetchMock).toHaveBeenCalledTimes(1);
      const [url, options] = fetchMock.mock.calls[0];
      expect(url).toBe('/api/v1/pairing/K7G7YY/points');
      expect(options.method).toBe('PUT');
      expect(JSON.parse(options.body).points).toHaveLength(5);
      expect(doc.getElementById('status').textContent).toBe('Automatisch gespeichert.');
    } finally {
      jest.useRealTimers();
    }
  });

  it('warnt beim Verlassen nur mit ungespeicherten Änderungen', async () => {
    try {
      const { doc, win, state } = await mountPage(threePoints);
      jest.useFakeTimers();
      const verlassen = () => {
        const event = new win.Event('beforeunload', { cancelable: true });
        win.dispatchEvent(event);
        return event.defaultPrevented;
      };

      // Frisch geladen ist alles gespeichert.
      expect(verlassen()).toBe(false);

      state.clickHandler!({ latlng: { lat: 47.7, lng: 11.9 } });
      expect(verlassen()).toBe(true);

      // Nach dem automatischen Speichern darf nicht mehr gewarnt werden.
      jest.advanceTimersByTime(800);
      await Promise.resolve();
      await Promise.resolve();
      expect(doc.getElementById('status').textContent).toBe('Automatisch gespeichert.');
      expect(verlassen()).toBe(false);
    } finally {
      jest.useRealTimers();
    }
  });

  it('speichert sofort und schaltet die Warnung ab', async () => {
    try {
      const { doc, win, state, fetchMock } = await mountPage(threePoints);
      jest.useFakeTimers();
      state.clickHandler!({ latlng: { lat: 47.7, lng: 11.9 } });

      doc.getElementById('save').click();
      await Promise.resolve();
      await Promise.resolve();
      expect(fetchMock).toHaveBeenCalledTimes(1);
      expect(doc.getElementById('status').textContent).toBe('4 Punkt(e) gespeichert – in der App abholen.');

      // Der wartende Autosave darf keinen zweiten Aufruf auslösen.
      jest.advanceTimersByTime(2000);
      await Promise.resolve();
      expect(fetchMock).toHaveBeenCalledTimes(1);

      const event = new win.Event('beforeunload', { cancelable: true });
      win.dispatchEvent(event);
      expect(event.defaultPrevented).toBe(false);
    } finally {
      jest.useRealTimers();
    }
  });

  it('sperrt das Umdrehen bei weniger als zwei Punkten', async () => {
    const leer = await mountPage([]);
    expect(leer.doc.getElementById('reverse').disabled).toBe(true);

    const einer = await mountPage([threePoints[0]]);
    expect(einer.doc.getElementById('reverse').disabled).toBe(true);
    einer.doc.getElementById('reverse').click(); // gesperrt: ändert nichts
    expect(labels(einer.doc)).toEqual(['Eibsee']);
  });
});

describe('Plan-Seite in jsdom: Rückgängig', () => {
  it('ist beim Laden gesperrt', async () => {
    const { doc } = await mountPage(threePoints);

    expect(doc.getElementById('undo').disabled).toBe(true);
    expect(doc.getElementById('undo').title).toBe('Nichts rückgängig zu machen');
  });

  it('holt einen über × gelöschten Punkt samt Namen zurück', async () => {
    const { doc } = await mountPage(threePoints);

    rows(doc)[1].querySelectorAll('button')[2].click();
    expect(labels(doc)).toEqual(['Eibsee', 'Kufstein']);

    doc.getElementById('undo').click();

    expect(labels(doc)).toEqual(['Eibsee', 'Zugspitze', 'Kufstein']);
    expect(lines(doc)[1]).toBe('47.50000, 11.50000, Zugspitze');
    expect(doc.getElementById('status').textContent).toBe('Rückgängig gemacht: Punkt gelöscht.');
    // Zurück in der Ausgangslage: nichts mehr rückgängig zu machen.
    expect(doc.getElementById('undo').disabled).toBe(true);
  });

  it('holt einen im Marker-Popup gelöschten Punkt zurück', async () => {
    const { doc, markers } = await mountPage(threePoints);
    const popupButton = markers[0].popup.querySelector('button');

    popupButton.click();
    expect(labels(doc)).toEqual(['Zugspitze', 'Kufstein']);

    doc.getElementById('undo').click();

    expect(labels(doc)).toEqual(['Eibsee', 'Zugspitze', 'Kufstein']);
    expect(markers).toHaveLength(3);
    // Start/Ziel sitzen wieder richtig.
    expect(rows(doc).map((row: any) => row.querySelector('.nr').className)).toEqual([
      'nr start',
      'nr',
      'nr end',
    ]);
  });

  it('macht das Umdrehen rückgängig', async () => {
    const { doc, markers } = await mountPage(threePoints);

    doc.getElementById('reverse').click();
    expect(labels(doc)).toEqual(['Kufstein', 'Zugspitze', 'Eibsee']);

    doc.getElementById('undo').click();

    expect(labels(doc)).toEqual(['Eibsee', 'Zugspitze', 'Kufstein']);
    expect(lines(doc)[0]).toBe('47.42110, 10.98480, Eibsee');
    expect(markers.map((m) => m.options.title)).toEqual(['Start', 'Wegpunkt 2', 'Ziel']);
    expect(doc.getElementById('status').textContent).toBe('Rückgängig gemacht: Umdrehen.');
  });

  it('stellt nach dem Ziehen die alte Lage wieder her', async () => {
    const { doc, markers } = await mountPage(threePoints);
    const marker = markers[1];

    marker.latlng = { lat: 48.9, lng: 12.9 };
    marker.on_dragend();
    expect(lines(doc)[1]).toBe('48.90000, 12.90000, Zugspitze');

    doc.getElementById('undo').click();

    expect(lines(doc)[1]).toBe('47.50000, 11.50000, Zugspitze');
    expect(labels(doc)).toEqual(['Eibsee', 'Zugspitze', 'Kufstein']);
    expect(doc.getElementById('status').textContent).toBe('Rückgängig gemacht: Verschieben.');
  });

  it('nimmt eine Umbenennung zurück', async () => {
    const { doc, win } = await mountPage(threePoints);

    renameInList(win, doc, 1, 'Gipfel');
    expect(labels(doc)).toEqual(['Eibsee', 'Gipfel', 'Kufstein']);

    doc.getElementById('undo').click();

    expect(labels(doc)).toEqual(['Eibsee', 'Zugspitze', 'Kufstein']);
    expect(lines(doc)[1]).toBe('47.50000, 11.50000, Zugspitze');
  });

  it('geht mehrere Schritte einzeln zurück und sperrt sich am Anfang', async () => {
    const { doc, state } = await mountPage(threePoints);

    state.clickHandler!({ latlng: { lat: 47.7, lng: 11.9 } });
    state.clickHandler!({ latlng: { lat: 47.8, lng: 12.0 } });
    rows(doc)[0].querySelectorAll('button')[2].click(); // × auf Zeile 1
    expect(labels(doc)).toEqual(['Zugspitze', 'Kufstein', 'Wegpunkt 4', 'Wegpunkt 5']);

    // Der Titel sagt, was der naechste Schritt rueckgaengig macht.
    expect(doc.getElementById('undo').title).toBe('Rückgängig: Punkt gelöscht');

    doc.getElementById('undo').click();
    expect(labels(doc)).toEqual(['Eibsee', 'Zugspitze', 'Kufstein', 'Wegpunkt 4', 'Wegpunkt 5']);
    expect(doc.getElementById('undo').title).toBe('Rückgängig: Punkt gesetzt');

    doc.getElementById('undo').click();
    expect(labels(doc)).toEqual(['Eibsee', 'Zugspitze', 'Kufstein', 'Wegpunkt 4']);

    doc.getElementById('undo').click();
    expect(labels(doc)).toEqual(['Eibsee', 'Zugspitze', 'Kufstein']);
    expect(doc.getElementById('undo').disabled).toBe(true);
  });

  it('macht auch Änderungen im Textfeld rückgängig', async () => {
    try {
      const { doc, win } = await mountPage(threePoints);
      jest.useFakeTimers();
      const area = doc.getElementById('points');

      area.value = '47.4211, 10.9848, Eibsee\n47.5, 11.5, Zugspitze';
      area.dispatchEvent(new win.Event('input', { bubbles: true }));
      jest.advanceTimersByTime(400);
      expect(labels(doc)).toEqual(['Eibsee', 'Zugspitze']);

      doc.getElementById('undo').click();

      expect(labels(doc)).toEqual(['Eibsee', 'Zugspitze', 'Kufstein']);
      expect(area.value).toContain('Kufstein');
      expect(doc.getElementById('status').textContent).toBe(
        'Rückgängig gemacht: Textfeld geändert.',
      );
    } finally {
      jest.useRealTimers();
    }
  });
});

describe('Plan-Seite in jsdom: abgelaufener Code', () => {
  /**
   * Server, auf dem der alte Code abgelaufen ist: PUT auf K7G7YY -> 404,
   * POST /start -> neuer Code, alles andere -> 200.
   */
  function expiredMock(): jest.Mock {
    return jest.fn(async (url: string, _init?: any): Promise<any> => {
      if (url === '/api/v1/pairing/start') {
        return { ok: true, status: 200, json: async () => ({ token: 'NEU234' }) };
      }
      if (url === '/api/v1/pairing/K7G7YY/points') return { ok: false, status: 404 };
      return { ok: true, status: 200 };
    });
  }

  it('legt einen neuen Code an und übernimmt die Punkte', async () => {
    const fetchMock = expiredMock();
    const { doc, win } = await mountPage(threePoints, { fetch: fetchMock });

    doc.getElementById('save').click();
    await flush(win);

    expect(fetchMock.mock.calls.map((call) => call[0])).toEqual([
      '/api/v1/pairing/K7G7YY/points',
      '/api/v1/pairing/start',
      '/api/v1/pairing/NEU234/points',
    ]);
    expect(JSON.parse(fetchMock.mock.calls[2][1].body).points).toHaveLength(3);
    expect(doc.getElementById('status').textContent).toContain('Neuer Code NEU234');
    expect(doc.getElementById('code').textContent).toBe('NEU234');
    expect(doc.body.getAttribute('data-token')).toBe('NEU234');
    // Adresszeile mitgezogen: ein Reload landet beim neuen Code.
    expect(win.location.pathname).toBe('/plan/NEU234');
  });

  it('hängt Link, QR und GPX auf den neuen Code um', async () => {
    const { doc, win } = await mountPage(threePoints, { fetch: expiredMock() });

    doc.getElementById('save').click();
    await flush(win);

    expect(doc.getElementById('plan-url').textContent).toBe(
      'https://api.example.org/plan/NEU234',
    );
    expect(doc.getElementById('qr').getAttribute('src')).toBe('/plan/NEU234/qr.png');
    const gpx = doc.getElementById('gpx');
    expect(gpx.getAttribute('href')).toBe('/plan/NEU234/gpx');
    expect(gpx.getAttribute('download')).toBe('MotoRoute-NEU234.gpx');
    expect(gpx.textContent).toBe('MotoRoute-NEU234.gpx');
  });

  it('speichert danach unter dem neuen Code weiter', async () => {
    const fetchMock = expiredMock();
    const { doc, win, state } = await mountPage(threePoints, { fetch: fetchMock });

    doc.getElementById('save').click();
    await flush(win);
    fetchMock.mockClear();

    state.clickHandler!({ latlng: { lat: 47.7, lng: 11.9 } });
    doc.getElementById('save').click();
    await flush(win);

    expect(fetchMock.mock.calls[0][0]).toBe('/api/v1/pairing/NEU234/points');
    expect(JSON.parse(fetchMock.mock.calls[0][1].body).points).toHaveLength(4);
  });

  it('rettet auch beim automatischen Speichern', async () => {
    try {
      const { doc, win, state, fetchMock } = await mountPage(threePoints, {
        fetch: expiredMock(),
      });
      jest.useFakeTimers();

      state.clickHandler!({ latlng: { lat: 47.7, lng: 11.9 } });
      jest.advanceTimersByTime(800);
      for (let tick = 0; tick < 14; tick += 1) await Promise.resolve();

      expect(fetchMock.mock.calls[0][0]).toBe('/api/v1/pairing/K7G7YY/points');
      expect(doc.getElementById('code').textContent).toBe('NEU234');
      // Der gesetzte Punkt geht mit, nicht nur der alte Stand.
      expect(JSON.parse(fetchMock.mock.calls[2][1].body).points).toHaveLength(4);
    } finally {
      jest.useRealTimers();
    }
  });

  it('sichert den Entwurf und rät zum Neuladen, wenn kein neuer Code klappt', async () => {
    const fetchMock = jest.fn(async (url: string, _init?: any): Promise<any> => {
      if (url === '/api/v1/pairing/start') return { ok: false, status: 429 };
      return { ok: false, status: 404 };
    });
    const { doc, win } = await mountPage(threePoints, { fetch: fetchMock });

    doc.getElementById('save').click();
    await flush(win);

    expect(doc.getElementById('status').textContent).toContain('liegen als Entwurf im Browser');
    expect(doc.getElementById('code').textContent).toBe('K7G7YY');
    expect(win.localStorage.getItem('motoroute.plan.K7G7YY')).not.toBeNull();
  });
});

describe('Plan-Seite in jsdom: Entwurf im Browser', () => {
  const draftPoints: Point[] = [
    ...threePoints,
    { lat: 47.7, lon: 11.9, label: 'Sprint', detail: null },
  ];

  it('bietet beim Laden einen abweichenden Entwurf an', async () => {
    const { doc } = await mountPage(threePoints, { draft: draftPoints });

    expect(doc.getElementById('draft').hidden).toBe(false);
    expect(doc.getElementById('draft-text').textContent).toContain('4 Punkten');
    expect(doc.getElementById('draft-text').textContent).toContain('Entwurf von');
  });

  it('übernimmt den Entwurf auf Knopfdruck', async () => {
    const { doc } = await mountPage(threePoints, { draft: draftPoints });

    doc.getElementById('draft-use').click();

    expect(doc.getElementById('draft').hidden).toBe(true);
    expect(labels(doc)).toEqual(['Eibsee', 'Zugspitze', 'Kufstein', 'Sprint']);
    expect(doc.getElementById('status').textContent).toContain('Entwurf übernommen');
  });

  it('verwirft den Entwurf und räumt den Speicher', async () => {
    const { doc, win } = await mountPage(threePoints, { draft: draftPoints });

    doc.getElementById('draft-drop').click();

    expect(doc.getElementById('draft').hidden).toBe(true);
    expect(win.localStorage.getItem('motoroute.plan.K7G7YY')).toBeNull();
    expect(labels(doc)).toEqual(['Eibsee', 'Zugspitze', 'Kufstein']);
    expect(doc.getElementById('status').textContent).toBe('Entwurf verworfen.');
  });

  it('schweigt, wenn der Entwurf dem gespeicherten Stand entspricht', async () => {
    const { doc, win } = await mountPage(threePoints, { draft: threePoints });

    expect(doc.getElementById('draft').hidden).toBe(true);
    expect(win.localStorage.getItem('motoroute.plan.K7G7YY')).toBeNull();
  });

  it('schreibt jede Änderung lokal und räumt nach dem Speichern auf', async () => {
    const { doc, win, state } = await mountPage(threePoints);
    const key = 'motoroute.plan.K7G7YY';

    state.clickHandler!({ latlng: { lat: 47.7, lng: 11.9 } });
    expect(JSON.parse(win.localStorage.getItem(key)!).points).toHaveLength(4);
    // Die Leiste erscheint nur beim Laden, nicht bei jeder Änderung.
    expect(doc.getElementById('draft').hidden).toBe(true);

    doc.getElementById('save').click();
    await flush(win);
    // Gespeichert: der Server ist die Wahrheit, kein Entwurf mehr nötig.
    expect(win.localStorage.getItem(key)).toBeNull();
  });

  it('hält den Entwurf, wenn das Speichern scheitert', async () => {
    const fetchMock = jest.fn(async (): Promise<any> => ({ ok: false, status: 503 }));
    const { doc, win, state } = await mountPage(threePoints, { fetch: fetchMock });

    state.clickHandler!({ latlng: { lat: 47.7, lng: 11.9 } });
    doc.getElementById('save').click();
    await flush(win);

    expect(win.localStorage.getItem('motoroute.plan.K7G7YY')).not.toBeNull();
    expect(doc.getElementById('status').textContent).toContain('fehlgeschlagen');
  });

  it('wiederholt ein fehlgeschlagenes Speichern nicht im Takt', async () => {
    const fetchMock = jest.fn(async (): Promise<any> => ({ ok: false, status: 503 }));
    try {
      const { doc, win, state } = await mountPage(threePoints, { fetch: fetchMock });
      jest.useFakeTimers();

      state.clickHandler!({ latlng: { lat: 47.7, lng: 11.9 } });
      jest.advanceTimersByTime(800);
      for (let tick = 0; tick < 6; tick += 1) await Promise.resolve();
      expect(fetchMock).toHaveBeenCalledTimes(1);

      // Frueher plante sich der Autosave nach einem Fehlschlag endlos neu ein.
      jest.advanceTimersByTime(4000);
      for (let tick = 0; tick < 6; tick += 1) await Promise.resolve();
      expect(fetchMock).toHaveBeenCalledTimes(1);
      expect(doc.getElementById('status').textContent).toContain('fehlgeschlagen');

      // Ungespeichert bleibt ungespeichert: die Warnung beim Verlassen steht.
      const event = new win.Event('beforeunload', { cancelable: true });
      win.dispatchEvent(event);
      expect(event.defaultPrevented).toBe(true);
    } finally {
      jest.useRealTimers();
    }
  });
});

describe('Plan-Seite: QR-Code als PNG', () => {
  it('kodiert den Plan-Link des Tokens', async () => {
    const png = Buffer.from([0x89, 0x50, 0x4e, 0x47]);
    const spy = jest.spyOn(QRCode, 'toBuffer').mockResolvedValue(png as never);
    try {
      const { contentType, body } = await renderQr('k7g7yy');

      expect(spy).toHaveBeenCalledWith(
        'https://api.example.org/plan/K7G7YY',
        expect.objectContaining({ type: 'png' }),
      );
      expect(contentType).toBe('png');
      expect(body).toEqual(png);
    } finally {
      spy.mockRestore();
    }
  });
});

describe('Plan-Seite: ausgeliefertes HTML', () => {
  it('bindet CSS und Skript als statische Dateien ein', async () => {
    const { html } = await renderPlan(threePoints);

    expect(html).toContain('<link rel="stylesheet" href="/plan/assets/plan.css">');
    expect(html).toContain('<script src="/plan/assets/plan.js"></script>');
    expect(html).not.toContain('<style>');
    expect(html).toContain('data-token="K7G7YY"');
    // GPX-Download hängt direkt an der Seite - kein App-Build nötig.
    expect(html).toContain('href="/plan/K7G7YY/gpx"');
    expect(html).toContain('MotoRoute-K7G7YY.gpx');
    // Die Rettung haengt genau diese Stellen auf einen neuen Code um.
    expect(html).toContain('id="code"');
    expect(html).toContain('id="plan-url"');
    expect(html).toContain('id="qr"');
    expect(html).toContain('id="draft"');
    expect(html).toContain('verlängert sich beim Speichern');
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

import { Controller, Get, Param, Req, Res } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Request, Response } from 'express';
import QRCode from 'qrcode';
import { normalizeToken, PairingService } from './pairing.service';
import { publicOrigin } from './pairing-url';

/**
 * Die Plan-Seite am Rechner: /plan/{TOKEN}. Kein Template-Engine, kein
 * Frontend-Build - eine handgeschriebene Seite, die ihre Punkte als
 * `lat, lon, Label` je Zeile entgegennimmt und per fetch an den
 * JSON-Endpunkt zurückschreibt.
 */
@Controller('plan')
export class PairingPlanPageController {
  constructor(
    private readonly pairing: PairingService,
    private readonly config: ConfigService,
  ) {}

  @Get(':token')
  async page(
    @Param('token') token: string,
    @Req() req: Request,
    @Res() res: Response,
  ): Promise<void> {
    const points = await this.pairing.getPoints(token);
    const planUrl = `${publicOrigin(req, this.config.get<string>('PAIRING_PUBLIC_BASE_URL'))}/plan/${normalizeToken(token)}`;

    if (points === null) {
      res.status(404).type('html').send(expiredPage(planUrl));
      return;
    }

    const qr = await QRCode.toDataURL(planUrl, { margin: 1, width: 260 });
    res.type('html').send(planPage(normalizeToken(token), planUrl, qr, points));
  }
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function layout(title: string, body: string, extraHead = ''): string {
  return `<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>${extraHead}
<style>
  :root { color-scheme: light dark; }
  body { font-family: system-ui, -apple-system, "Segoe UI", sans-serif; margin: 0;
         padding: 24px; background: #f4f4f5; color: #18181b; }
  main { max-width: 640px; margin: 0 auto; background: #fff; border-radius: 16px;
         padding: 24px; box-shadow: 0 2px 12px rgba(0,0,0,.08); }
  h1 { font-size: 20px; margin: 0 0 4px; }
  p, li { line-height: 1.5; }
  .muted { color: #52525b; font-size: 14px; }
  code { background: #f4f4f5; padding: 2px 6px; border-radius: 6px; }
  #map { height: 340px; margin: 0 0 6px; border: 1px solid #d4d4d8; border-radius: 12px;
         background: #f4f4f5; z-index: 0; }
  #summary { margin: 0 0 4px; font-weight: 500; }
  #map-hint { margin: 0 0 16px; }
  .linkish { background: none; border: 0; padding: 0; color: #b91c1c; cursor: pointer;
             font-size: 13px; text-decoration: underline; }
  textarea { width: 100%; box-sizing: border-box; min-height: 220px; font: 14px/1.5 ui-monospace, monospace;
             padding: 12px; border: 1px solid #d4d4d8; border-radius: 10px; resize: vertical; }
  button { margin-top: 12px; padding: 12px 18px; font-size: 16px; border: 0; border-radius: 10px;
           background: #18181b; color: #fff; cursor: pointer; }
  button:disabled { opacity: .6; cursor: default; }
  .row { display: flex; gap: 24px; flex-wrap: wrap; align-items: flex-start; }
  .qr { text-align: center; }
  .qr img { width: 220px; height: 220px; image-rendering: pixelated; }
  #status { margin-top: 12px; font-size: 14px; min-height: 20px; }
  .ok { color: #15803d; } .err { color: #b91c1c; }
</style>
</head>
<body><main>${body}</main></body>
</html>`;
}

function planPage(
  token: string,
  planUrl: string,
  qrDataUrl: string,
  points: { label: string; detail: string | null; lat: number; lon: number }[],
): string {
  // Achtung: hier echter Zeilenumbruch, kein '\\n' - das ist TS-Code
  // (ausserhalb des HTML-Templates) und wuerde sonst als Backslash-n im
  // Textfeld landen, sodass nach dem Laden alles in einer Zeile klebt.
  const prefill = points
    .map((p) => `${p.lat}, ${p.lon}, ${p.label}`)
    .join('\n');
  const body = `
<h1>Route am Computer planen</h1>
<p class="muted">Code <strong>${escapeHtml(token)}</strong> · gültig für 2 Stunden · gespeichert: <span id="count">${points.length}</span></p>
<div id="map" role="application" aria-label="Karte: Klick setzt einen Wegpunkt"></div>
<p class="muted" id="summary"></p>
<p class="muted" id="map-hint">In die Karte klicken setzt einen Punkt, Marker ziehen verschiebt ihn -
  die Zeilen darunter werden automatisch mitgeführt (und bleiben der Fallback).</p>
<div class="row">
  <div class="qr">
    <img src="${qrDataUrl}" alt="QR-Code mit dem Plan-Link" width="220" height="220">
    <p class="muted">In der App scannen:<br>Wegpunkte → „Am Computer planen“</p>
  </div>
  <div style="flex:1; min-width: 260px;">
    <p>Punkte eintragen — eine Zeile pro Wegpunkt:<br>
      <code>Breite, Länge, Name</code><br>
      <span class="muted">z.&nbsp;B. <code>47.4211, 10.9848, Eibsee</code></span></p>
    <textarea id="points" spellcheck="false" placeholder="47.4211, 10.9848, Eibsee">${escapeHtml(prefill)}</textarea>
    <button id="save" type="button">Punkte speichern</button>
    <div id="status"></div>
    <p class="muted">Link zum Abtippen:<br><code>${escapeHtml(planUrl)}</code></p>
  </div>
</div>
<script>
(function () {
  var token = ${JSON.stringify(token)};
  var area = document.getElementById('points');
  var status = document.getElementById('status');
  var button = document.getElementById('save');
  var count = document.getElementById('count');
  var mapBox = document.getElementById('map');
  var mapHint = document.getElementById('map-hint');
  var summary = document.getElementById('summary');
  function show(text, cls) { status.textContent = text; status.className = cls || ''; }
  function parse(text) {
    var points = [];
    text.split(/\\r?\\n/).forEach(function (line, index) {
      var trimmed = line.trim();
      if (!trimmed) return;
      var parts = trimmed.split(',');
      if (parts.length < 2) throw new Error('Zeile ' + (index + 1) + ': Breite und Länge fehlen');
      var lat = Number(parts[0]);
      var lon = Number(parts[1]);
      if (!isFinite(lat) || lat < -90 || lat > 90) throw new Error('Zeile ' + (index + 1) + ': Breite ungültig');
      if (!isFinite(lon) || lon < -180 || lon > 180) throw new Error('Zeile ' + (index + 1) + ': Länge ungültig');
      var label = parts.slice(2).join(',').trim();
      points.push({ lat: lat, lon: lon, label: label || ('Wegpunkt ' + (points.length + 1)) });
    });
    return points;
  }
  // ---- Karte: Klick setzt einen Punkt, Ziehen verschiebt ihn.
  // Die Textzeilen bleiben die Wahrheit: jede Kartenaktion schreibt sie neu,
  // und Tippen im Textfeld zeichnet die Marker nach.
  var map = null;
  var markerLayer = null;
  var routeLine = null;
  var lastCount = -1;
  var writeGuard = false;
  var editTimer = null;

  function readPoints() {
    try { return parse(area.value); } catch (err) { return null; }
  }

  // Luftlinie zwischen zwei Punkten (Haversine, Erdradius 6371,0088 km).
  // Bewusst ohne Routingdienst: die Linie ist eine Lesehilfe fuer die
  // Reihenfolge, keine berechnete Strassenstrecke.
  function distanceKm(a, b) {
    var rad = Math.PI / 180;
    var dLat = (b.lat - a.lat) * rad;
    var dLon = (b.lon - a.lon) * rad;
    var s = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
    return 2 * 6371.0088 * Math.asin(Math.sqrt(s));
  }

  function formatKm(km) {
    if (km < 1) return Math.round(km * 1000) + ' m';
    return km.toFixed(1).replace('.', ',') + ' km';
  }

  function updateSummary(points) {
    if (!summary) return;
    if (!points.length) { summary.textContent = 'Noch keine Punkte.'; return; }
    var parts = [points.length === 1 ? '1 Punkt' : points.length + ' Punkte'];
    if (points.length > 1) {
      var km = 0;
      for (var i = 1; i < points.length; i += 1) km += distanceKm(points[i - 1], points[i]);
      parts.push('Luftlinie ' + formatKm(km));
    }
    summary.textContent = parts.join(' · ');
  }

  // Linie in der Reihenfolge der Punkte: zeigt sofort, wenn die Tour
  // zickzackt. interactive: false, damit sie keine Klicks auf die Karte
  // abfaengt. Laeuft auch beim Drag mit, dort werden die Marker nicht neu
  // aufgebaut.
  function syncRoute(points) {
    updateSummary(points);
    if (routeLine) {
      routeLine.setLatLngs(points.map(function (p) { return [p.lat, p.lon]; }));
    }
  }

  function writePoints(points, message, redraw) {
    writeGuard = true;
    area.value = points.map(function (p) {
      return p.lat.toFixed(5) + ', ' + p.lon.toFixed(5) + ', ' + p.label;
    }).join('\\n');
    writeGuard = false;
    syncRoute(points);
    // redraw === false laesst vorhandene Marker stehen (Fall: Marker gezogen -
    // der Marker sitzt nach dem Drag schon richtig, ein Neuaufbau waere nur
    // ein DOM-Teardown mitten in der laufenden Mausgeste).
    if (redraw !== false) drawMarkers(points);
    if (message) show(message, 'ok');
  }

  function drawMarkers(points) {
    syncRoute(points);
    if (!markerLayer) return;
    markerLayer.clearLayers();
    points.forEach(function (p, index) {
      var marker = L.marker([p.lat, p.lon], { draggable: true, keyboard: false }).addTo(markerLayer);
      var box = document.createElement('div');
      var title = document.createElement('strong');
      title.textContent = p.label;
      var remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'linkish';
      remove.textContent = 'Punkt entfernen';
      remove.addEventListener('click', function () {
        var current = readPoints() || [];
        current.splice(index, 1);
        map.closePopup();
        writePoints(current);
      });
      box.appendChild(title);
      box.appendChild(document.createElement('br'));
      box.appendChild(remove);
      marker.bindPopup(box);
      marker.on('dragend', function () {
        var current = readPoints() || [];
        var moved = marker.getLatLng();
        var old = current[index];
        current[index] = {
          lat: moved.lat,
          lon: moved.lng,
          label: old ? old.label : 'Wegpunkt ' + (index + 1),
          detail: old ? old.detail : null
        };
        // Marker NICHT neu aufbauen: clearLayers() zerstoert hier genau das
        // Element, an dem der Browser den Drag gerade beendet - der naechste
        // Klick (z. B. auf "Punkte speichern") kann dadurch verschluckt werden.
        writePoints(current, 'Punkt verschoben - Zeile aktualisiert.', false);
      });
    });
    if (points.length && points.length !== lastCount) {
      lastCount = points.length;
      map.fitBounds(L.latLngBounds(points.map(function (p) { return [p.lat, p.lon]; })),
        { padding: [30, 30], maxZoom: 12 });
    }
  }

  function initMap() {
    if (!window.L || !mapBox) {
      if (mapHint) mapHint.textContent = 'Karte hier nicht verfügbar - Punkte wie gewohnt als Zeilen eintragen, das funktioniert genauso.';
      updateSummary(readPoints() || []);
      return;
    }
    map = L.map(mapBox, { scrollWheelZoom: false }).setView([47.6, 11.0], 8);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 18,
      attribution: '&copy; OpenStreetMap-Mitwirkende'
    }).addTo(map);
    markerLayer = L.layerGroup().addTo(map);
    routeLine = L.polyline([], { color: '#18181b', weight: 3, opacity: 0.7, interactive: false }).addTo(map);
    map.on('click', function (event) {
      var current = readPoints() || [];
      current.push({
        lat: event.latlng.lat,
        lon: event.latlng.lng,
        label: 'Wegpunkt ' + (current.length + 1)
      });
      writePoints(current, 'Punkt gesetzt - die Textzeile ist ergänzt.');
    });
    var initial = readPoints();
    if (initial && initial.length) drawMarkers(initial);
  }

  area.addEventListener('input', function () {
    if (writeGuard) return;
    clearTimeout(editTimer);
    editTimer = setTimeout(function () {
      var points = readPoints();
      if (!points) return;
      drawMarkers(points);
      show('', '');
    }, 350);
  });

  button.addEventListener('click', function () {
    var points;
    try { points = parse(area.value); } catch (e) { show(e.message, 'err'); return; }
    button.disabled = true;
    show('Speichern …');
    fetch('/api/v1/pairing/' + token + '/points', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ points: points })
    }).then(function (res) {
      if (res.ok) { count.textContent = points.length; show(points.length + ' Punkt(e) gespeichert – in der App abholen.', 'ok'); }
      else if (res.status === 404) { show('Dieser Plan ist abgelaufen. Bitte in der App neu starten.', 'err'); }
      else { show('Speichern fehlgeschlagen (' + res.status + ').', 'err'); }
    }).catch(function () {
      show('Server nicht erreichbar. Verbindung prüfen und erneut versuchen.', 'err');
    }).then(function () { button.disabled = false; });
  });
initMap();
})();
</script>`;
  return layout(
    'Route planen – MotoRoute',
    body,
    '<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">' +
      '<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>',
  );
}

function expiredPage(planUrl: string): string {
  return layout(
    'Plan abgelaufen – MotoRoute',
    `<h1>Dieser Plan ist abgelaufen</h1>
<p>Der Code ist nicht mehr gültig (Pläne laufen nach 2 Stunden ab) oder existiert nicht.</p>
<p>Starte in der App neu: <strong>Wegpunkte → „Am Computer planen“</strong>.</p>
<p class="muted">Aufgerufen: <code>${escapeHtml(planUrl)}</code></p>`,
  );
}

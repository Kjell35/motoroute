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

function layout(title: string, body: string): string {
  return `<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
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
  const prefill = points
    .map((p) => `${p.lat}, ${p.lon}, ${p.label}`)
    .join('\n');
  const body = `
<h1>Route am Computer planen</h1>
<p class="muted">Code <strong>${escapeHtml(token)}</strong> · gültig für 2 Stunden · gespeichert: <span id="count">${points.length}</span></p>
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
})();
</script>`;
  return layout('Route planen – MotoRoute', body);
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

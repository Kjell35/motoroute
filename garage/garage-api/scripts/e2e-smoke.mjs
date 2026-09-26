// E2E-Smoke-Test gegen die laufende Garage-API (localhost:4100).
// Liest ADMIN_EMAIL/ADMIN_PASSWORD aus .env, zeigt Passwoerter NIE an.
// Deckt ab: Login, Katalog, Fahrzeug anlegen, Specs, Wartung, Erinnerung,
// Tankbuch-Verbrauch, Reifen, Dokument, Kosten, Kilometerstand-Update.
import fs from 'fs';

const BASE = 'http://localhost:4100';
const get = (k) => { const m = fs.readFileSync('.env', 'utf8').match(new RegExp('^' + k + '="?([^"\\r\\n]*)"?', 'm')); return m ? m[1] : undefined; };

let failures = 0;
const step = (name, cond, extra = '') => {
  console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? '  [' + extra + ']' : ''));
  if (!cond) failures++;
};

async function api(path, { method = 'GET', body, token } = {}) {
  const res = await fetch(BASE + path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: 'Bearer ' + token } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = null;
  try { json = await res.json(); } catch { /* leere Antwort ok */ }
  return { status: res.status, json };
}

// 1) Login mit dem Bootstrap-Admin aus der .env
const email = get('ADMIN_EMAIL');
const login = await api('/api/auth/login', { method: 'POST', body: { email, password: get('ADMIN_PASSWORD') } });
step('Login', login.status === 200 && !!login.json?.accessToken, 'HTTP ' + login.status);
const token = login.json?.accessToken;

// 2) Garage leer?
const garage0 = await api('/api/vehicles/garage', { token });
step('GET /vehicles/garage', garage0.status === 200, 'HTTP ' + garage0.status);

// 3) Katalog: BMW -> R 1250 GS -> Standard-Variante
const mans = await api('/api/catalog/manufacturers?type=MOTORCYCLE', { token });
const mansArr = mans.json?.manufacturers ?? mans.json ?? [];
const bmw = Array.isArray(mansArr) ? mansArr.find((m) => /bmw/i.test(m.name)) : undefined;
step('Katalog: BMW gefunden', !!bmw, mans.status + ', ' + (Array.isArray(mansArr) ? mansArr.length : '?') + ' Hersteller');

const models = await api('/api/catalog/manufacturers/' + bmw.id + '/models', { token });
const modelsArr = models.json?.models ?? models.json ?? [];
const gs = Array.isArray(modelsArr) ? modelsArr.find((m) => /1250/i.test(m.name)) : undefined;
step('Katalog: R 1250 GS gefunden', !!gs, Array.isArray(modelsArr) ? modelsArr.map((m) => m.name).join(', ') : '?');

const variants = await api('/api/catalog/models/' + gs.id + '/variants', { token });
const variantsArr = variants.json?.variants ?? variants.json ?? [];
const std = Array.isArray(variantsArr) ? variantsArr[0] : undefined;
step('Katalog: Variante vorhanden', !!std, Array.isArray(variantsArr) ? variantsArr.map((v) => v.name).join(', ') : '?');

// 4) Fahrzeug anlegen (Vertrag: Namen ODER variantId, Preis in Cents)
const created = await api('/api/vehicles', {
  method: 'POST', token,
  body: {
    category: 'motorcycle', manufacturerName: 'BMW', modelName: 'R 1250 GS', variantId: std.id,
    year: 2024, odometerKm: 42350, nickname: 'E2E-Test-Bike', color: 'Schwarz',
    licensePlate: 'E2E-PRIVAT-123', purchasePriceCents: 1990000, notes: 'E2E-Testfahrzeug',
  },
});
step('Fahrzeug anlegen', created.status === 201 || created.status === 200, 'HTTP ' + created.status + ' ' + (created.json?.error ? JSON.stringify(created.json.error).slice(0, 80) : ''));
const vehicle = created.json;

// 5) Technische Daten (eigene Route aus dem Katalog)
const specs = await api('/api/vehicles/' + vehicle.id + '/specifications', { token });
const specObj = specs.json?.specifications ?? specs.json ?? {};
const specCount = typeof specObj === 'object' ? Object.keys(specObj).length : 0;
step('Technische Daten vorhanden', specs.status === 200 && specCount > 0, specCount + ' Specs');
const sampleKeys = Object.keys(specObj).slice(0, 4).map((k) => k + '=' + String(specObj[k]).slice(0, 18)).join(' ');
if (sampleKeys) console.log('     Specs-Beispiel: ' + sampleKeys);

// 6) Privatsphaere: ohne Token keine Fahrzeug-Endpunkte
step('Keine oeffentlichen Fahrzeug-Endpunkte', (await api('/api/vehicles/' + vehicle.id)).status === 401, 'ohne Token -> 401');

// 7) Wartung: Oelwechsel ohne nextDue -> Server berechnet aus Standard-Intervall
const maint = await api('/api/vehicles/' + vehicle.id + '/maintenance', {
  method: 'POST', token,
  body: { type: 'OIL_CHANGE', performedAt: '2026-09-01', odometerKm: 42000, costCents: 8900 },
});
step('Wartung erfassen (Oelwechsel)', maint.status === 201 || maint.status === 200, 'HTTP ' + maint.status + ' ' + (maint.json?.error ? JSON.stringify(maint.json.error).slice(0, 80) : ''));
const mRec = maint.json?.record ?? maint.json ?? {};
console.log('     nextDueOdometerKm=' + (mRec.nextDueOdometerKm ?? mRec.nextDueKm) + ' nextDueDate=' + (mRec.nextDueDate ?? '-'));

// 8) Erinnerungen: Status-Liste
const rem = await api('/api/vehicles/' + vehicle.id + '/reminders', { token });
const remArr = rem.json?.reminders ?? rem.json ?? [];
const oil = Array.isArray(remArr) ? remArr.find((r) => r.type === 'OIL_CHANGE' || r.typeKey === 'OIL_CHANGE') : undefined;
step('Erinnerungen abrufen', rem.status === 200 && Array.isArray(remArr) && remArr.length > 0, Array.isArray(remArr) ? remArr.length + ' Typen' : '?');
if (oil) console.log('     Oelwechsel-Status: ' + (oil.status ?? oil.level) + ' (Rest: ' + (oil.kmRemaining ?? oil.remainingKm) + ' km / ' + (oil.daysRemaining ?? oil.remainingDays) + ' Tage)');

// 9) Tankbuch: zwei Volltankungen -> Verbrauch
const f1 = await api('/api/vehicles/' + vehicle.id + '/fuel', { method: 'POST', token, body: { date: '2026-09-05', odometerKm: 42350, liters: 18, priceCentsTotal: 3060, station: 'Shell' } });
const f2 = await api('/api/vehicles/' + vehicle.id + '/fuel', { method: 'POST', token, body: { date: '2026-09-20', odometerKm: 42950, liters: 16.5, priceCentsTotal: 2805, station: 'Aral' } });
step('Tankbuch-Eintraege', f1.status < 300 && f2.status < 300, 'HTTP ' + f1.status + '/' + f2.status + ' ' + (f1.json?.error ? JSON.stringify(f1.json.error).slice(0, 80) : ''));
const fuel = await api('/api/vehicles/' + vehicle.id + '/fuel/stats', { token });
const stats = fuel.json && fuel.json.averageConsumptionPer100km !== undefined ? fuel.json : fuel.json?.stats;
console.log('     Verbrauch: ' + JSON.stringify(stats));

// 10) Reifen + Dokument
const tire = await api('/api/vehicles/' + vehicle.id + '/tires', { method: 'POST', token, body: { position: 'front', brand: 'Michelin', modelName: 'Road 6', size: '120/70 ZR17', mountedAt: '2026-04-01', mountedAtKm: 38000, treadDepthMm: 4.5 } });
step('Reifen anlegen', tire.status < 300, 'HTTP ' + tire.status + ' ' + (tire.json?.error ? JSON.stringify(tire.json.error).slice(0, 80) : ''));
const doc = await api('/api/vehicles/' + vehicle.id + '/documents', { method: 'POST', token, body: { type: 'invoice', title: 'Kaufvertrag (Test)', fileUrl: 'https://example.invalid/e2e.pdf', mimeType: 'application/pdf' } });
step('Dokument anlegen', doc.status < 300, 'HTTP ' + doc.status + ' ' + (doc.json?.error ? JSON.stringify(doc.json.error).slice(0, 80) : ''));

// 11) Kosten (Fahrzeug-Ebene, Alias auf Wartungs-Kosten)
const costs = await api('/api/vehicles/' + vehicle.id + '/costs', { token });
step('Kosten-Auswertung', costs.status === 200, JSON.stringify(costs.json).slice(0, 110));

// 12) Kilometerstand aktualisieren
const upd = await api('/api/vehicles/' + vehicle.id, { method: 'PUT', token, body: { odometerKm: 42950 } });
step('Kilometerstand-Update', upd.status === 200, 'HTTP ' + upd.status);

// 13) Aufräumen: Testfahrzeug weg (historische DB bleibt sauber)
const del = await api('/api/vehicles/' + vehicle.id, { method: 'DELETE', token });
step('Testfahrzeug geloescht (kaskadierend)', del.status === 200 || del.status === 204, 'HTTP ' + del.status);

console.log('');
console.log(failures === 0 ? '=== ALLE E2E-CHECKS GRUEN ===' : '=== ' + failures + ' CHECK(S) FEHLGESCHLAGEN ===');
process.exit(failures === 0 ? 0 : 1);

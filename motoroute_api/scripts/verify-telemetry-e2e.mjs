// Live-E2E für die Telemetrie (Migration 0008: app_error_reports).
// Ablauf: register -> admin/errors als Normalnutzer (403) -> Fehler melden
// (202) -> per Service-Key zum Admin befördern -> admin/errors (200) ->
// anonyme Meldung (202, ohne Token) -> Cleanup (Admin-Konto löschen).
import fs from 'fs';

const env = Object.fromEntries(
  fs.readFileSync('.env', 'utf8')
    .split(/\r?\n/)
    .filter((l) => l.includes('=') && !l.startsWith('#'))
    .map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]),
);

const API = 'https://motoroute-api-8fi9.onrender.com';
const SB = env.SUPABASE_URL;
const KEY = env.SUPABASE_SERVICE_ROLE_KEY;

const email = `telemetry-live-${Date.now()}@example.com`;
const pw = 'Test1234!';

const reg = await fetch(`${API}/v1/auth/register`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ email, password: pw }),
});
const regBody = await reg.json();
const token = regBody.accessToken || regBody.access_token;
console.log('register:', reg.status, token ? 'token ok' : 'KEIN TOKEN');

// Nutzer-ID für die Admin-Beförderung holen.
const uidRes = await fetch(`${SB}/auth/v1/user`, {
  headers: { Authorization: `Bearer ${token}`, apikey: KEY },
});
const uid = (await uidRes.json())?.id;
console.log('user id:', uid ? uid : 'FEHLER');

// 1) admin/errors als Normalnutzer -> 403.
const before = await fetch(`${API}/v1/telemetry/admin/errors`, {
  headers: { Authorization: `Bearer ${token}` },
});
console.log('admin/errors als Normalnutzer:', before.status, '(403 erwartet)');

// 2) Fehlerbericht mit Token melden -> 202.
const rep = await fetch(`${API}/v1/telemetry/errors`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
  body: JSON.stringify({
    category: 'other',
    cause: 'e2e-verify-telemetry (Testbericht, kann ignoriert werden)',
    httpStatus: 503,
    platform: 'web',
    appVersion: '0.4.8',
  }),
});
console.log('errors melden:', rep.status, JSON.stringify(await rep.json()));

// 3) Anonyme Meldung (ohne Token) -> 202.
const anon = await fetch(`${API}/v1/telemetry/errors`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    category: 'other',
    cause: 'e2e-verify-telemetry anonym (Testbericht)',
    platform: 'web',
    appVersion: '0.4.8',
  }),
});
console.log('errors anonym:', anon.status, JSON.stringify(await anon.json()));

// 4) Zum Admin befördern (Service-Key umgeht RLS).
const promote = await fetch(`${SB}/rest/v1/users?id=eq.${uid}`, {
  method: 'PATCH',
  headers: {
    apikey: KEY,
    Authorization: `Bearer ${KEY}`,
    'Content-Type': 'application/json',
    Prefer: 'return=minimal',
  },
  body: JSON.stringify({ role: 'admin' }),
});
console.log('promote zu admin:', promote.status, '(2xx erwartet)');

// 5) admin/errors als Admin -> 200 + unsere Berichte.
const after = await fetch(`${API}/v1/telemetry/admin/errors?limit=20`, {
  headers: { Authorization: `Bearer ${token}` },
});
const list = await after.json();
const rows = Array.isArray(list) ? list : list.reports ?? [];
const ours = rows.filter((r) => String(r.cause ?? '').includes('e2e-verify-telemetry'));
console.log('admin/errors als Admin:', after.status, '| rows gesamt:', rows.length, '| e2e-Treffer:', ours.length);
if (rows[0]) {
  console.log('  neuester:', JSON.stringify({ category: rows[0].category, cause: rows[0].cause, http_status: rows[0].http_status, app_version: rows[0].app_version }));
}

// Cleanup: Test-Konto entfernen. Der Nutzer ist danach kein Admin mehr;
// die Testberichte bleiben (anonym) in app_error_reports - erkennbar am cause.
const del = await fetch(`${SB}/auth/v1/admin/users/${uid}`, {
  method: 'DELETE',
  headers: { apikey: KEY, Authorization: `Bearer ${KEY}` },
});
console.log('cleanup:', del.status);

const ok = before.status === 403 && rep.status === 202 && anon.status === 202 && [200, 201, 204].includes(promote.status) && after.status === 200 && ours.length >= 2;
console.log(ok ? 'ERGEBNIS: OK - Telemetrie funktioniert live' : 'ERGEBNIS: FEHLER - siehe Zeilen oben');
process.exit(ok ? 0 : 1);

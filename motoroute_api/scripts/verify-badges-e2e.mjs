// Live-E2E für den Pass-Knacker nach Migration (Stilfser Joch).
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

const email = `badge-live-${Date.now()}@example.com`;
const pw = 'Test1234!';

const reg = await fetch(`${API}/v1/auth/register`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ email, password: pw }),
});
const regBody = await reg.json();
const token = regBody.accessToken || regBody.access_token;
console.log('register:', reg.status, token ? 'token ok' : 'KEIN TOKEN');

// 1) Check-in am Stilfser Joch (Seed-Punkt).
const c1 = await fetch(`${API}/v1/badges/checkin`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
  body: JSON.stringify({ lat: 46.52847, lon: 10.45255 }),
});
const b1 = await c1.json();
console.log(
  'checkin #1:', c1.status,
  '| unlockedNow:', JSON.stringify(b1.unlockedNow?.map((b) => b.title)),
  '| dist:', `${b1.unlockedNow?.[0]?.distanceMeters}m`,
  '| total:', b1.totalUnlocked,
);

// 2) Erneut -> idempotent (revisited statt Doppel-Unlock).
const c2 = await fetch(`${API}/v1/badges/checkin`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
  body: JSON.stringify({ lat: 46.52847, lon: 10.45255 }),
});
const b2 = await c2.json();
console.log(
  'checkin #2:', c2.status,
  '| unlockedNow:', b2.unlockedNow?.length,
  '| revisited:', JSON.stringify(b2.revisited?.map((b) => b.title)),
);

// 3) Trophäenschrank.
const me = await fetch(`${API}/v1/badges/me`, { headers: { Authorization: `Bearer ${token}` } });
const mb = await me.json();
const un = mb.badges?.find((b) => b.unlocked);
console.log('badges/me:', me.status, '| unlocked:', `${mb.unlockedCount}/${mb.totalCount}`, '|', un?.title, '|', un?.unlockedAt);

// 4) Admin-Endpunkt: normaler Nutzer -> 403.
const adm = await fetch(`${API}/v1/badges`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
  body: JSON.stringify({ title: 'Test', category: 'pass', lat: 1, lon: 1 }),
});
console.log('create als normaler Nutzer:', adm.status, '(403 erwartet)');

// Cleanup: Test-Konto inkl. user_badges (FK cascade) entfernen.
const uidRes = await fetch(`${SB}/auth/v1/user`, {
  headers: { Authorization: `Bearer ${token}`, apikey: KEY },
});
const uid = (await uidRes.json())?.id;
const del = await fetch(`${SB}/auth/v1/admin/users/${uid}`, {
  method: 'DELETE',
  headers: { apikey: KEY, Authorization: `Bearer ${KEY}` },
});
console.log('cleanup:', del.status);

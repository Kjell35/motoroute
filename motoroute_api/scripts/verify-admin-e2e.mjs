// E2E-Admin-Verifikation gegen die LIVE-Systeme.
// 1) Registriert einen Wegwerf-Account, befördert ihn in der DB zum Admin
// 2) Prueft: chat admin reports, marketplace admin, garage admin (via provision)
// 3) Loescht den Account wieder (DB sauber)
// Nutzung: node scripts/verify-admin-e2e.mjs
import fs from 'fs';

const env = fs.readFileSync('.env', 'utf8');
const get = (k) => (env.match(new RegExp('^' + k + '=(.*)$', 'm')) || [])[1];
const su = get('SUPABASE_URL');
const sk = get('SUPABASE_SERVICE_ROLE_KEY');
const M = 'https://motoroute-api-8fi9.onrender.com';
const G = 'https://garage-api-4a7o.onrender.com';
const h = { apikey: sk, Authorization: 'Bearer ' + sk };
const TS = Date.now();
const EMAIL = `admin-e2e-${TS}@gmail.com`;

// 1. Register ueber API
let r = await fetch(`${M}/v1/auth/register`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ email: EMAIL, password: 'Diag1234!', displayName: 'Admin E2E' }),
});
const reg = await r.json();
const userId = reg.user?.id;
console.log('1. register:', r.status, userId ? 'user=' + userId.slice(0, 8) + '…' : JSON.stringify(reg).slice(0, 100));

// 2. Zum Admin befördern
r = await fetch(`${su}/rest/v1/users?id=eq.${userId}`, {
  method: 'PATCH',
  headers: { ...h, 'Content-Type': 'application/json', Prefer: 'return=minimal' },
  body: JSON.stringify({ role: 'admin' }),
});
console.log('2. promote to admin:', r.status);

// 3. Frisch einloggen (Token ohne Rolle cachen)
r = await fetch(`${M}/v1/auth/login`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ email: EMAIL, password: 'Diag1234!' }),
});
const login = await r.json();
const tok = login.accessToken;
const ah = { Authorization: 'Bearer ' + tok };

r = await fetch(`${M}/v1/users/me`, { headers: ah });
const me = await r.json();
console.log('3. users/me role:', r.status, '->', me.role);

// 4. Chat-Admin-Reports
r = await fetch(`${M}/v1/chat/admin/reports?status=pending`, { headers: ah });
const rep = r.ok ? await r.json() : await r.text();
console.log('4. chat admin reports:', r.status, r.ok ? JSON.stringify(rep).slice(0, 60) : rep);

// 5. Marketplace-Admin
r = await fetch(`${M}/v1/marketplace/admin/reports?status=pending`, { headers: ah });
console.log('5. marketplace admin reports:', r.status);

// 6. Garage-Admin via Provision
r = await fetch(`${M}/v1/users/me/garage-ticket`, { method: 'POST', headers: ah });
const t = await r.json();
r = await fetch(`${G}/api/auth/provision`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ ticket: t.ticket }),
});
const prov = await r.json();
console.log('6. garage provision:', r.status, '-> role=' + prov.user?.role);

// 7. Aufräumen: DB-Zeile + Auth-User löschen
await fetch(`${su}/rest/v1/users?id=eq.${userId}`, { method: 'DELETE', headers: h });
r = await fetch(`${su}/auth/v1/admin/users/${userId}`, { method: 'DELETE', headers: h });
console.log('7. cleanup:', r.status);
console.log(EMAIL, 'gelöscht.');

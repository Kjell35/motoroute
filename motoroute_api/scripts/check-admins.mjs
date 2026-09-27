// Admin-Rollen-Check in der Live-DB. Nutzung: node scripts/check-admins.mjs
import fs from 'fs';

const env = fs.readFileSync('.env', 'utf8');
const get = (k) => (env.match(new RegExp('^' + k + '=(.*)$', 'm')) || [])[1];
const su = get('SUPABASE_URL');
const sk = get('SUPABASE_SERVICE_ROLE_KEY');
const h = { apikey: sk, Authorization: 'Bearer ' + sk };

let r = await fetch(`${su}/rest/v1/users?select=role&role=eq.admin`, { headers: h });
const admins = await r.json();
console.log('1. Admin-Konten in DB:', r.status, Array.isArray(admins) ? admins.length + ' admin(s)' : '?');

r = await fetch(`${su}/rest/v1/users?select=id,role&limit=50`, { headers: h });
const all = await r.json();
const roles = {};
for (const u of all) roles[u.role] = (roles[u.role] || 0) + 1;
console.log('2. Rollenverteilung (erste 50):', JSON.stringify(roles));

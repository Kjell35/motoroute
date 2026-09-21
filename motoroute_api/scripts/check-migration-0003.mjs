// Prüf-Skript: Sind die Spalten der Migration 0003 in der Live-DB?
// Nutzung: node scripts/check-migration-0003.mjs
import fs from 'fs';

const env = fs.readFileSync('.env', 'utf8');
const get = (k) => (env.match(new RegExp('^' + k + '=(.*)$', 'm')) || [])[1];
const su = get('SUPABASE_URL');
const sk = get('SUPABASE_SERVICE_ROLE_KEY');

const r = await fetch(
  `${su}/rest/v1/users?select=first_name,chat_name_mode,chat_display_name,plan&limit=1`,
  { headers: { apikey: sk, Authorization: `Bearer ${sk}` } },
);
console.log('HTTP', r.status);
const body = await r.text();
console.log(body.slice(0, 300));
if (r.status === 200) {
  console.log('=> Migration 0003 ist LIVE (alle 4 Spalten erreichbar).');
} else {
  console.log('=> Migration fehlt oder Schema-Cache alt. SQL-Editor ausführen.');
}

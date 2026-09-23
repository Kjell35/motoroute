// Prüft, ob Migration 0004 (Fahrhistorie) in der Live-DB ist.
// Nutzung: node scripts/check-migration-0004.mjs
import fs from 'fs';

const env = fs.readFileSync('.env', 'utf8');
const get = (k) => (env.match(new RegExp('^' + k + '=(.*)$', 'm')) || [])[1];
const su = get('SUPABASE_URL');
const sk = get('SUPABASE_SERVICE_ROLE_KEY');

const tables = ['ride_history', 'place_visits'];
let ok = true;

for (const t of tables) {
  const r = await fetch(`${su}/rest/v1/${t}?select=id&limit=1`, {
    headers: { apikey: sk, Authorization: `Bearer ${sk}` },
  });
  if (r.ok) {
    console.log(`OK   ${t} existiert`);
  } else {
    ok = false;
    const body = await r.text();
    console.log(`FEHLT ${t}: ${r.status} ${body.slice(0, 120)}`);
  }
}

// users-Flags prüfen
const u = await fetch(`${su}/rest/v1/users?select=auth_privacy,share_rides,share_places,hide_start_end,ride_history_enabled&limit=1`, {
  headers: { apikey: sk, Authorization: `Bearer ${sk}` },
});
if (u.ok) {
  console.log('OK   users-Privacy-Flags existieren');
} else {
  ok = false;
  console.log(`FEHLT users-Flags: ${u.status} ${(await u.text()).slice(0, 200)}`);
}

process.exit(ok ? 0 : 1);

// Prüfskript: Ist Migration 0005 (poi-Tabelle) live?
// Nutzung: node scripts/check-migration-0005.mjs
import fs from 'fs';

const env = fs.readFileSync('.env', 'utf8');
const get = (k) => (env.match(new RegExp('^' + k + '=(.*)$', 'm')) || [])[1];
const su = get('SUPABASE_URL');
const sk = get('SUPABASE_SERVICE_ROLE_KEY');

const r = await fetch(`${su}/rest/v1/poi?select=id,category,name&limit=1`, {
  headers: { apikey: sk, Authorization: `Bearer ${sk}` },
});
if (r.status === 200) {
  console.log('OK   poi-Tabelle existiert (Migration 0005 live).');
} else {
  console.log(`FAIL poi-Tabelle fehlt (HTTP ${r.status}) - Migration 0005 im SQL-Editor ausführen.`);
  process.exitCode = 1;
}

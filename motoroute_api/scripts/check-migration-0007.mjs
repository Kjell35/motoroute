// Prueft, ob die Migration 0007 (Reviews + Notifications) live ist.
// Nutzung: node scripts/check-migration-0007.mjs  (liest .env)
import fs from 'fs';

const env = fs.readFileSync('.env', 'utf8');
const get = (k) => (env.match(new RegExp('^' + k + '=(.*)$', 'm')) || [])[1];
const su = get('SUPABASE_URL');
const sk = get('SUPABASE_SERVICE_ROLE_KEY');

if (!sk) {
  console.error('FAIL SUPABASE_SERVICE_ROLE_KEY fehlt in .env');
  process.exit(1);
}

const headers = { apikey: sk, Authorization: `Bearer ${sk}` };
let ok = true;

for (const table of ['marketplace_reviews', 'notifications']) {
  const r = await fetch(`${su}/rest/v1/${table}?select=id&limit=1`, { headers });
  if (r.ok) {
    console.log(`OK  ${table} erreichbar`);
  } else {
    ok = false;
    console.log(`FAIL ${table}: HTTP ${r.status} (Migration 0007 ausfuehren)`);
  }
}

// review_count/review_avg auf listings?
const r2 = await fetch(
  `${su}/rest/v1/marketplace_listings?select=review_count,review_avg&limit=1`,
  { headers },
);
if (r2.ok) {
  console.log('OK  marketplace_listings.review_count/avg Spalten vorhanden');
} else {
  ok = false;
  console.log(`FAIL review_count-Spalten: HTTP ${r2.status}`);
}

console.log(ok ? '\nMigration 0007 ist live.' : '\nMigration 0007 FEHLT - SQL im Supabase-Editor ausfuehren.');
process.exit(ok ? 0 : 1);

// Prueft, ob die Marktplatz-Migration 0006 in der Live-DB angekommen ist.
// Nutzung: node scripts/check-migration-0006.mjs  (liest .env)
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

let failures = 0;
const check = async (label, url) => {
  try {
    const res = await fetch(url, { headers });
    if (res.ok) {
      console.log(`OK   ${label}`);
    } else {
      console.log(`FAIL ${label} (HTTP ${res.status})`);
      failures++;
    }
  } catch (e) {
    console.log(`FAIL ${label} (${e.message})`);
    failures++;
  }
};

// Kerntabellen des Marktplatzes
await check('marketplace_listings', `${su}/rest/v1/marketplace_listings?select=id&limit=1`);
await check('marketplace_categories', `${su}/rest/v1/marketplace_categories?select=key&limit=3`);
await check('marketplace_subcategories', `${su}/rest/v1/marketplace_subcategories?select=key&limit=3`);
await check('marketplace_favorites', `${su}/rest/v1/marketplace_favorites?select=user_id&limit=1`);
await check('marketplace_reports', `${su}/rest/v1/marketplace_reports?select=id&limit=1`);
await check('users.role-Spalte', `${su}/rest/v1/users?select=role&limit=1`);
await check('poi (Migration 0005)', `${su}/rest/v1/poi?select=id&limit=1`);

// Storage-Bucket der Produktfotos
try {
  const res = await fetch(`${su}/storage/v1/bucket`, { headers });
  const buckets = await res.json();
  const has = Array.isArray(buckets) && buckets.some((b) => b.id === 'marketplace-photos');
  console.log(has ? 'OK   storage-bucket marketplace-photos' : 'FAIL storage-bucket marketplace-photos fehlt');
  if (!has) failures++;
} catch (e) {
  console.log(`FAIL storage-bucket (${e.message})`);
  failures++;
}

console.log(failures === 0
  ? '\nAlle Marktplatz-Objekte live. Migration 0006 ist durch.'
  : `\n${failures} Pruefung(en) fehlgeschlagen - Migration 0006 im Supabase-SQL-Editor ausfuehren.`);
process.exit(failures === 0 ? 0 : 1);

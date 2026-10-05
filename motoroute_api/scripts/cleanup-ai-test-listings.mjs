// DB-Aufräumen (Offene Aufgabe 3): Die 6 KI-Test-Listings ("Toaster",
// review_status='rejected') werden final gesperrt (status='blocked'),
// damit sie eindeutig als entsorgt gelten und nie wieder in irgendeiner
// Queue/Verwaltung auftauchen. Öffentlich sichtbar sind sie ohnehin nie
// (List-Filter verlangt status='active' UND review_status='approved').
//
// Nutzung (auf dem PC mit motoroute_api/.env):
//   node scripts/cleanup-ai-test-listings.mjs            # Dry-Run: nur anzeigen
//   node scripts/cleanup-ai-test-listings.mjs --apply    # wirklich setzen
//
// Benötigt SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY in motoroute_api/.env.
import fs from 'fs';

const env = fs.readFileSync('.env', 'utf8');
const get = (k) => (env.match(new RegExp('^' + k + '=(.*)$', 'm')) || [])[1];
const su = get('SUPABASE_URL');
const sk = get('SUPABASE_SERVICE_ROLE_KEY');
const apply = process.argv.includes('--apply');

if (!su || !sk) {
  console.error('FAIL SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY fehlen in motoroute_api/.env');
  process.exit(1);
}

const headers = { apikey: sk, Authorization: `Bearer ${sk}`, 'Content-Type': 'application/json' };

// 1) Kandidaten suchen: KI-Test-Listings, endgültig abgelehnt.
const url =
  `${su}/rest/v1/marketplace_listings` +
  `?select=id,title,status,review_status,review_reason,created_at` +
  `&review_status=eq.rejected&title=ilike.*Toaster*&order=created_at.asc`;
const r = await fetch(url, { headers });
if (!r.ok) {
  console.error(`FAIL Suche: ${r.status} ${(await r.text()).slice(0, 200)}`);
  process.exit(1);
}
const rows = await r.json();
console.log(`Gefunden: ${rows.length} KI-Test-Listing(s) ("Toaster", review_status='rejected')`);
for (const row of rows) {
  console.log(`  - ${row.id} "${row.title}" status=${row.status} created=${row.created_at}`);
}

if (rows.length === 0) {
  console.log('Nichts zu tun.');
  process.exit(0);
}

if (!apply) {
  console.log("\nDRY-RUN: mit --apply werden alle gefundenen Listings auf status='blocked' gesetzt.");
  process.exit(0);
}

// 2) status='blocked' setzen (ausschliesslich die gefundenen IDs).
const ids = rows.map((row) => row.id);
const patch = await fetch(`${su}/rest/v1/marketplace_listings?id=in.(${ids.join(',')})`, {
  method: 'PATCH',
  headers,
  body: JSON.stringify({ status: 'blocked' }),
});
if (!patch.ok) {
  console.error(`FAIL Update: ${patch.status} ${(await patch.text()).slice(0, 200)}`);
  process.exit(1);
}
console.log(`OK ${ids.length} Listing(s) auf status='blocked' gesetzt.`);

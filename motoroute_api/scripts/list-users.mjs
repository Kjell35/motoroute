// Listet alle Benutzer mit aktueller Rolle (für die Admin-Vergabe).
// Nutzung: node scripts/list-users.mjs
import fs from 'fs';

const env = fs.readFileSync('.env', 'utf8');
const get = (k) => (env.match(new RegExp('^' + k + '=(.*)$', 'm')) || [])[1];
const su = get('SUPABASE_URL');
const sk = get('SUPABASE_SERVICE_ROLE_KEY');

const r = await fetch(`${su}/rest/v1/users?select=id,username,email,display_name,role,created_at&order=created_at.asc`, {
  headers: { apikey: sk, Authorization: `Bearer ${sk}` },
});
const users = await r.json();
if (!Array.isArray(users)) {
  console.error('Fehler:', JSON.stringify(users).slice(0, 200));
  process.exit(1);
}
console.log(`Angemeldete Benutzer (${users.length}):`);
for (const u of users) {
  console.log(`- ${(u.username || u.email || u.id)} | Rolle: ${u.role ?? 'user'} | ${u.email ?? ''} | seit ${(u.created_at ?? '').slice(0, 10)}`);
}

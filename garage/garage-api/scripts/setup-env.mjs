// Diagnose + Migration der .env-Werte:
//  1. Liest die vom Nutzer ausgefuellte .env.example (DATABASE_URL, ADMIN_*)
//  2. Testet, welche Postgres-Variante erreichbar ist (Direkt vs. Pooler)
//  3. Schreibt die funktionierende Variante in die echte .env
// Gibt NIEMALS Passwoerter aus. Nutzung: node scripts/setup-env.mjs
import fs from 'fs';
import net from 'net';
import dns from 'dns/promises';

const readVal = (f, k) => {
  const m = fs.readFileSync(f, 'utf8').match(new RegExp('^' + k + '="?([^"\\r\\n]*)"?', 'm'));
  return m ? m[1].trim() : undefined;
};

const url = readVal('.env.example', 'DATABASE_URL');
const adminEmail = readVal('.env.example', 'ADMIN_EMAIL');
const adminPassword = readVal('.env.example', 'ADMIN_PASSWORD');
if (!url || !adminEmail || !adminPassword) {
  console.error('FAIL .env.example unvollstaendig (DATABASE_URL/ADMIN_EMAIL/ADMIN_PASSWORD)');
  process.exit(1);
}

let u;
try { u = new URL(url); } catch { console.error('FAIL DATABASE_URL ist kein gueltiger URL'); process.exit(1); }
if (!u.password || u.password.includes('[YOUR-PASSWORD]')) {
  console.error('FAIL Passwort nicht ersetzt ([YOUR-PASSWORD] steht noch drin)');
  process.exit(1);
}

let finalUrl = url;
const host = u.hostname;

// Supabase-Direktverbindung? (db.<ref>.supabase.co) - die ist heute oft
// IPv6-only und scheitert an heimischen Anschluessen. Dann: Session-Pooler.
if (/\.supabase\.co$/.test(host)) {
  const ref = host.match(/^db\.([a-z0-9]{10,})\./)?.[1];
  let hasV4 = false;
  try { hasV4 = (await dns.resolve4(host)).length > 0; } catch { /* kein A-Record */ }
  if (!hasV4 && ref) {
    const pool = new URL(url);
    pool.hostname = 'aws-0-eu-central-1.pooler.supabase.com';
    pool.username = 'postgres.' + ref;
    finalUrl = pool.toString();
    console.log('INFO Direkt-Host ist IPv6-only - wechsle auf Session-Pooler (IPv4-faehig)');
  } else if (ref) {
    console.log('INFO Direkt-Host hat IPv4 - Direktverbindung bleibt');
  }
}

const fin = new URL(finalUrl);
const port = Number(fin.port || 5432);
const reachable = await new Promise((resolve) => {
  const socket = net.connect({ host: fin.hostname, port });
  const t = setTimeout(() => { socket.destroy(); resolve(false); }, 8000);
  socket.once('connect', () => { clearTimeout(t); socket.destroy(); resolve(true); });
  socket.once('error', () => { clearTimeout(t); resolve(false); });
});
console.log((reachable ? 'REACHABLE ' : 'UNREACHABLE ') + fin.hostname + ':' + port);
if (!reachable) {
  console.error('FAIL Datenbank-Host nicht erreichbar - DATABASE_URL in .env.example pruefen');
  process.exit(2);
}

// In die echte .env schreiben (bestehende Zeilen wie JWT_SECRET bleiben)
let env = fs.existsSync('.env') ? fs.readFileSync('.env', 'utf8') : '';
const setEnv = (k, v) => {
  const re = new RegExp('^' + k + '=.*$', 'm');
  const line = k + '="' + v + '"';
  if (re.test(env)) env = env.replace(re, line);
  else env += (env.endsWith('\n') ? '' : '\n') + line + '\n';
};
setEnv('DATABASE_URL', finalUrl);
setEnv('ADMIN_EMAIL', adminEmail);
setEnv('ADMIN_PASSWORD', adminPassword);
fs.writeFileSync('.env', env);
console.log('ENV-WRITTEN .env aktualisiert (Werte aus .env.example uebernommen, Passwoerter nie angezeigt)');

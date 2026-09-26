// E2E: Registrierung -> Angebot (BMW-Auspuff) -> Favorit anlegen -> Favoriten-Liste.
// Nutzung: node scripts/e2e-favorites.mjs
const LIVE = process.env.LIVE || 'https://motoroute-api-8fi9.onrender.com';
const TS = Date.now();

async function j(method, path, token, body, isForm) {
  const r = await fetch(LIVE + path, {
    method,
    headers: {
      ...(token ? { Authorization: 'Bearer ' + token } : {}),
      ...(isForm ? {} : { 'Content-Type': 'application/json' }),
    },
    body: body ? (isForm ? body : JSON.stringify(body)) : undefined,
  });
  const text = await r.text();
  let parsed;
  try { parsed = JSON.parse(text); } catch { parsed = text.slice(0, 200); }
  return { status: r.status, body: parsed };
}

// 1. Registrieren + Login
const email = `fav-e2e-${TS}@example.com`;
const reg = await j('POST', '/v1/auth/register', null, { email, password: 'Test1234!' });
console.log('1. register:', reg.status);
const login = await j('POST', '/v1/auth/login', null, { email, password: 'Test1234!' });
const token = login.body.accessToken || login.body.access_token;
console.log('2. login:', login.status, token ? 'token ok' : 'KEIN TOKEN ' + JSON.stringify(login.body).slice(0, 120));

// 2. Angebot erstellen (wird freigegeben)
const create = await j('POST', '/v1/marketplace/listings', token, {
  title: 'BMW R1250 GS Auspuff',
  description: 'Originale Akrapovic-Anlage, kurvig gefahren, Top-Zustand.',
  priceCents: 45000,
  condition: 'gut',
  category: 'motorradteile',
  subcategory: 'auspuff',
  brand: 'BMW',
  model: 'R1250 GS',
  locationLabel: 'München',
  shipping: true,
});
console.log('3. create listing:', create.status, 'review:', create.body?.listing?.reviewStatus ?? create.body?.review_status ?? JSON.stringify(create.body).slice(0, 150));
const listingId = create.body?.listing?.id ?? create.body?.id;
if (!listingId) { console.error('keine listing id:', JSON.stringify(create.body).slice(0, 300)); process.exit(1); }

// 3. Favorit anlegen
const fav = await j('POST', `/v1/marketplace/me/favorites/${listingId}`, token);
console.log('4. add favorite:', fav.status, JSON.stringify(fav.body).slice(0, 150));

// 4. Favoriten-Liste
const list = await j('GET', '/v1/marketplace/me/favorites', token);
const listings = list.body?.listings ?? [];
console.log('5. list favorites:', list.status, 'count:', listings.length, listings[0] ? `title=${listings[0].title}` : JSON.stringify(list.body).slice(0, 200));

console.log(listings.length === 1 ? '\nERGEBNIS: OK — Favoriten-Liste funktioniert' : '\nERGEBNIS: FEHLER — Liste bleibt leer');
process.exit(listings.length === 1 ? 0 : 1);

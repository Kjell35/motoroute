// DI-Smoke-Test (CJS, da dist/ CommonJS ist): Der NestJS-DI-Container muss
// die komplette App aufloesen koennen. Genau hier starb der Render-Deploy
// von v0.3.15 (update_failed), obwohl alle Unit-Tests gruen waren - Tests
// mocken Provider, der echte Bootstrap nicht. Nutzung: node scripts/di-smoke.cjs
const { AppModule } = require('../dist/app.module.js');
const { NestFactory } = require('@nestjs/core');

(async () => {
  try {
    const app = await NestFactory.createApplicationContext(AppModule, { logger: false });
    const mp = app.get('MarketplaceService');
    console.log('DI-OK: MarketplaceService aufloesbar; KI konfiguriert =', mp.review.configured);
    await app.close();
    process.exit(0);
  } catch (err) {
    console.log('DI-FAIL:', (err && err.message ? err.message : String(err)).split('\n')[0]);
    process.exit(1);
  }
})();

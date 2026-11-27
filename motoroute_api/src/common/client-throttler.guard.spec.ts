import { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Test } from '@nestjs/testing';
import { ThrottlerModule } from '@nestjs/throttler';
import { PairingController } from '../modules/pairing/pairing.controller';
import { PairingService } from '../modules/pairing/pairing.service';

/**
 * Prüft den Schlüssel der Drosselung über echtes HTTP.
 *
 * Vorher zählte der Throttler auf `req.ip`; hinter dem Render-Proxy waren das
 * wechselnde Adressen, sodass 5/min je Anfrage in einem anderen Fenster
 * landeten (live: 4,3,2,1 dann wieder 4,3,2,1). Der Test schickt denselben
 * Client mit unterschiedlichen Proxy-Einträgen im X-Forwarded-For: der Zähler
 * muss trotzdem einer sein.
 */
describe('ClientThrottlerGuard: Schlüssel aus X-Forwarded-For', () => {
  let app: INestApplication;
  let baseUrl: string;
  const start = jest.fn();

  beforeAll(async () => {
    start.mockResolvedValue({
      token: 'ABC234',
      plan_url: 'https://api.example.org/plan/ABC234',
      plan_urls: ['https://api.example.org/plan/ABC234'],
      expires_in_seconds: 7200,
    });

    const moduleRef = await Test.createTestingModule({
      imports: [ThrottlerModule.forRoot([{ ttl: 60_000, limit: 120 }])],
      controllers: [PairingController],
      providers: [
        {
          provide: PairingService,
          useValue: {
            start,
            getPoints: async () => [],
            savePoints: async () => [],
          },
        },
        { provide: ConfigService, useValue: new ConfigService({}) },
      ],
    }).compile();

    app = moduleRef.createNestApplication();
    await app.init();
    await app.listen(0, '127.0.0.1');
    baseUrl = await app.getUrl();
  });

  afterAll(async () => {
    await app.close();
  });

  async function post(forwardedFor?: string): Promise<{ status: number; remaining: string | null }> {
    const response = await fetch(`${baseUrl}/api/v1/pairing/start`, {
      method: 'POST',
      headers: forwardedFor ? { 'x-forwarded-for': forwardedFor } : undefined,
    });
    return { status: response.status, remaining: response.headers.get('x-ratelimit-remaining') };
  }

  it('zählt denselben Client auch bei wechselnden Proxy-Einträgen als einen', async () => {
    const calls: { status: number; remaining: string | null }[] = [];
    for (let hop = 0; hop < 6; hop += 1) {
      // Linker Eintrag bleibt: derselbe Client. Rechts wandert der Hop.
      calls.push(await post(`203.0.113.9, 10.0.0.${hop + 1}`));
    }

    expect(calls.map((call) => call.status)).toEqual([200, 200, 200, 200, 200, 429]);
    expect(calls.slice(0, 5).map((call) => call.remaining)).toEqual(['4', '3', '2', '1', '0']);
  });

  it('lässt einen anderen Client davon unberührt', async () => {
    const call = await post('198.51.100.4, 10.0.0.7');

    expect(call.status).toBe(200);
    expect(call.remaining).toBe('4');
  });

  it('fällt ohne X-Forwarded-For auf req.ip zurück', async () => {
    const statuses: number[] = [];
    for (let index = 0; index < 6; index += 1) {
      statuses.push((await post()).status);
    }

    expect(statuses).toEqual([200, 200, 200, 200, 200, 429]);
  });
});

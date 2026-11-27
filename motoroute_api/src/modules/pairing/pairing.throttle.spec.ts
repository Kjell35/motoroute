import { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Test } from '@nestjs/testing';
import { ThrottlerModule } from '@nestjs/throttler';
import { PairingController } from './pairing.controller';
import { PairingService } from './pairing.service';

/**
 * Prüft die Drosselung von POST …/pairing/start über echtes HTTP: sechs
 * Aufrufe, der sechste muss 429 sein. Ohne diesen Test bliebe nur „der
 * Decorator steht da" - der Throttler war zuvor nirgends als Guard gebunden.
 */
describe('PairingController: Drosselung von start()', () => {
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

  async function post(): Promise<number> {
    const response = await fetch(`${baseUrl}/api/v1/pairing/start`, { method: 'POST' });
    return response.status;
  }

  it('erlaubt 5 Starts pro Minute, der sechste ist 429', async () => {
    const statuses: number[] = [];
    for (let index = 0; index < 6; index += 1) {
      statuses.push(await post());
    }

    expect(statuses.slice(0, 5)).toEqual([200, 200, 200, 200, 200]);
    expect(statuses[5]).toBe(429);
    expect(start).toHaveBeenCalledTimes(5);
  });

  it('der Abruf per GET bleibt von der Start-Drosselung unberührt', async () => {
    const response = await fetch(`${baseUrl}/api/v1/pairing/ABC234`);
    expect(response.status).toBe(200);
  });
});

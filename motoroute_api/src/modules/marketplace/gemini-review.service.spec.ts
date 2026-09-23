import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';
import { GeminiReviewService } from './gemini-review.service';

/**
 * Die kombinierte KI-Pruefung (Text-Klassifikator + Gemini-Vision) ist
 * der Kern der Marktplatz-Anforderung (Punkt 5/7/8/9): Nur eindeutig
 * fahrzeugbezogene Angebote werden automatisch veroeffentlicht.
 */
jest.mock('axios');
const mockedAxios = axios as jest.Mocked<typeof axios>;

const IMG_BRAKE = 'https://example.com/bremsscheibe.jpg';
const IMG_TOASTER = 'https://example.com/toaster.jpg';

function mockImageDownload(): void {
  mockedAxios.get.mockResolvedValue({
    data: new ArrayBuffer(4),
    headers: { 'content-type': 'image/jpeg' },
  } as never);
}

/** Gemini antwortet mit dem gegebenen relation-JSON. */
function mockGemini(relation: string, label = 'Objekt'): void {
  mockedAxios.post.mockResolvedValue({
    data: { candidates: [{ content: { parts: [{ text: JSON.stringify({ label, relation }) }] } }] },
  } as never);
}

async function service(): Promise<GeminiReviewService> {
  const moduleRef = await Test.createTestingModule({
    providers: [
      GeminiReviewService,
      { provide: ConfigService, useValue: { get: () => 'test-gemini-api-key-1234567890' } },
    ],
  }).compile();
  return moduleRef.get(GeminiReviewService);
}

describe('GeminiReviewService - kombinierte KI-Pruefung', () => {
  beforeEach(() => {
    mockedAxios.get.mockReset();
    mockedAxios.post.mockReset();
  });

  it('lehnt eindeutig fremde Produkte ab (Toaster) - auch mit Bild', async () => {
    mockImageDownload();
    mockGemini('unrelated', 'Toaster');
    const svc = await service();

    const result = await svc.review({
      title: 'Toaster',
      description: '2 Scheiben, Edelstahl',
      imageUrls: [IMG_TOASTER],
    });

    expect(result.decision).toBe('REJECT');
    expect(result.textReview.verdict).toBe('FOREIGN');
  });

  it('veroeffentlicht eindeutiges Fahrzeugteil mit passendem Foto (BMW Auspuff)', async () => {
    mockImageDownload();
    mockGemini('motorcycle_part', 'Motorrad-Auspuff');
    const svc = await service();

    const result = await svc.review({
      title: 'BMW R1250 Auspuff',
      description: 'Originales Auspuff-Endtopf, wenig Kilometer',
      brand: 'BMW',
      imageUrls: [IMG_BRAKE],
    });

    expect(result.decision).toBe('APPROVE');
  });

  it('blockiert Widerspruch: Fahrzeugteil-Text, aber Toaster-Foto (Punkt 8)', async () => {
    mockImageDownload();
    mockGemini('unrelated', 'Toaster');
    const svc = await service();

    const result = await svc.review({
      title: 'BMW Motorrad Auspuff',
      description: 'Originales Teil',
      imageUrls: [IMG_TOASTER],
    });

    expect(result.decision).toBe('REJECT');
    expect(result.reason).toContain('kein Fahrzeugteil');
  });

  it('stellt unsicheren Text ohne Belastung zur manuellen Pruefung (Punkt 9)', async () => {
    mockImageDownload();
    mockGemini('unclear');
    const svc = await service();

    const result = await svc.review({
      title: 'Wie neu',
      description: 'wurde 2x benutzt',
      imageUrls: [IMG_BRAKE],
    });

    expect(result.decision).toBe('MANUAL_REVIEW');
  });

  it('Deko-Beispiel der Anforderung: Shimano Fahrradschaltung wird zugelassen', async () => {
    mockImageDownload();
    mockGemini('bicycle_part', 'Schaltwerk');
    const svc = await service();

    const result = await svc.review({
      title: 'Shimano Fahrradschaltung',
      description: 'Deore XT, 11-fach',
      brand: 'Shimano',
      imageUrls: [IMG_BRAKE],
    });

    expect(result.decision).toBe('APPROVE');
  });

  it('Gemini-Ausfall fuehrt NICHT zur Veroeffentlichung unsicherer Faelle', async () => {
    mockImageDownload();
    mockedAxios.post.mockRejectedValue(new Error('gemini down'));
    const svc = await service();

    const result = await svc.review({
      title: 'Wie neu',
      description: 'wurde 2x benutzt',
      imageUrls: [IMG_BRAKE],
    });

    // Text = UNCERTAIN, Bild = error -> niemals APPROVE.
    expect(result.decision).toBe('MANUAL_REVIEW');
  });
});

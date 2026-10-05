import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';
import { ChatModerationService } from './moderation.service';

/**
 * Automatische KI-Moderation: klare Verstosse verstecken + KI-Meldung
 * (reporter == reported) erzeugen; Fehler und Freistosse degradieren
 * still, ohne die Nachricht zu veraendern.
 */
jest.mock('axios');
const mockedAxios = axios as jest.Mocked<typeof axios>;

function supabaseMock() {
  const chain = {
    update: jest.fn().mockReturnThis(),
    eq: jest.fn().mockResolvedValue({ error: null }),
    insert: jest.fn().mockResolvedValue({ error: null }),
  };
  return {
    from: jest.fn(() => chain),
    _chain: chain,
  };
}

async function service(db: ReturnType<typeof supabaseMock>, key = 'test-gemini-api-key-1234567890') {
  const moduleRef = await Test.createTestingModule({
    providers: [
      ChatModerationService,
      { provide: ConfigService, useValue: { get: (k: string) => (k === 'GEMINI_API_KEY' ? key : null) } },
      { provide: SUPABASE_CLIENT, useValue: db },
    ],
  }).compile();
  return moduleRef.get(ChatModerationService);
}

// SUPABASE_CLIENT wird als Symbol exportiert -> direkt referenzieren.
import { SUPABASE_CLIENT } from '../../supabase/supabase.module';

function geminiAnswer(violation: boolean, category = 'insult'): void {
  mockedAxios.post.mockResolvedValue({
    data: {
      candidates: [
        {
          content: {
            parts: [
              {
                text: JSON.stringify({
                  violation,
                  category,
                  excerpt: 'Beleidigung',
                  explanation: 'Klare Beleidigung',
                }),
              },
            ],
          },
        },
      ],
    },
  } as never);
}

describe('ChatModerationService', () => {
  beforeEach(() => {
    mockedAxios.post.mockReset();
  });

  it('versteckt klare Verstoesse und legt KI-Meldung an (reporter == reported)', async () => {
    const db = supabaseMock();
    geminiAnswer(true, 'insult');
    const svc = await service(db);

    await svc.reviewMessage({
      messageId: 'msg-1',
      senderId: 'user-1',
      conversationId: 'conv-1',
      content: 'Du bist wirklich ein genuin mieser Abschaum, verschwinde!',
    });

    expect(db.from).toHaveBeenCalledWith('messages');
    expect(db.from).toHaveBeenCalledWith('reports');
    expect(db._chain.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        reporter_id: 'user-1',
        reported_user_id: 'user-1', // KI-Konvention: reporter == reported
        message_id: 'msg-1',
        reason: 'insult',
      }),
    );
  });

  it('unbedenkliche Nachrichten bleiben unangetastet', async () => {
    const db = supabaseMock();
    geminiAnswer(false);
    const svc = await service(db);

    await svc.reviewMessage({
      messageId: 'msg-2',
      senderId: 'user-2',
      conversationId: 'conv-1',
      content: 'Morgen Tour zum Stilfser Joch, wer faehrt mit?',
    });

    expect(db._chain.update).not.toHaveBeenCalled();
    expect(db._chain.insert).not.toHaveBeenCalled();
  });

  it('Gemini-Fehler veraendert die Nachricht nicht (still degradieren)', async () => {
    const db = supabaseMock();
    mockedAxios.post.mockRejectedValue(new Error('gemini down'));
    const svc = await service(db);

    await svc.reviewMessage({
      messageId: 'msg-3',
      senderId: 'user-3',
      conversationId: 'conv-1',
      content: 'irgendeine laengere Nachricht zum Testen des Fehlverhaltens',
    });

    expect(db._chain.update).not.toHaveBeenCalled();
  });

  it('kurze Nachrichten werden gar nicht geprueft (Kosten/Cooldown)', async () => {
    const db = supabaseMock();
    const svc = await service(db);

    await svc.reviewMessage({
      messageId: 'msg-4',
      senderId: 'user-4',
      conversationId: 'conv-1',
      content: 'ok lol',
    });

    expect(mockedAxios.post).not.toHaveBeenCalled();
  });

  it('ohne API-Key passiert nichts', async () => {
    const db = supabaseMock();
    const svc = await service(db, null as unknown as string);

    await svc.reviewMessage({
      messageId: 'msg-5',
      senderId: 'user-5',
      conversationId: 'conv-1',
      content: 'eine laengere Nachricht, die normalerweise geprueft wuerde',
    });

    expect(mockedAxios.post).not.toHaveBeenCalled();
  });
});

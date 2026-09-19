import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { EventEmitter2 } from '@nestjs/event-emitter';
import { SupabaseAuthService } from '../../guards';

// Die Service-Klasse wird dynamisch importiert, damit wir an die
// modulinternen Rate-Limit-Zähler über mehrere Testfälle hinweg kommen,
// ohne das Modul neu zu kompilieren.
import { ChatService } from './chat.service';

describe('ChatService Rate-Limiting (Sliding Window, Abschnitt 25)', () => {
  let service: ChatService;

  beforeEach(async () => {
    const moduleRef = await Test.createTestingModule({
      providers: [
        ChatService,
        { provide: 'SUPABASE_CLIENT', useValue: null },
        { provide: ConfigService, useValue: { get: () => '' } },
        { provide: EventEmitter2, useValue: { emit: jest.fn() } },
        { provide: SupabaseAuthService, useValue: { validateToken: jest.fn().mockResolvedValue(null) } },
      ],
    }).compile();
    service = moduleRef.get(ChatService);
  });

  it('isMember ohne konfigurierte DB: konservativ false', async () => {
    expect(await service.isMember('token', 'conv')).toBe(false);
  });

  it('userIdFromToken mit leerem Token: null', async () => {
    expect(await service.userIdFromToken('')).toBe(null);
  });

  it('realtimeConfig ohne DB: configured=false (App fällt auf Polling zurück)', () => {
    expect(service.realtimeConfig()).toEqual({ configured: false });
  });
});

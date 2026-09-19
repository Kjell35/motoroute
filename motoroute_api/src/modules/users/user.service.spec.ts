import { HttpException, HttpStatus } from '@nestjs/common';
import { UserService } from './user.service';

type SupabaseResult = { data: unknown; error: { message: string; code?: string } | null };

function mockSupabase() {
  return {
    from: jest.fn().mockReturnThis(),
    select: jest.fn().mockReturnThis(),
    eq: jest.fn().mockReturnThis(),
    update: jest.fn().mockReturnThis(),
    upsert: jest.fn().mockReturnThis(),
    maybeSingle: jest.fn(),
    single: jest.fn(),
  };
}

describe('UserService', () => {
  it('getMe returns the profile row', async () => {
    const sb = mockSupabase();
    sb.maybeSingle.mockResolvedValue({
      data: { id: 'u-1', email: 'a@b.de', display_name: 'Rider' },
      error: null,
    } as SupabaseResult);
    const service = new UserService(sb as never);

    const result = await service.getMe({ id: 'u-1', email: 'a@b.de' });

    expect(result).toEqual({ id: 'u-1', email: 'a@b.de', display_name: 'Rider' });
    expect(sb.eq).toHaveBeenCalledWith('id', 'u-1');
  });

  it('getMe falls back to a default profile when the row does not exist yet', async () => {
    const sb = mockSupabase();
    sb.maybeSingle.mockResolvedValue({ data: null, error: null } as SupabaseResult);
    const service = new UserService(sb as never);

    const result = await service.getMe({ id: 'u-1' });

    expect(result).toEqual({
      id: 'u-1',
      email: null,
      display_name: null,
      avatar_url: null,
      updated_at: null,
    });
  });

  it('updateMe never accepts a user id from the DTO (id comes from JWT only)', async () => {
    const sb = mockSupabase();
    sb.single.mockResolvedValue({ data: { id: 'u-1' }, error: null } as SupabaseResult);
    const service = new UserService(sb as never);

    await service.updateMe({ id: 'u-1' }, { displayName: 'Neu' });

    // update().eq('id', jwt-user-id) - die eq-Bedingung ist die einzige
    // Zeilenauswahl, ein Body-Feld kann sie nicht überschreiben.
    expect(sb.update).toHaveBeenCalledWith(expect.objectContaining({ display_name: 'Neu' }));
    expect(sb.eq).toHaveBeenCalledWith('id', 'u-1');
  });

  it('updateMe creates the profile via upsert when no row exists (PGRST116)', async () => {
    const sb = mockSupabase();
    sb.single
      .mockResolvedValueOnce({
        data: null,
        error: { message: 'no rows', code: 'PGRST116' },
      } as SupabaseResult)
      .mockResolvedValueOnce({ data: { id: 'u-2' }, error: null } as SupabaseResult);
    const service = new UserService(sb as never);

    const result = await service.updateMe({ id: 'u-2', email: 'x@y.de' }, { displayName: 'A' });

    expect(sb.upsert).toHaveBeenCalledWith(
      expect.objectContaining({ id: 'u-2', display_name: 'A' }),
      expect.anything(),
    );
    expect(result).toEqual({ id: 'u-2' });
  });

  it('getMe maps DB errors to 500 with a machine-readable code', async () => {
    const sb = mockSupabase();
    sb.maybeSingle.mockResolvedValue({
      data: null,
      error: { message: 'connection refused' },
    } as SupabaseResult);
    const service = new UserService(sb as never);

    await expect(service.getMe({ id: 'u-1' })).rejects.toThrow(HttpException);
    try {
      await service.getMe({ id: 'u-1' });
    } catch (e) {
      expect((e as HttpException).getStatus()).toBe(HttpStatus.INTERNAL_SERVER_ERROR);
    }
  });
});

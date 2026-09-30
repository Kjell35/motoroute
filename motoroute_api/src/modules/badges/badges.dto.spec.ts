import 'reflect-metadata';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { CreateBadgeDto } from './badges.controller';

async function errorsFor(body: Record<string, unknown>) {
  const errs = await validate(plainToInstance(CreateBadgeDto, body));
  return errs.map((e) => e.property);
}

describe('CreateBadgeDto', () => {
  const ok = { title: 'Col de Test', category: 'pass', lat: '45.1', lon: '6.2' };

  it('akzeptiert gültige Eingabe (Strings werden zu Zahlen, Optionales darf fehlen)', async () => {
    expect(await errorsFor(ok)).toEqual([]);
    expect(await errorsFor({ ...ok, radiusMeters: '300', iconUrl: 'https://example.com/i.png' })).toEqual([]);
  });

  it('lehnt ungültige Kategorie, Koordinaten, Radius und http-Icons ab', async () => {
    expect(await errorsFor({ ...ok, category: 'foo' })).toContain('category');
    expect(await errorsFor({ ...ok, lat: '91' })).toContain('lat');
    expect(await errorsFor({ ...ok, lon: '-181' })).toContain('lon');
    expect(await errorsFor({ ...ok, radiusMeters: 10 })).toContain('radiusMeters');
    expect(await errorsFor({ ...ok, radiusMeters: 501 })).toContain('radiusMeters');
    expect(await errorsFor({ ...ok, iconUrl: 'http://example.com/i.png' })).toContain('iconUrl');
    expect(await errorsFor({ ...ok, title: 'x' })).toContain('title');
  });
});

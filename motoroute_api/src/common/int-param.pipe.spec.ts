import { BadRequestException } from '@nestjs/common';
import { IntParamPipe } from './int-param.pipe';

describe('IntParamPipe', () => {
  const pipe = new IntParamPipe('id');

  it('gibt eine gültige bigserial-ID als Zahl zurück', () => {
    expect(pipe.transform('42')).toBe(42);
  });

  it('akzeptiert die vom globalen ValidationPipe schon umgewandelte Zahl', () => {
    expect(pipe.transform(7)).toBe(7);
    // Ungültige Eingaben kommen dort als NaN an und müssen 400 ergeben.
    expect(() => pipe.transform(Number.NaN)).toThrow(BadRequestException);
  });

  it('lehnt Text mit 400 ab statt NaN in die Abfrage zu lassen', () => {
    expect(() => pipe.transform('abc')).toThrow(BadRequestException);
    expect(() => pipe.transform('12abc')).toThrow('id muss eine ganze Zahl sein');
  });

  it('lehnt 0, negative Werte und Zahlen über 2^53 ab', () => {
    for (const value of ['0', '-1', '99999999999999999999']) {
      expect(() => pipe.transform(value)).toThrow(BadRequestException);
    }
    expect(() => pipe.transform(-5)).toThrow(BadRequestException);
  });
});

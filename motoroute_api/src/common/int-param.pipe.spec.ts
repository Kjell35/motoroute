import { BadRequestException } from '@nestjs/common';
import { IntParamPipe } from './int-param.pipe';

describe('IntParamPipe', () => {
  const pipe = new IntParamPipe('id');

  it('gibt eine gültige bigserial-ID als Zahl zurück', () => {
    expect(pipe.transform('42')).toBe(42);
  });

  it('lehnt Text mit 400 ab statt NaN in die Abfrage zu lassen', () => {
    expect(() => pipe.transform('abc')).toThrow(BadRequestException);
    expect(() => pipe.transform('12abc')).toThrow('id muss eine ganze Zahl sein');
  });

  it('lehnt 0, negative Werte und Zahlen über 2^53 ab', () => {
    for (const value of ['0', '-1', '99999999999999999999']) {
      expect(() => pipe.transform(value)).toThrow(BadRequestException);
    }
  });
});

import { BadRequestException, PipeTransform } from '@nestjs/common';

/**
 * Prüft einen numerischen Pfadparameter (bigserial-/integer-ID).
 *
 * Vorbild ist UuidParamPipe - dort war der Fehler derselbe: der String ging
 * unverändert in die Abfrage, `Number('abc')` wurde zu NaN, Postgres antwortete
 * mit 22P02 bzw. einer Typumwandlungs-Meldung und der Client bekam einen 500
 * statt einer verständlichen 400.
 *
 * Nur für Spalten mit numerischem Schlüssel verwenden (z. B.
 * marketplace_reports.id); UUID- und text-ID-Spalten gehören an UuidParamPipe.
 */
export class IntParamPipe implements PipeTransform<string, number> {
  constructor(private readonly field: string) {}

  transform(value: string): number {
    const raw = (value ?? '').trim();
    if (!/^\d+$/.test(raw)) {
      throw new BadRequestException(`${this.field} muss eine ganze Zahl sein`);
    }
    const parsed = Number(raw);
    // bigserial reicht bis 2^63, JS-Zahlen sind nur bis 2^53 exakt - alles
    // darüber kann keine gültige ID sein, die diese API je ausgegeben hat.
    if (!Number.isSafeInteger(parsed) || parsed < 1) {
      throw new BadRequestException(`${this.field} muss eine positive ganze Zahl sein`);
    }
    return parsed;
  }
}

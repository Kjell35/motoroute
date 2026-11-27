import { BadRequestException, PipeTransform } from '@nestjs/common';

/**
 * Prüft einen numerischen Pfadparameter (bigserial-/integer-ID).
 *
 * Vorbild ist UuidParamPipe - dort war der Fehler derselbe: der String ging
 * unverändert in die Abfrage, `Number('abc')` wurde zu NaN und Postgres
 * antwortete mit einem Typfehler, sodass der Client einen 500 statt einer
 * verständlichen 400 bekam.
 *
 * Achtung: Der globale ValidationPipe läuft vor dieser Pipe und wandelt den
 * Parameter wegen des deklarierten Typs `number` bereits um. Ein ungültiger
 * Wert kommt deshalb als NaN (Zahl) hier an, ein gültiger als Zahl - deshalb
 * werden beide Formen behandelt.
 *
 * Nur für Spalten mit numerischem Schlüssel verwenden (z. B.
 * marketplace_reports.id); UUID- und text-ID-Spalten gehören an UuidParamPipe.
 */
export class IntParamPipe implements PipeTransform<string | number, number> {
  constructor(private readonly field: string) {}

  transform(value: string | number): number {
    if (typeof value === 'number') {
      if (!Number.isInteger(value) || value < 1) {
        throw new BadRequestException(`${this.field} muss eine positive ganze Zahl sein`);
      }
      return value;
    }
    const raw = String(value ?? '').trim();
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

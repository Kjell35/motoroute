import { BadRequestException, PipeTransform } from '@nestjs/common';

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Prüft einen UUID-Pfadparameter, bevor er in Postgres landet.
 *
 * Ohne diese Prüfung ging der String unverändert in die Datenbank: Postgres
 * antwortet mit 22P02 (invalid input syntax for type uuid) und der Client
 * bekam einen nackten 500 statt einer verständlichen 400 (Log: "listRoutes
 * failed: 22P02 invalid input syntax for type uuid").
 *
 * Nur für Spalten vom Typ uuid verwenden - text-IDs (z. B. poi.id) und
 * bigserial-IDs (z. B. marketplace_reports.id) würden dadurch abgewiesen.
 */
export class UuidParamPipe implements PipeTransform<string, string> {
  constructor(private readonly field: string) {}

  transform(value: string): string {
    if (!UUID_PATTERN.test(value ?? '')) {
      throw new BadRequestException(`${this.field} ist keine gültige UUID`);
    }
    return value;
  }
}

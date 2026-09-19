import { Type } from 'class-transformer';
import {
  IsEnum,
  IsLatitude,
  IsLongitude,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

/** Die 4 Meldungstypen des Community-Radars (Spiegel zum SQL-Enum). */
export const HAZARD_TYPES = ['rollsplitt', 'sperrung', 'baustelle', 'oelspur'] as const;
export type HazardType = (typeof HAZARD_TYPES)[number];

export class CreateHazardDto {
  @IsEnum(HAZARD_TYPES, { message: 'reportType muss rollsplitt, sperrung, baustelle oder oelspur sein' })
  reportType: HazardType;

  @Type(() => Number)
  @IsLatitude()
  lat: number;

  @Type(() => Number)
  @IsLongitude()
  lng: number;

  /** Optionaler Freitext (wird serverseitig auf 500 Zeichen gekappt). */
  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string;
}

export class NearbyHazardsQueryDto {
  @Type(() => Number)
  @IsLatitude()
  lat: number;

  @Type(() => Number)
  @IsLongitude()
  lon: number;

  /** Radius in km (SQL klemmt auf [0.1, 100] km). */
  @IsOptional()
  @Type(() => Number)
  @Min(0.1)
  @Max(100)
  radiusKm?: number;
}

export class UpvoteHazardDto {
  @IsUUID()
  id: string;
}

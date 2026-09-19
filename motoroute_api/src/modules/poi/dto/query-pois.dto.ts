import { Transform } from 'class-transformer';
import { ArrayMinSize, IsArray, IsEnum, IsNumber } from 'class-validator';

export enum PoiCategory {
  FUEL = 'FUEL',
  MOTO_HOTEL = 'MOTO_HOTEL',
  BIKER_MEETUP = 'BIKER_MEETUP',
  CAMPSITE = 'CAMPSITE',
  ICE_CREAM = 'ICE_CREAM',
  SPEED_CAMERA = 'SPEED_CAMERA',
}

/**
 * bbox as "minLng,minLat,maxLng,maxLat" query string, matching the
 * GET /v1/pois?bbox=...&categories=... shape from Phase 1/2 Teil F.
 */
export class QueryPoisDto {
  @Transform(({ value }) => String(value).split(',').map(Number))
  @IsArray()
  @ArrayMinSize(4)
  @IsNumber({}, { each: true })
  bbox: number[];

  @Transform(({ value }) => String(value).split(','))
  @IsArray()
  @IsEnum(PoiCategory, { each: true })
  categories: PoiCategory[];
}

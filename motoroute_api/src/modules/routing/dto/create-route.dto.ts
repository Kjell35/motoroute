import { Type } from 'class-transformer';
import {
  ArrayMinSize,
  IsArray,
  IsEnum,
  IsLatitude,
  IsLongitude,
  IsOptional,
  IsString,
  ValidateNested,
} from 'class-validator';

export enum RouteStyle {
  FAST = 'FAST',
  CURVY = 'CURVY',
  EXTRA_CURVY = 'EXTRA_CURVY',
  FAST_AND_CURVY = 'FAST_AND_CURVY',
  UNPAVED = 'UNPAVED',
}

export enum VehicleType {
  MOTORCYCLE = 'MOTORCYCLE',
  CAR = 'CAR',
  BICYCLE = 'BICYCLE',
}

export enum AvoidOption {
  HIGHWAY = 'HIGHWAY',
  FERRY = 'FERRY',
  TOLL = 'TOLL',
}

export class WaypointDto {
  @IsLatitude()
  lat: number;

  @IsLongitude()
  lng: number;

  @IsOptional()
  @IsString()
  label?: string;
}

export class RoutePreferenceDto {
  @IsEnum(RouteStyle)
  style: RouteStyle;

  @IsEnum(VehicleType)
  vehicleType: VehicleType;

  @IsOptional()
  @IsArray()
  @IsEnum(AvoidOption, { each: true })
  avoid?: AvoidOption[];
}

export class CreateRouteDto {
  @IsArray()
  @ArrayMinSize(2, { message: 'At least a start and a destination waypoint are required' })
  @ValidateNested({ each: true })
  @Type(() => WaypointDto)
  waypoints: WaypointDto[];

  @ValidateNested()
  @Type(() => RoutePreferenceDto)
  preference: RoutePreferenceDto;
}

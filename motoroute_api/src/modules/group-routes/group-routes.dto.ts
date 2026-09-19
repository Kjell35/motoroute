import { Type } from 'class-transformer';
import {
  IsArray,
  IsBoolean,
  IsEnum,
  IsIn,
  IsLatitude,
  IsLongitude,
  IsNumber,
  IsOptional,
  IsString,
  MaxLength,
  ValidateNested,
} from 'class-validator';

export enum RouteStatus {
  PLANNING = 'planning',
  FINAL = 'final',
  RIDING = 'riding',
  COMPLETED = 'completed',
}

export enum EditingPermission {
  ALL_MEMBERS = 'all_members',
  OWNER_ONLY = 'owner_only',
}

export class CreateGroupRouteDto {
  @IsString()
  groupId: string;

  @IsString()
  @MaxLength(80)
  name: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  description?: string;

  @IsOptional()
  @IsString()
  startName?: string;

  @IsLatitude()
  startLat: number;

  @IsLongitude()
  startLng: number;

  @IsOptional()
  @IsString()
  destName?: string;

  @IsLatitude()
  destLat: number;

  @IsLongitude()
  destLng: number;

  @IsOptional()
  @IsIn(['MOTORCYCLE', 'CAR', 'BICYCLE'])
  vehicleType?: string;

  @IsOptional()
  @IsIn(['FAST', 'CURVY', 'EXTRA_CURVY', 'FAST_AND_CURVY', 'UNPAVED'])
  routingStyle?: string;

  @IsOptional()
  @IsBoolean()
  avoidHighways?: boolean;

  @IsOptional()
  @IsBoolean()
  avoidFerries?: boolean;

  @IsOptional()
  @IsBoolean()
  avoidTolls?: boolean;

  @IsOptional()
  @IsEnum(EditingPermission)
  permission?: EditingPermission;
}

export class UpdateGroupRouteDto {
  @IsOptional()
  @IsString()
  @MaxLength(80)
  name?: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  description?: string;
}

export class AddStopDto {
  @IsLatitude()
  lat: number;

  @IsLongitude()
  lng: number;

  @IsString()
  @MaxLength(120)
  name: string;

  @IsOptional()
  @IsIn(['fuel', 'moto_hotel', 'biker_meetup', 'campsite', 'ice_cream', 'viewpoint', 'other'])
  category?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string;

  @IsOptional()
  @IsString()
  @MaxLength(300)
  address?: string;
}

export class ReorderStopsDto {
  @IsArray()
  @IsString({ each: true })
  stopIds: string[];
}

export class UpdateStopDto {
  @IsOptional()
  @IsString()
  @MaxLength(120)
  name?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string;

  @IsOptional()
  @IsIn(['fuel', 'moto_hotel', 'biker_meetup', 'campsite', 'ice_cream', 'viewpoint', 'other'])
  category?: string;
}

export class SetStatusDto {
  @IsEnum(RouteStatus)
  status: RouteStatus;
}

export class SetPermissionDto {
  @IsEnum(EditingPermission)
  permission: EditingPermission;
}

export class AddCommentDto {
  @IsString()
  @MaxLength(500)
  content: string;
}

export class DuplicateRouteDto {
  @IsOptional()
  @IsString()
  @MaxLength(80)
  newName?: string;
}

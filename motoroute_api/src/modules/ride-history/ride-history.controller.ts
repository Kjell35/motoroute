import {
  Body,
  Controller,
  Get,
  HttpCode,
  Param,
  Post,
  Put,
  Req,
  UseGuards,
} from '@nestjs/common';
import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsIn,
  IsNumber,
  IsOptional,
  IsString,
  Length,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { AuthProvider, AuthenticatedRequest } from '../../guards';
import { RideHistoryService, RideSyncDto, PrivacyUpdateDto } from './ride-history.service';

class TrackPointDto {
  @IsNumber() lat!: number;
  @IsNumber() lng!: number;
  @IsOptional() @IsNumber() elevationMeters?: number | null;
  @IsNumber() secondsSinceStart!: number;
}

class PlaceVisitDto {
  @IsString() @Length(1, 120) externalId!: string;
  @IsIn(['fuel', 'restaurant', 'hotel', 'camping', 'bikertreff', 'other'])
  category!: 'fuel' | 'restaurant' | 'hotel' | 'camping' | 'bikertreff' | 'other';
  @IsString() @Length(1, 120) label!: string;
  @IsNumber() @Min(-90) lat!: number;
  @IsNumber() @Min(-180) lng!: number;
}

export class SyncRideDto {
  @IsString() @Length(1, 80) externalId!: string;
  @IsString() @Length(1, 120) title!: string;
  @IsString() @Length(10, 40) startedAt!: string;
  @IsString() @Length(10, 40) endedAt!: string;
  @IsNumber() @Min(0) distanceMeters!: number;
  @IsNumber() @Min(0) durationSeconds!: number;
  @IsNumber() @Min(0) elevationGainMeters!: number;
  @IsArray() @ArrayMaxSize(5000) @ValidateNested({ each: true })
  @Type(() => TrackPointDto)
  track!: TrackPointDto[];
  @IsArray() @ArrayMaxSize(100) @ValidateNested({ each: true })
  @Type(() => PlaceVisitDto)
  pois!: PlaceVisitDto[];
  @IsOptional() @IsString() @MaxLength(120) startLabel?: string | null;
  @IsOptional() @IsString() @MaxLength(120) endLabel?: string | null;
  @IsOptional() @IsNumber() startLat?: number | null;
  @IsOptional() @IsNumber() startLng?: number | null;
  @IsOptional() @IsNumber() endLat?: number | null;
  @IsOptional() @IsNumber() endLng?: number | null;
  @IsOptional() @IsString() @MaxLength(2000) description?: string | null;
  @IsOptional() @IsArray() @ArrayMaxSize(8) @IsString({ each: true }) photos?: string[];
}

class PerRideDto {
  @IsString() @Length(1, 80) externalId!: string;
  @IsBoolean() isPublic!: boolean;
  @IsOptional() @IsBoolean() shareTrack?: boolean;
}

class PerPlaceDto {
  @IsString() @Length(1, 120) externalId!: string;
  @IsBoolean() isPublic!: boolean;
}

export class PrivacySettingsDto {
  @IsOptional() @IsBoolean() rideHistoryEnabled?: boolean;
  @IsOptional() @IsIn(['private', 'public']) authPrivacy?: 'private' | 'public';
  @IsOptional() @IsBoolean() shareRides?: boolean;
  @IsOptional() @IsBoolean() sharePlaces?: boolean;
  @IsOptional() @IsBoolean() hideStartEnd?: boolean;
  @IsOptional() @IsArray() @ArrayMaxSize(200) @ValidateNested({ each: true })
  @Type(() => PerRideDto)
  perRide?: PerRideDto[];
  @IsOptional() @IsArray() @ArrayMaxSize(500) @ValidateNested({ each: true })
  @Type(() => PerPlaceDto)
  perPlace?: PerPlaceDto[];
}

/**
 * Fahrhistorie im Benutzerprofil. Alle Endpunkte erfordern einen JWT;
 * die öffentliche Sicht filtert zusätzlich über die Privacy-Flags des
 * Besitzers (Default: alles privat).
 */
@Controller('v1/ride-history')
@UseGuards(AuthProvider)
export class RideHistoryController {
  constructor(private readonly service: RideHistoryService) {}

  /** Eine abgeschlossene Tour synchronisieren (App -> Backend). */
  @Post('rides')
  @HttpCode(201)
  async syncRide(@Req() req: AuthenticatedRequest, @Body() dto: SyncRideDto) {
    return this.service.syncRide(req.user!, dto as unknown as RideSyncDto);
  }

  /** Eigene Historie + aktuelle Einstellungen (Profil-Bearbeitung). */
  @Get('me')
  async myHistory(@Req() req: AuthenticatedRequest) {
    return this.service.getMyHistory(req.user!);
  }

  /** Privatsphäre-Einstellungen ändern (Global + pro Tour/Ort). */
  @Put('privacy')
  async updatePrivacy(@Req() req: AuthenticatedRequest, @Body() dto: PrivacySettingsDto) {
    return this.service.updatePrivacy(req.user!, dto as unknown as PrivacyUpdateDto);
  }

  /** Öffentliches Profil eines anderen Benutzers ansehen. */
  @Get('public/:userId')
  async publicProfile(@Req() req: AuthenticatedRequest, @Param('userId') userId: string) {
    return this.service.getPublicProfile(req.user!, userId);
  }
}

import { Body, Controller, Delete, Get, HttpCode, Put, Post, Req, UseGuards } from '@nestjs/common';
import { IsOptional, IsString, Length, MaxLength, MinLength } from 'class-validator';
import { AuthProvider, AuthenticatedRequest } from '../../guards';
import { UserService } from './user.service';

/**
 * DTOs für das User-Modul. Absichtlich schlicht gehalten - MVP-scope
 * ist "Profil abrufen/aktualisieren", nicht "vollständige User-Verwaltung".
 */
export class UpdateProfileDto {
  @IsOptional()
  @IsString()
  @Length(1, 80)
  displayName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  avatarUrl?: string;
}

/**
 * Passwort-Änderung: aktuelles Passwort wird serverseitig per GoTrue-
 * Login verifiziert, bevor die Admin-API es ändert.
 */
export class UpdatePasswordDto {
  @IsString()
  @MinLength(6)
  @MaxLength(128)
  currentPassword: string;

  @IsString()
  @MinLength(8)
  @MaxLength(128)
  newPassword: string;
}

/**
 * User-Controller.
 *
 * Endpunkte:
 * - GET    /v1/users/me           → eigenes Profil + Entitlements (Auth)
 * - PUT    /v1/users/me           → Profil aktualisieren (Auth)
 * - POST   /v1/users/me/password  → Passwort ändern (Auth)
 * - DELETE /v1/users/me           → Konto endgültig löschen (Auth)
 *
 * (Der frühere unauthentifizierte Webhook-Upsert ist entfernt: Das
 * Provisionieren passiert im AuthService mit Service-Key - ein offen
 * erreichbarer Upsert wäre ein Datenmanipulationsleck.)
 *
 * getMe/updateMe tragen den strikten AuthProvider - das ist der erste
 * Endpunkt-Verbund, an dem der Supabase-JWT-Weg Ende-zu-Ende durch ist.
 */
@Controller('v1/users')
export class UserController {
  constructor(private readonly userService: UserService) {}

  @Get('me')
  @UseGuards(AuthProvider)
  async getMe(@Req() req: AuthenticatedRequest): Promise<unknown> {
    return this.userService.getMe(req.user!);
  }

  @Put('me')
  @UseGuards(AuthProvider)
  async updateMe(@Req() req: AuthenticatedRequest, @Body() dto: UpdateProfileDto): Promise<unknown> {
    return this.userService.updateMe(req.user!, dto);
  }

  @Post('me/password')
  @HttpCode(200)
  @UseGuards(AuthProvider)
  async changePassword(
    @Req() req: AuthenticatedRequest,
    @Body() dto: UpdatePasswordDto,
  ): Promise<{ changed: boolean }> {
    return this.userService.updatePassword(req.user!, dto);
  }

  @Delete('me')
  @UseGuards(AuthProvider)
  async deleteMe(@Req() req: AuthenticatedRequest): Promise<{ deleted: boolean }> {
    return this.userService.deleteMe(req.user!);
  }
}

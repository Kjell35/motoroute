import { Body, Controller, Delete, Get, HttpCode, Put, Post, Req, UseGuards } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHmac } from 'crypto';
import { HttpException, HttpStatus } from '@nestjs/common';
import { IsIn, IsOptional, IsString, Length, Matches, MaxLength, MinLength } from 'class-validator';
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

  @IsOptional()
  @IsString()
  @Length(3, 40)
  @Matches(/^[a-zA-Z0-9_-]+$/, {
    message: 'username darf nur Buchstaben, Zahlen, _ und - enthalten',
  })
  username?: string;

  @IsOptional()
  @IsString()
  @Length(0, 80)
  firstName?: string;

  @IsOptional()
  @IsIn(['username', 'first_name', 'custom'])
  chatNameMode?: 'username' | 'first_name' | 'custom';

  @IsOptional()
  @IsString()
  @Length(0, 80)
  chatDisplayName?: string;
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
  constructor(
    private readonly userService: UserService,
    private readonly config: ConfigService,
  ) {}

  @Get('me')
  @UseGuards(AuthProvider)
  async getMe(@Req() req: AuthenticatedRequest): Promise<unknown> {
    return this.userService.getMe(req.user!);
  }

  /**
   * Garage-Auto-Provisioning (Schritt 1): kurzlebiges HMAC-Ticket fuer
   * POST /api/auth/provision der Garage-API erzeugen. Der Nutzer wird
   * dort silent registriert/eingeloggt - kein zweites Login-Formular.
   */
  @Post('me/garage-ticket')
  @HttpCode(201)
  @UseGuards(AuthProvider)
  garageTicket(@Req() req: AuthenticatedRequest): unknown {
    const secret = this.config.get<string>('GARAGE_TICKET_SECRET');
    if (!secret || secret.length < 32) {
      throw new HttpException(
        { error: 'PROVISION_DISABLED', message: 'Garage-Anbindung nicht konfiguriert' },
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
    const payload = Buffer.from(
      JSON.stringify({
        v: 1,
        sub: req.user!.id,
        email: req.user!.email ?? '',
        displayName: '', // Garage faellt auf Email-Localpart zurueck
        admin: req.user!.role === 'admin',
        exp: Math.floor(Date.now() / 1000) + 120, // 2 Minuten gueltig
      }),
    ).toString('base64url');
    const sig = createHmac('sha256', secret).update(payload).digest('base64url');
    return { ticket: `${payload}.${sig}`, garageApiUrl: this.config.get<string>('GARAGE_API_URL') ?? null };
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

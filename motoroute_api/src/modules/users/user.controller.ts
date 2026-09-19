import { Body, Controller, Get, Put, Post, Req, UseGuards } from '@nestjs/common';
import { IsEmail, IsOptional, IsString, Length, MaxLength } from 'class-validator';
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
 * Webhook-Body: Supabase ruft diesen Endpunkt (mit eigenem Secret,
 * siehe .env.example-Planung) auf, wenn sich ein Nutzer das erste Mal
 * registriert. Die User-ID kommt aus der Supabase-Payload.
 */
export class UserWebhookDto {
  @IsString()
  id: string;

  @IsOptional()
  @IsEmail()
  email?: string;

  @IsOptional()
  @IsString()
  @Length(1, 80)
  displayName?: string;
}

/**
 * User-Controller.
 *
 * Endpunkte:
 * - GET  /v1/users/me   → eigenes Profil (Auth erforderlich)
 * - PUT  /v1/users/me   → Profil aktualisieren (Auth erforderlich)
 * - POST /v1/users      → (intern) Webhook-Upsert nach Erst-Login
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

  @Post()
  async upsert(@Body() dto: UserWebhookDto): Promise<unknown> {
    return this.userService.upsert(dto);
  }
}

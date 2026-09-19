import { Body, Controller, Get, HttpCode, Post, Req, ServiceUnavailableException, UseGuards } from '@nestjs/common';
import { AuthProvider, AuthenticatedRequest } from '../../guards';
import { AuthSession, LoginDto, RefreshDto, RegisterDto } from './auth.dto';
import { AuthService } from './auth.service';

/**
 * Auth-Endpunkte (alle ohne Options-Provider: Login/Registrierung sind
 * per Definition anonym erreichbar, /logout + /me verifizieren aktiv).
 */
@Controller('v1/auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  private ensureConfigured(): void {
    if (!this.authService.isConfigured) {
      throw new ServiceUnavailableException(
        'Auth ist auf diesem Server nicht konfiguriert (SUPABASE_ANON_KEY fehlt)',
      );
    }
  }

  @Post('login')
  @HttpCode(200)
  async login(@Body() dto: LoginDto): Promise<AuthSession> {
    this.ensureConfigured();
    return this.authService.login(dto);
  }

  @Post('register')
  @HttpCode(201)
  async register(@Body() dto: RegisterDto): Promise<AuthSession> {
    this.ensureConfigured();
    return this.authService.register(dto);
  }

  @Post('refresh')
  @HttpCode(200)
  async refresh(@Body() dto: RefreshDto): Promise<AuthSession> {
    this.ensureConfigured();
    return this.authService.refresh(dto.refreshToken);
  }

  @Post('logout')
  @HttpCode(204)
  @UseGuards(AuthProvider)
  async logout(@Req() _req: AuthenticatedRequest): Promise<void> {
    await this.authService.logout();
  }

  @Get('me')
  @UseGuards(AuthProvider)
  async me(@Req() req: AuthenticatedRequest): Promise<AuthSession['user']> {
    const token = req.user?.token;
    if (!token) {
      throw new ServiceUnavailableException('Token-Verifikation nicht verfügbar');
    }
    return this.authService.profile(token);
  }
}

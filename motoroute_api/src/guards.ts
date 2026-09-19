import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { Request } from 'express';

/**
 * Shape attached to `req.user` after successful token validation.
 * Deliberately minimal - only what downstream handlers need (user id
 * for scoping profile/route queries, email for convenience).
 */
export interface AuthenticatedUser {
  id: string;
  email?: string;
  /**
   * Raw bearer token - benötigt von Services, die Supabase mit den
   * Rechten DES NUTZERS aufrufen müssen (Chat: RLS bleibt Durchsetzungs-
   * schicht). Niemals loggen oder an Dritte weitergeben.
   */
  token?: string;
}

export interface AuthenticatedRequest extends Request {
  user?: AuthenticatedUser;
}

/**
 * Validates a Supabase JWT and resolves the underlying user.
 *
 * Extracted from the guards themselves so it can be mocked in guard
 * unit tests without stubbing the whole Supabase client (see
 * guards.spec.ts). Uses supabase.auth.getUser(token): the token is
 * verified by the Supabase Auth server (signature + expiry + issuer),
 * which stays correct even if Supabase rotates its JWT secret.
 */
@Injectable()
export class SupabaseAuthService {
  private readonly adminClient: SupabaseClient | null;

  constructor(config: ConfigService) {
    const url = config.get<string>('SUPABASE_URL');
    const key = config.get<string>('SUPABASE_SERVICE_ROLE_KEY');
    const configured =
      url && key && !url.includes('your-project.supabase.co') && key.length >= 20;
    // Degradierung statt Boot-Abbruch: ohne echtes Supabase-Projekt
    // bleibt der Dienst startbar (anonymes Routing funktioniert als
    // Produkt-Requirement sowieso ohne Account). validateToken liefert
    // dann null -> alle Requests gelten als anonym.
    this.adminClient = configured
      ? createClient(url!, key!, {
          auth: { autoRefreshToken: false, persistSession: false },
        })
      : null;
  }

  async validateToken(token: string): Promise<AuthenticatedUser | null> {
    if (this.adminClient == null) return null;
    const { data, error } = await this.adminClient.auth.getUser(token);
    if (error || !data.user) return null;
    return { id: data.user.id, email: data.user.email ?? undefined };
  }
}

/**
 * Reads the Authorization header, validates the JWT when present and
 * attaches `req.user`. A missing or invalid token is accepted as
 * "anonymous" - anonymous usage is an explicit product requirement
 * (Phase 1/2 Teil F), so this guard NEVER throws.
 */
@Injectable()
export class OptionalAuthProvider implements CanActivate {
  constructor(private readonly auth: SupabaseAuthService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const token = extractBearerToken(request);

    if (token) {
      // Invalid token on an anonymous-allowed endpoint: treat as
      // anonymous rather than rejecting - the caller may be replaying
      // an expired token after the session already lapsed, and the
      // MVP flow works without an account.
      const user = await this.auth.validateToken(token);
      if (user) request.user = { ...user, token };
    }
    return true;
  }
}

/**
 * Strict variant for endpoints that REQUIRE authentication (saved
 * routes, profile mutation, later account deletion). Returns 401 with
 * a machine-readable code instead of a raw Error (which Nest would
 * turn into an unhelpful 500).
 */
@Injectable()
export class AuthProvider implements CanActivate {
  constructor(private readonly auth: SupabaseAuthService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const token = extractBearerToken(request);

    if (!token) {
      throw new UnauthorizedException({ error: 'AUTH_REQUIRED', message: 'Bearer token missing' });
    }

    const user = await this.auth.validateToken(token);
    if (!user) {
      throw new UnauthorizedException({ error: 'AUTH_REQUIRED', message: 'Invalid or expired token' });
    }

    request.user = { ...user, token };
    return true;
  }
}

function extractBearerToken(request: Request): string | null {
  const header = request.headers.authorization;
  if (!header?.startsWith('Bearer ')) return null;
  const token = header.slice('Bearer '.length).trim();
  return token.length > 0 ? token : null;
}

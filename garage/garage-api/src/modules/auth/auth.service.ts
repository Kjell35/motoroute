import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import jwt from 'jsonwebtoken';
import { prisma } from '../../common/prisma';
import { env } from '../../config/env';

export interface AuthUser {
  id: string;
  email: string;
  displayName: string;
  role: 'user' | 'admin';
}

export class AuthError extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
  ) {
    super(message);
  }
}

function toAuthUser(u: { id: string; email: string; displayName: string; role: string }): AuthUser {
  return {
    id: u.id,
    email: u.email,
    displayName: u.displayName,
    role: u.role === 'admin' ? 'admin' : 'user',
  };
}

const { randomBytes, createHmac, timingSafeEqual } = crypto;

/**
 * Ticket-Format (Base64url-JSON): { v:1, sub, email, displayName, admin, exp, sig }
 * sig = HMAC-SHA256(GARAGE_TICKET_SECRET, base64url(JSON ohne sig)).
 * Konstante Zeit beim Vergleich (timingSafeEqual).
 */
interface ProvisionTicket {
  sub: string;
  email: string;
  displayName: string;
  admin: boolean;
  exp: number; // Unix-Sekunden
}

export function signTicket(t: ProvisionTicket, secret: string): string {
  const { sig: _omit, ...rest } = { ...t, sig: '' } as ProvisionTicket & { sig: string };
  void _omit;
  const payload = Buffer.from(JSON.stringify(rest)).toString('base64url');
  const sig = createHmac('sha256', secret).update(payload).digest('base64url');
  return `${payload}.${sig}`;
}

export function parseTicket(ticket: string, secret: string): ProvisionTicket | null {
  const dot = ticket.lastIndexOf('.');
  if (dot <= 0) return null;
  const payload = ticket.slice(0, dot);
  const sig = ticket.slice(dot + 1);
  const expected = createHmac('sha256', secret).update(payload).digest('base64url');
  const a = Buffer.from(sig);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !timingSafeEqual(a, b)) return null;
  try {
    const t = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as ProvisionTicket;
    if (!t.sub || !t.email || typeof t.exp !== 'number') return null;
    if (t.exp * 1000 < Date.now()) return null; // abgelaufen
    return t;
  } catch {
    return null;
  }
}

export class AuthService {
  async register(email: string, password: string, displayName: string): Promise<{ user: AuthUser; accessToken: string }> {
    const normalized = email.trim().toLowerCase();
    const existing = await prisma.user.findUnique({ where: { email: normalized } });
    if (existing) {
      throw new AuthError(409, 'EMAIL_TAKEN', 'Diese E-Mail ist bereits registriert');
    }
    if (password.length < 8) {
      throw new AuthError(400, 'WEAK_PASSWORD', 'Passwort muss mindestens 8 Zeichen haben');
    }
    const passwordHash = await bcrypt.hash(password, 12);
    const user = await prisma.user.create({
      data: { email: normalized, passwordHash, displayName: displayName.trim() || normalized.split('@')[0] },
    });
    return { user: toAuthUser(user), accessToken: this.signToken(user.id) };
  }

  async login(email: string, password: string): Promise<{ user: AuthUser; accessToken: string }> {
    const normalized = email.trim().toLowerCase();
    const user = await prisma.user.findUnique({ where: { email: normalized } });
    if (!user) {
      throw new AuthError(401, 'INVALID_CREDENTIALS', 'E-Mail oder Passwort falsch');
    }
    const ok = await bcrypt.compare(password, user.passwordHash);
    if (!ok) {
      throw new AuthError(401, 'INVALID_CREDENTIALS', 'E-Mail oder Passwort falsch');
    }
    return { user: toAuthUser(user), accessToken: this.signToken(user.id) };
  }

  async userFromToken(token: string): Promise<AuthUser | null> {
    try {
      const payload = jwt.verify(token, env.JWT_SECRET) as { sub?: string };
      if (!payload.sub) return null;
      const user = await prisma.user.findUnique({ where: { id: payload.sub } });
      return user ? toAuthUser(user) : null;
    } catch {
      return null;
    }
  }

  private signToken(userId: string): string {
    return jwt.sign({ sub: userId }, env.JWT_SECRET, {
      expiresIn: env.JWT_EXPIRES_IN_SECONDS,
    });
  }

  /**
   * Auto-Provisioning (App-Anforderung: Garage OHNE eigene Anmeldung):
   * Das MotoRoute-Backend signiert ein kurzlebiges Ticket (HMAC), die
   * App reicht es hier ein. Wir registrieren den Nutzer silent (oder
   * loggen ihn ein, falls die E-Mail schon existiert) - der Nutzer
   * sieht nie ein Garage-Login-Formular.
   *
   * Ticket-Payload: { v, sub, email, displayName, admin, exp, sig }
   * sig = HMAC-SHA256 über die Serialisierung des Rests.
   */
  async provisionFromTicket(
    ticket: string,
  ): Promise<{ user: AuthUser; accessToken: string }> {
    if (!env.GARAGE_TICKET_SECRET) {
      throw new AuthError(503, 'PROVISION_DISABLED', 'Auto-Provisioning nicht konfiguriert');
    }
    const parsed = parseTicket(ticket, env.GARAGE_TICKET_SECRET);
    if (!parsed) {
      throw new AuthError(401, 'INVALID_TICKET', 'Ticket ungültig oder abgelaufen');
    }
    const { email, displayName, admin } = parsed;

    // Admin-Mapping: MotoRoute-Admins werden Garage-Admins.
    const adminEmails = (env.GARAGE_ADMIN_EMAILS ?? '')
      .split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
    const isAdmin = admin === true || adminEmails.includes(email.toLowerCase());

    const normalized = email.trim().toLowerCase();
    const existing = await prisma.user.findUnique({ where: { email: normalized } });
    if (existing) {
      // Rolle ggf. hochstufen (Admin-Mapping), dann Login.
      if (isAdmin && existing.role !== 'admin') {
        await prisma.user.update({ where: { id: existing.id }, data: { role: 'admin' } });
      }
      const fresh = isAdmin
        ? await prisma.user.findUniqueOrThrow({ where: { id: existing.id } })
        : existing;
      return { user: toAuthUser(fresh), accessToken: this.signToken(existing.id) };
    }

    // Silent-Register: deterministisches Zufalls-Passwort (Nutzer kennt
    // es nicht und braucht es nicht - Login läuft immer über Tickets;
    // wer ein echtes Passwort will, nutzt den klassischen Register-Flow).
    const passwordHash = await bcrypt.hash(randomBytes(24).toString('hex'), 12);
    const user = await prisma.user.create({
      data: {
        email: normalized,
        passwordHash,
        displayName: displayName.trim() || normalized.split('@')[0],
        role: isAdmin ? 'admin' : 'user',
      },
    });
    return { user: toAuthUser(user), accessToken: this.signToken(user.id) };
  }
}

export const authService = new AuthService();

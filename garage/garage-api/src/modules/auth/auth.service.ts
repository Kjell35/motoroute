import bcrypt from 'bcryptjs';
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
}

export const authService = new AuthService();

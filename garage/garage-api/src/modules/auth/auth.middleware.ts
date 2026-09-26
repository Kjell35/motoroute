import type { NextFunction, Request, Response } from 'express';
import { authService, AuthError, type AuthUser } from './auth.service';

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      user?: AuthUser;
    }
  }
}

export async function requireAuth(req: Request, res: Response, next: NextFunction): Promise<void> {
  const header = req.headers.authorization ?? '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) {
    res.status(401).json({ error: 'UNAUTHENTICATED', message: 'Authorization: Bearer <token> fehlt' });
    return;
  }
  const user = await authService.userFromToken(token);
  if (!user) {
    res.status(401).json({ error: 'UNAUTHENTICATED', message: 'Token ungültig oder abgelaufen' });
    return;
  }
  req.user = user;
  next();
}

export function requireAdmin(req: Request, res: Response, next: NextFunction): void {
  if (req.user?.role !== 'admin') {
    res.status(403).json({ error: 'FORBIDDEN', message: 'Admin-Berechtigung erforderlich' });
    return;
  }
  next();
}

export { AuthError };

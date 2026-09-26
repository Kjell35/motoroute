import { Router } from 'express';
import { z } from 'zod';
import rateLimit from 'express-rate-limit';
import { authService } from './auth.service';
import { requireAuth } from './auth.middleware';

export const authRouter = Router();

const authLimiter = rateLimit({ windowMs: 15 * 60_000, max: 30 });

const registerSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8).max(128),
  displayName: z.string().min(1).max(80).optional(),
});

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1).max(128),
});

/** Validierungsfehler von zod in ein einheitliches 400-Format gießen. */
export function parseBody<T>(schema: z.ZodType<T>, body: unknown): T {
  const result = schema.safeParse(body);
  if (!result.success) {
    const details = result.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('; ');
    const err = new Error(details) as Error & { status?: number; code?: string };
    err.status = 400;
    err.code = 'VALIDATION_ERROR';
    throw err;
  }
  return result.data;
}

authRouter.post('/register', authLimiter, async (req, res, next) => {
  try {
    const { email, password, displayName } = parseBody(registerSchema, req.body);
    const result = await authService.register(email, password, displayName ?? '');
    res.status(201).json(result);
  } catch (e) {
    next(e);
  }
});

authRouter.post('/login', authLimiter, async (req, res, next) => {
  try {
    const { email, password } = parseBody(loginSchema, req.body);
    const result = await authService.login(email, password);
    res.json(result);
  } catch (e) {
    next(e);
  }
});

authRouter.get('/me', requireAuth, (req, res) => {
  res.json({ user: req.user });
});

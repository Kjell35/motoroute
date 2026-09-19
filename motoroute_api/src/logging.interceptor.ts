import { ExecutionContext, Injectable, Logger, NestInterceptor, CallHandler } from '@nestjs/common';
import { Observable } from 'rxjs';
import { tap } from 'rxjs/operators';

/**
 * LoggingInterceptor - strukturiertes Request-Logging für Debugging und
 * spätere Monitoring-Integration (z. B. mit Datadog/Sentry).
 *
 * Absichtlich leicht gehalten: der MVP braucht kein komplettes APM,
 * aber ohne dieses Interceptor wären Failed-Requests im Log nur an
 * der Exception-Stacktrace erkennbar - das ist bei einem Routing-Service
 * (GraphHopper-Timeouts, 503-Responses) zu ungenau.
 */
@Injectable()
export class LoggingInterceptor implements NestInterceptor {
  private readonly logger = new Logger(LoggingInterceptor.name);

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const http = context.switchToHttp();
    const request = http.getRequest<Request>();
    const { method, url } = request;
    const startedAt = Date.now();

    return next.handle().pipe(
      tap({
        next: () => {
          const elapsed = Date.now() - startedAt;
          this.logger.log(`${method} ${url} → 2xx in ${elapsed}ms`);
        },
        error: (err) => {
          const elapsed = Date.now() - startedAt;
          this.logger.error(
            `${method} ${url} → ${err?.status ?? 500} in ${elapsed}ms: ${err?.message ?? err}`,
          );
        },
      }),
    );
  }
}
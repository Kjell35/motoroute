import { plainToInstance } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, Max, Min, validateSync } from 'class-validator';

/**
 * Validates process.env at startup. Fails fast with a clear error
 * instead of the app booting into a half-configured state that only
 * surfaces as a confusing runtime error later (e.g. a routing request
 * failing because GRAPHHOPPER_URL was silently undefined).
 *
 * TRAFFIC_API_KEY is deliberately optional - see .env.example: the
 * traffic module is not part of the MVP and must degrade gracefully
 * when unset, not block startup.
 *
 * GRAPHHOPPER_URL ist ebenfalls optional: Ohne eigenen GraphHopper
 * routed das Backend über den OSRM-Fallback (ROUTING_FALLBACK_URL,
 * Default: öffentlicher OSRM-Demo-Server) - so läuft ein Cloud-
 * Deployment ohne lokale Java-Instanz. SUPABASE_JWT_SECRET wird von
 * keinem Modul mehr gelesen (JWT-Verifikation läuft serverseitig über
 * auth.getUser()) und ist deshalb optional.
 */
class EnvironmentVariables {
  @IsInt()
  @Min(1)
  @Max(65535)
  PORT: number = 3000;

  @IsIn(['development', 'production', 'test'])
  NODE_ENV: string = 'development';

  @IsOptional()
  @IsString()
  GRAPHHOPPER_URL?: string;

  @IsOptional()
  @IsString()
  ROUTING_FALLBACK_URL?: string;

  @IsString()
  SUPABASE_URL: string;

  @IsString()
  SUPABASE_SERVICE_ROLE_KEY: string;

  @IsOptional()
  @IsString()
  SUPABASE_JWT_SECRET?: string;

  @IsOptional()
  @IsString()
  GEOCODING_URL?: string;

  @IsOptional()
  @IsString()
  TRAFFIC_PROVIDER?: string;

  @IsOptional()
  @IsString()
  TRAFFIC_API_KEY?: string;

  @IsOptional()
  @IsString()
  PUBLIC_URL?: string;
}

export function validateEnv(config: Record<string, unknown>) {
  const validated = plainToInstance(EnvironmentVariables, config, {
    enableImplicitConversion: true,
  });
  const errors = validateSync(validated, { skipMissingProperties: false });

  if (errors.length > 0) {
    throw new Error(
      `Invalid environment configuration:\n${errors
        .map((e) => `  - ${e.property}: ${Object.values(e.constraints ?? {}).join(', ')}`)
        .join('\n')}`,
    );
  }

  return validated;
}
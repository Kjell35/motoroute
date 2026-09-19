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
 */
class EnvironmentVariables {
  @IsInt()
  @Min(1)
  @Max(65535)
  PORT: number = 3000;

  @IsIn(['development', 'production', 'test'])
  NODE_ENV: string = 'development';

  @IsString()
  GRAPHHOPPER_URL: string;

  @IsString()
  SUPABASE_URL: string;

  @IsString()
  SUPABASE_SERVICE_ROLE_KEY: string;

  @IsString()
  SUPABASE_JWT_SECRET: string;

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
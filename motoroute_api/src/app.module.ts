import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ThrottlerModule } from '@nestjs/throttler';
import { validateEnv } from './config/env.validation';
import { LoggingInterceptor } from './logging.interceptor';
import { SupabaseModule } from './supabase/supabase.module';
import { RoutingModule } from './modules/routing/routing.module';
import { PoiModule } from './modules/poi/poi.module';
import { SearchModule } from './modules/search/search.module';
import { TrafficModule } from './modules/traffic/traffic.module';
import { RoundTripModule } from './modules/roundtrip/roundtrip.module';
import { AuthModule } from './modules/auth/auth.module';
import { UserModule } from './modules/users/user.module';
import { ChatModule } from './modules/chat/chat.module';
import { GroupRoutesModule } from './modules/group-routes/group-routes.module';
import { GroupRidesModule } from './modules/group-rides/group-rides.module';
import { BikerPoisModule } from './modules/biker-pois/biker-pois.module';
import { HazardsModule } from './modules/hazards/hazards.module';
import { WeatherModule } from './modules/weather/weather.module';
import { RideHistoryModule } from './modules/ride-history/ride-history.module';
import { MarketplaceModule } from './modules/marketplace/marketplace.module';
import { HealthController } from './modules/health/health.controller';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      validate: validateEnv,
      // Auf manchen Dev-Maschinen liegt z. B. PORT=0 in der Shell.
      // @nestjs/config merged process.env ÜBER die .env-Datei, d. h.
      // der Shell-Wert würde gewinnen und die .env wäre tot. Für
      // diesen Dienst ist die .env die Source of Truth (main.ts lädt
      // sie deshalb VORHER mit dotenv{override:true} direkt in
      // process.env). In Produktion: echte Env-Variablen ohne .env-
      // Datei setzen - die greifen dann uneingeschränkt.
      envFilePath: '.env',
      // ignoreEnvVars war true - das EXKLUDIERTE process.env aus der
      // Validierung, d.h. auf Hosts ohne .env-Datei (Render!) fiel die
      // Validierung immer auf leer, selbst wenn alle Variablen korrekt
      // als echte Env-Variablen injiziert waren. Jetzt: process.env
      // fliesst in die Validierung ein (defensiv zusaetzlich in
      // validateEnv gemerged).
    }),
    // Global rate limiting - the mobile app is the only intended
    // caller, but the API is public-reachable (unlike GraphHopper/
    // Supabase behind it), so basic abuse protection is a day-1
    // requirement, not a later hardening pass.
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: 120 }]),
    SupabaseModule,
    AuthModule,
    RoutingModule,
    PoiModule,
    SearchModule,
    TrafficModule,
    RoundTripModule,
    UserModule,
    ChatModule,
    GroupRoutesModule,
    GroupRidesModule,
    BikerPoisModule,
    HazardsModule,
    WeatherModule,
    RideHistoryModule,
    MarketplaceModule,
  ],
  controllers: [HealthController],
  providers: [LoggingInterceptor],
})
export class AppModule {}
import { Body, Controller, HttpException, HttpStatus, Injectable, Module, Post } from '@nestjs/common';
import { IsEnum, IsLatitude, IsLongitude, IsNumber, Min } from 'class-validator';
import { RouteStyle } from '../routing/dto/create-route.dto';

/**
 * NOT PART OF THE MVP (Phase 1/2 Teil A.2 Punkt 4 / Teil G): round-trip
 * generation is algorithmically the hardest feature in the whole
 * product and is explicitly scoped out of the MVP. This module exists
 * only so the API surface and request shape are fixed early - per
 * Abschnitt 8 der Vorgaben ("Diese Funktion soll bereits
 * architektonisch berücksichtigt werden") - without pretending the
 * generation algorithm exists yet.
 *
 * Sobald das Rundtouren-Feature actualisiert wird, ersetze den
 * RoundTripService durch einer, der:
 * 1. Eine iterative Wegpunkt-Generierung durchführt (Ziel-Distanz
 *    einhalten, Stil maximieren, Rückkehr zum Start)
 * 2. Jede generierte Route über den GraphHopperClient validiert
 * 3. Das Ergebnis als Route-Entity zurückgibt
 */
export class CreateRoundTripDto {
  @IsLatitude()
  startLat: number;

  @IsLongitude()
  startLng: number;

  @IsNumber()
  @Min(1)
  targetDistanceKm: number;

  @IsEnum(RouteStyle)
  style: RouteStyle;
}

@Injectable()
export class RoundTripService {
  async generate(_dto: CreateRoundTripDto): Promise<never> {
    throw new HttpException(
      'Round-trip generation is not implemented in the MVP - see Phase 1/2 Teil A.2/G',
      HttpStatus.NOT_IMPLEMENTED,
    );
  }
}

@Controller('v1/roundtrips')
export class RoundTripController {
  constructor(private readonly roundTripService: RoundTripService) {}

  @Post()
  async create(@Body() dto: CreateRoundTripDto) {
    return this.roundTripService.generate(dto);
  }
}

@Module({
  controllers: [RoundTripController],
  providers: [RoundTripService],
})
export class RoundTripModule {}
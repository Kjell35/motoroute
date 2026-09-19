import { BadRequestException, Controller, Get, Injectable, Query } from '@nestjs/common';
import { TrafficIncident } from './tomtom.mapper';
import { TrafficService } from './traffic.service';

const BBOX_LENGTH = 4;

/**
 * Parses and validates "minLng,minLat,maxLng,maxLat".
 *
 * Explizit ablehnen statt still NaNs filtern: Der stille Fallback hat
 * den Fehler vorher nur verschoben (App fragt mit kaputter bbox nach,
 * bekommt [], glaubt "keine Vorfälle" statt "ungültige Anfrage").
 */
@Injectable()
export class BoundingBoxParser {
  parse(bbox: string | undefined): number[] {
    if (!bbox) {
      throw new BadRequestException('bbox query parameter is required (minLng,minLat,maxLng,maxLat)');
    }
    const parts = bbox.split(',').map(Number);
    if (parts.length !== BBOX_LENGTH || parts.some((n) => !Number.isFinite(n))) {
      throw new BadRequestException('bbox must be 4 comma-separated numbers: minLng,minLat,maxLng,maxLat');
    }
    const [minLng, minLat, maxLng, maxLat] = parts;
    if (minLng >= maxLng || minLat >= maxLat) {
      throw new BadRequestException('bbox min values must be smaller than max values');
    }
    return parts;
  }
}

@Controller('v1/traffic')
export class TrafficController {
  constructor(
    private readonly trafficService: TrafficService,
    private readonly bboxParser: BoundingBoxParser,
  ) {}

  @Get()
  async getIncidents(@Query('bbox') bbox: string): Promise<TrafficIncident[]> {
    const parsed = this.bboxParser.parse(bbox);
    return this.trafficService.getIncidentsInBoundingBox(parsed);
  }
}

import { Controller, Get, NotFoundException, Param, Query } from '@nestjs/common';
import { QueryPoisDto } from './dto/query-pois.dto';
import { Poi } from './entities/poi.entity';
import { PoiDetail } from './poi.detail';
import { PoiService } from './poi.service';

@Controller('v1/pois')
export class PoiController {
  constructor(private readonly poiService: PoiService) {}

  @Get()
  async findInBoundingBox(@Query() query: QueryPoisDto): Promise<Poi[]> {
    return this.poiService.findInBoundingBox(query);
  }

  /**
   * Detail-Endpunkt für das POI-Detail-Sheet der App: volle Metadaten
   * (website, opening_hours, bikerScore, address) + Herkunft
   * (Quelle, veröffentlicht am/von).
   */
  @Get(':id')
  async detail(@Param('id') id: string): Promise<PoiDetail> {
    const detail = await this.poiService.findDetail(id);
    if (!detail) {
      throw new NotFoundException({
        error: 'POI_NOT_FOUND',
        message: 'POI nicht gefunden',
      });
    }
    return detail;
  }
}

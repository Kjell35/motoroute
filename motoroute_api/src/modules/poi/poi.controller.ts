import { Controller, Get, Query } from '@nestjs/common';
import { QueryPoisDto } from './dto/query-pois.dto';
import { Poi } from './entities/poi.entity';
import { PoiService } from './poi.service';

@Controller('v1/pois')
export class PoiController {
  constructor(private readonly poiService: PoiService) {}

  @Get()
  async findInBoundingBox(@Query() query: QueryPoisDto): Promise<Poi[]> {
    return this.poiService.findInBoundingBox(query);
  }
}

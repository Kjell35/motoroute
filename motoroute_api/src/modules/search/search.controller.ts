import { Controller, Get, NotFoundException, Param, Query } from '@nestjs/common';
import { SearchQueryDto, SearchResult } from './dto/search-query.dto';
import { SearchService } from './search.service';

@Controller('v1/search')
export class SearchController {
  constructor(private readonly searchService: SearchService) {}

  @Get()
  async search(@Query() query: SearchQueryDto): Promise<SearchResult[]> {
    return this.searchService.search(query);
  }

  /** Reverse-Geocoding: Koordinaten -> lesbarer Name (Wegpunkt-Label). */
  @Get('reverse/:lat/:lng')
  async reverse(
    @Param('lat') lat: string,
    @Param('lng') lng: string,
  ): Promise<SearchResult> {
    const latNum = Number(lat);
    const lngNum = Number(lng);
    if (
      !Number.isFinite(latNum) ||
      !Number.isFinite(lngNum) ||
      latNum < -90 ||
      latNum > 90 ||
      lngNum < -180 ||
      lngNum > 180
    ) {
      throw new NotFoundException('Ungueltige Koordinaten');
    }
    const result = await this.searchService.reverse(latNum, lngNum);
    if (!result) {
      throw new NotFoundException('Ort konnte nicht aufgeloest werden');
    }
    return result;
  }
}

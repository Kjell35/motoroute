import { Controller, Get, Query } from '@nestjs/common';
import { SearchQueryDto, SearchResult } from './dto/search-query.dto';
import { SearchService } from './search.service';

@Controller('v1/search')
export class SearchController {
  constructor(private readonly searchService: SearchService) {}

  @Get()
  async search(@Query() query: SearchQueryDto): Promise<SearchResult[]> {
    return this.searchService.search(query);
  }
}

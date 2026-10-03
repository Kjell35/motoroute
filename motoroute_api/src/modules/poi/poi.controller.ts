import { Controller, Get, NotFoundException, Param, Query, Res } from '@nestjs/common';
import { Response } from 'express';
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
   * Foto-Proxy für Google-Places-Fotos: Der API-Key bleibt im Backend,
   * die App löst die relative URL (aus PoiDetail.imageUrl) gegen ihre
   * API-Basis auf. WICHTIG vor @Get(':id') deklariert - sonst würde die
   * id-Route 'photo' als ID fressen. Ohne Key/ungültigem name: 404.
   */
  @Get('photo')
  async photo(
    @Query('name') name: string,
    @Res() res: Response,
  ): Promise<void> {
    const photo = await this.poiService.fetchGooglePhoto(name ?? '');
    if (!photo) {
      res.status(404).json({ error: 'PHOTO_UNAVAILABLE' });
      return;
    }
    res.setHeader('Content-Type', photo.contentType);
    res.setHeader('Cache-Control', 'public, max-age=86400');
    res.send(photo.data);
  }

  /**
   * Detail-Endpunkt für das POI-Detail-Sheet der App: volle Metadaten
   * (website, opening_hours, bikerScore, address) + Herkunft
   * ("veröffentlicht am/von"). Die App reicht die Koordinaten und die
   * Kategorie des Karten-Treffers mit - damit kann der Endpunkt auch
   * Live-OSM-POIs ohne DB-Zeile über einen Google-Nearby-Match
   * anreichern (Bild, Beschreibung, Website), wenn GOOGLE_PLACES_API_KEY
   * gesetzt ist. Ohne Treffer gilt die ehrliche Kette OSM -> DB.
   */
  @Get(':id')
  async detail(
    @Param('id') id: string,
    @Query('lat') lat?: string,
    @Query('lng') lng?: string,
    @Query('category') category?: string,
  ): Promise<PoiDetail> {
    const detail = await this.poiService.findDetail(
      id,
      lat != null ? Number(lat) : undefined,
      lng != null ? Number(lng) : undefined,
      category,
    );
    if (!detail) {
      throw new NotFoundException({
        error: 'POI_NOT_FOUND',
        message: 'POI nicht gefunden',
      });
    }
    return detail;
  }
}

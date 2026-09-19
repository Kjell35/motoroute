import { Body, Controller, Delete, Get, HttpCode, Param, Post, Put, Req, UseGuards } from '@nestjs/common';
import { AuthProvider, AuthenticatedRequest } from '../../guards';
import { GroupRidesService } from './group-rides.service';
import { IsLatitude, IsLongitude } from 'class-validator';

export class RidePositionDto {
  @IsLatitude()
  lat: number;

  @IsLongitude()
  lng: number;
}

/**
 * Live-Gruppenfahrt: REST-Endpunkte. Positionen sind OPT-IN - der Client
 * ruft startSharing NUR nach ausdrücklicher Nutzerfreigabe auf.
 */
@Controller('v1/group-rides')
@UseGuards(AuthProvider)
export class GroupRidesController {
  constructor(private readonly rides: GroupRidesService) {}

  @Get(':routeId/live')
  live(@Req() req: AuthenticatedRequest, @Param('routeId') routeId: string): Promise<unknown> {
    return this.rides.liveState(req.user!, routeId);
  }

  @Post(':routeId/sharing')
  @HttpCode(204)
  async startSharing(
    @Req() req: AuthenticatedRequest,
    @Param('routeId') routeId: string,
    @Body() position: RidePositionDto,
  ): Promise<void> {
    await this.rides.startSharing(req.user!, routeId, position);
  }

  @Put(':routeId/heartbeat')
  @HttpCode(204)
  async heartbeat(
    @Req() req: AuthenticatedRequest,
    @Param('routeId') routeId: string,
    @Body() position: RidePositionDto,
  ): Promise<void> {
    await this.rides.heartbeat(req.user!, routeId, position);
  }

  @Delete(':routeId/sharing')
  @HttpCode(204)
  async stopSharing(@Req() req: AuthenticatedRequest, @Param('routeId') routeId: string): Promise<void> {
    await this.rides.stopSharing(req.user!, routeId);
  }

  @Post(':routeId/finish')
  @HttpCode(204)
  async finish(@Req() req: AuthenticatedRequest, @Param('routeId') routeId: string): Promise<void> {
    await this.rides.finish(req.user!, routeId);
  }
}

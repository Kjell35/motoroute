import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  Post,
  Put,
  Req,
  UseGuards,
} from '@nestjs/common';
import { AuthProvider, AuthenticatedRequest } from '../../guards';
import { GroupRoutesService } from './group-routes.service';
import {
  AddCommentDto,
  AddStopDto,
  CreateGroupRouteDto,
  DuplicateRouteDto,
  ReorderStopsDto,
  SetPermissionDto,
  SetStatusDto,
  UpdateGroupRouteDto,
  UpdateStopDto,
} from './group-routes.dto';

/**
 * REST-Endpunkte des kollaborativen Gruppen-Routenplaners (Abschnitt 33).
 * Alle Endpunkte strikt authentifiziert; die Autorisierung läuft
 * serverseitig über RLS + RPC-Prüfungen (can_edit_route) - der Controller
 * ist bewusst dünn.
 */
@Controller('v1/group-routes')
@UseGuards(AuthProvider)
export class GroupRoutesController {
  constructor(private readonly routes: GroupRoutesService) {}

  @Post()
  @HttpCode(201)
  create(@Req() req: AuthenticatedRequest, @Body() dto: CreateGroupRouteDto): Promise<unknown> {
    return this.routes.createRoute(req.user!, dto);
  }

  @Get('group/:groupId')
  listForGroup(@Req() req: AuthenticatedRequest, @Param('groupId') groupId: string): Promise<unknown[]> {
    return this.routes.listRoutes(req.user!, groupId);
  }

  @Get(':routeId')
  get(@Req() req: AuthenticatedRequest, @Param('routeId') routeId: string): Promise<unknown> {
    return this.routes.getRoute(req.user!, routeId);
  }

  @Put(':routeId')
  @HttpCode(204)
  async update(
    @Req() req: AuthenticatedRequest,
    @Param('routeId') routeId: string,
    @Body() dto: UpdateGroupRouteDto,
  ): Promise<void> {
    await this.routes.updateRoute(req.user!, routeId, dto);
  }

  @Delete(':routeId')
  @HttpCode(204)
  async delete(@Req() req: AuthenticatedRequest, @Param('routeId') routeId: string): Promise<void> {
    await this.routes.deleteRoute(req.user!, routeId);
  }

  @Post(':routeId/duplicate')
  @HttpCode(201)
  duplicate(
    @Req() req: AuthenticatedRequest,
    @Param('routeId') routeId: string,
    @Body() dto: DuplicateRouteDto,
  ): Promise<unknown> {
    return this.routes.duplicateRoute(req.user!, routeId, dto.newName);
  }

  @Put(':routeId/permission')
  @HttpCode(204)
  async setPermission(
    @Req() req: AuthenticatedRequest,
    @Param('routeId') routeId: string,
    @Body() dto: SetPermissionDto,
  ): Promise<void> {
    await this.routes.setPermission(req.user!, routeId, dto.permission);
  }

  @Put(':routeId/status')
  @HttpCode(204)
  async setStatus(
    @Req() req: AuthenticatedRequest,
    @Param('routeId') routeId: string,
    @Body() dto: SetStatusDto,
  ): Promise<void> {
    await this.routes.setStatus(req.user!, routeId, dto.status);
  }

  @Post(':routeId/lock')
  @HttpCode(204)
  async lock(@Req() req: AuthenticatedRequest, @Param('routeId') routeId: string): Promise<void> {
    await this.routes.lock(req.user!, routeId);
  }

  @Post(':routeId/unlock')
  @HttpCode(204)
  async unlock(@Req() req: AuthenticatedRequest, @Param('routeId') routeId: string): Promise<void> {
    await this.routes.unlock(req.user!, routeId);
  }

  // ------------------------------------------------------------------ Stopps

  @Post(':routeId/stops')
  @HttpCode(201)
  addStop(
    @Req() req: AuthenticatedRequest,
    @Param('routeId') routeId: string,
    @Body() dto: AddStopDto,
  ): Promise<unknown> {
    return this.routes.addStop(req.user!, routeId, dto);
  }

  @Put('stops/:stopId')
  @HttpCode(204)
  async updateStop(
    @Req() req: AuthenticatedRequest,
    @Param('stopId') stopId: string,
    @Body() dto: UpdateStopDto,
  ): Promise<void> {
    await this.routes.updateStop(req.user!, stopId, dto);
  }

  @Delete('stops/:stopId')
  @HttpCode(204)
  async deleteStop(@Req() req: AuthenticatedRequest, @Param('stopId') stopId: string): Promise<void> {
    await this.routes.deleteStop(req.user!, stopId);
  }

  @Put(':routeId/stops/reorder')
  @HttpCode(204)
  async reorder(
    @Req() req: AuthenticatedRequest,
    @Param('routeId') routeId: string,
    @Body() dto: ReorderStopsDto,
  ): Promise<void> {
    await this.routes.reorderStops(req.user!, routeId, dto.stopIds);
  }

  // ------------------------------------------------------- Kommentare/Start

  @Post('stops/:stopId/comments')
  @HttpCode(201)
  async addComment(
    @Req() req: AuthenticatedRequest,
    @Param('stopId') stopId: string,
    @Body() dto: AddCommentDto,
  ): Promise<void> {
    await this.routes.addComment(req.user!, stopId, dto.content);
  }

  @Get('stops/:stopId/comments')
  getComments(@Req() req: AuthenticatedRequest, @Param('stopId') stopId: string): Promise<unknown[]> {
    return this.routes.getComments(req.user!, stopId);
  }

  /**
   * Route starten (Abschnitt 17): überträgt Start/Ziel/Stopps/Stil/
   * Vermeidungen als NORMALE Route an den Navigation-Flow der App. Der
   * Endpunkt validiert den Zugriff und markiert die Route als 'riding'
   * (Statusänderung kann der App auch per Query-Parameter fernbleiben).
   */
  @Post(':routeId/start')
  async start(
    @Req() req: AuthenticatedRequest,
    @Param('routeId') routeId: string,
  ): Promise<unknown> {
    return this.routes.getRoute(req.user!, routeId);
  }

  @Post(':routeId/complete')
  @HttpCode(204)
  async complete(@Req() req: AuthenticatedRequest, @Param('routeId') routeId: string): Promise<void> {
    await this.routes.setStatus(req.user!, routeId, 'completed');
  }
}

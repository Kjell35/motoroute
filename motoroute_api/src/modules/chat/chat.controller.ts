import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  Post,
  Put,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import { AuthProvider, AuthenticatedRequest } from '../../guards';
import { ChatService } from './chat.service';
import {
  BlockUserDto,
  CreateGroupDto,
  CreateInvitationDto,
  JoinByCodeDto,
  PaginationQueryDto,
  RemoveMemberDto,
  ReportMessageDto,
  ReportUserDto,
  SearchUsersDto,
  SendMessageDto,
  StartPrivateChatDto,
  TransferOwnershipDto,
  TypingDto,
  UpdateGroupDto,
  UpdateProfileDtoChat,
} from './chat.dto';

/**
 * Chat-Controller - alle REST-Endpunkte des Chat-Systems unter /v1/chat.
 *
 * Jeder Endpunkt trägt den strikten AuthProvider: Der öffentliche Chat
 * ist explizit NUR für angemeldete Nutzer (Chat-Vorgabe Abschnitt 2/26),
 * Privates/Gruppen ohnehin. Es gibt hier bewusst keinen anonymen Zugang.
 */
@Controller('v1/chat')
@UseGuards(AuthProvider)
export class ChatController {
  constructor(private readonly chat: ChatService) {}

  // ---------------------------------------------------------------- Profil

  @Get('me')
  getMe(@Req() req: AuthenticatedRequest): Promise<unknown> {
    return this.chat.getProfile(req.user!);
  }

  @Put('me')
  updateMe(@Req() req: AuthenticatedRequest, @Body() dto: UpdateProfileDtoChat): Promise<unknown> {
    return this.chat.updateProfile(req.user!, dto as unknown as Record<string, unknown>);
  }

  @Get('users/search')
  searchUsers(@Req() req: AuthenticatedRequest, @Query() dto: SearchUsersDto): Promise<unknown[]> {
    return this.chat.searchUsers(req.user!, dto.query, dto.limit ?? 15);
  }

  @Get('users/:userId')
  getUserProfile(@Req() req: AuthenticatedRequest, @Param('userId') userId: string): Promise<unknown> {
    return this.chat.getUserProfile(req.user!, userId);
  }

  // -------------------------------------------------------- Konversationen

  @Get('conversations')
  listConversations(@Req() req: AuthenticatedRequest): Promise<unknown> {
    return this.chat.listConversations(req.user!);
  }

  @Get('conversations/:conversationId/members')
  listMembers(
    @Req() req: AuthenticatedRequest,
    @Param('conversationId') conversationId: string,
  ): Promise<unknown[]> {
    return this.chat.listMembers(req.user!, conversationId);
  }

  @Get('conversations/:conversationId/messages')
  fetchMessages(
    @Req() req: AuthenticatedRequest,
    @Param('conversationId') conversationId: string,
    @Query() query: PaginationQueryDto,
  ): Promise<unknown> {
    return this.chat.fetchMessages(req.user!, conversationId, query.before, query.limit ?? 30);
  }

  @Post('conversations/:conversationId/messages')
  @HttpCode(201)
  sendMessage(
    @Req() req: AuthenticatedRequest,
    @Param('conversationId') conversationId: string,
    @Body() dto: SendMessageDto,
  ): Promise<unknown> {
    return this.chat.sendMessage(req.user!, conversationId, dto.content, dto.attachment);
  }

  @Post('conversations/:conversationId/read')
  @HttpCode(204)
  async markRead(
    @Req() req: AuthenticatedRequest,
    @Param('conversationId') conversationId: string,
  ): Promise<void> {
    await this.chat.markRead(req.user!, conversationId);
  }

  @Delete('messages/:messageId')
  @HttpCode(204)
  async deleteMessage(@Req() req: AuthenticatedRequest, @Param('messageId') messageId: string): Promise<void> {
    await this.chat.deleteMessage(req.user!, messageId);
  }

  @Post('conversations/private')
  @HttpCode(201)
  startPrivateChat(@Req() req: AuthenticatedRequest, @Body() dto: StartPrivateChatDto): Promise<unknown> {
    return this.chat.startPrivateChat(req.user!, dto.otherUserId);
  }

  // ------------------------------------------------------ Typing & Presence

  @Post('typing')
  @HttpCode(204)
  async typing(@Req() req: AuthenticatedRequest, @Body() dto: TypingDto): Promise<void> {
    await this.chat.broadcastTyping(req.user!, dto.conversationId, dto.isTyping);
  }

  @Post('presence/touch')
  @HttpCode(204)
  async touchPresence(@Req() req: AuthenticatedRequest): Promise<void> {
    await this.chat.touchPresence(req.user!);
  }

  // ---------------------------------------------------------------- Gruppen

  @Post('groups')
  @HttpCode(201)
  createGroup(@Req() req: AuthenticatedRequest, @Body() dto: CreateGroupDto): Promise<unknown> {
    return this.chat.createGroup(req.user!, dto);
  }

  @Get('groups/:groupId')
  getGroup(@Req() req: AuthenticatedRequest, @Param('groupId') groupId: string): Promise<unknown> {
    return this.chat.getGroup(req.user!, groupId);
  }

  @Put('groups/:groupId')
  updateGroup(
    @Req() req: AuthenticatedRequest,
    @Param('groupId') groupId: string,
    @Body() dto: UpdateGroupDto,
  ): Promise<unknown> {
    return this.chat.updateGroup(req.user!, groupId, dto as unknown as Record<string, unknown>);
  }

  @Delete('groups/:groupId')
  @HttpCode(204)
  async deleteGroup(@Req() req: AuthenticatedRequest, @Param('groupId') groupId: string): Promise<void> {
    await this.chat.deleteGroup(req.user!, groupId);
  }

  @Post('groups/:groupId/leave')
  leaveGroup(@Req() req: AuthenticatedRequest, @Param('groupId') groupId: string): Promise<unknown> {
    return this.chat.leaveGroup(req.user!, groupId);
  }

  @Post('groups/:groupId/transfer-ownership')
  @HttpCode(204)
  async transferOwnership(
    @Req() req: AuthenticatedRequest,
    @Param('groupId') groupId: string,
    @Body() dto: TransferOwnershipDto,
  ): Promise<void> {
    await this.chat.transferOwnership(req.user!, groupId, dto.newOwnerId);
  }

  @Post('groups/:groupId/members/remove')
  @HttpCode(204)
  async removeMember(
    @Req() req: AuthenticatedRequest,
    @Param('groupId') groupId: string,
    @Body() dto: RemoveMemberDto,
  ): Promise<void> {
    await this.chat.removeMember(req.user!, groupId, dto.userId);
  }

  // -------------------------------------------------------- Einladungscodes

  @Post('groups/:groupId/invitations')
  @HttpCode(201)
  createInvitation(
    @Req() req: AuthenticatedRequest,
    @Param('groupId') groupId: string,
    @Body() dto: CreateInvitationDto,
  ): Promise<unknown> {
    return this.chat.createInvitation(req.user!, groupId, dto.expiresInDays);
  }

  @Post('groups/:groupId/invitations/deactivate')
  @HttpCode(204)
  async deactivateInvitation(@Req() req: AuthenticatedRequest, @Param('groupId') groupId: string): Promise<void> {
    await this.chat.deactivateInvitation(req.user!, groupId);
  }

  @Get('groups/:groupId/invitations/active')
  getActiveInvitation(@Req() req: AuthenticatedRequest, @Param('groupId') groupId: string): Promise<unknown> {
    return this.chat.getActiveInvitation(req.user!, groupId);
  }

  @Post('invitations/preview')
  previewByCode(@Req() req: AuthenticatedRequest, @Body() dto: JoinByCodeDto): Promise<unknown> {
    return this.chat.previewByCode(req.user!, dto.code);
  }

  @Post('invitations/join')
  joinByCode(@Req() req: AuthenticatedRequest, @Body() dto: JoinByCodeDto): Promise<unknown> {
    return this.chat.joinByCode(req.user!, dto.code);
  }

  // ------------------------------------------------------------- Moderation

  @Post('blocks')
  @HttpCode(204)
  async blockUser(@Req() req: AuthenticatedRequest, @Body() dto: BlockUserDto): Promise<void> {
    await this.chat.blockUser(req.user!, dto.userId);
  }

  @Delete('blocks/:userId')
  @HttpCode(204)
  async unblockUser(@Req() req: AuthenticatedRequest, @Param('userId') userId: string): Promise<void> {
    await this.chat.unblockUser(req.user!, userId);
  }

  @Get('blocks')
  listBlocked(@Req() req: AuthenticatedRequest): Promise<unknown[]> {
    return this.chat.listBlocked(req.user!);
  }

  @Post('reports/message')
  @HttpCode(201)
  async reportMessage(@Req() req: AuthenticatedRequest, @Body() dto: ReportMessageDto): Promise<void> {
    await this.chat.reportMessage(req.user!, dto.messageId, dto.reason, dto.details);
  }

  @Post('reports/user')
  @HttpCode(201)
  async reportUser(@Req() req: AuthenticatedRequest, @Body() dto: ReportUserDto): Promise<void> {
    await this.chat.reportUser(req.user!, dto.reportedUserId, dto.reason, dto.details);
  }

  // ------------------------------------------------------ Realtime-Config

  /**
   * Liefert der App die Supabase-Realtime-Verbindungsdaten. Der anon key
   * ist dafür gedacht, in der App verwendet zu werden (er autorisiert
   * nichts über RLS hinaus) - kein Secret, keine Service-Role.
   */
  @Get('realtime/config')
  realtimeConfig(@Req() req: AuthenticatedRequest): unknown {
    void req;
    return this.chat.realtimeConfig();
  }
}

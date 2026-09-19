import { Module } from '@nestjs/common';
import { SupabaseModule } from '../../supabase/supabase.module';
import { AuthProvider, SupabaseAuthService } from '../../guards';
import { RoutingModule } from '../routing/routing.module';
import { ChatModule } from '../chat/chat.module';
import { GroupRoutesController } from './group-routes.controller';
import { GroupRoutesService } from './group-routes.service';
import { GroupRoutesGateway } from './group-routes.gateway';

@Module({
  imports: [SupabaseModule, RoutingModule, ChatModule],
  controllers: [GroupRoutesController],
  providers: [GroupRoutesService, GroupRoutesGateway, AuthProvider, SupabaseAuthService],
})
export class GroupRoutesModule {}

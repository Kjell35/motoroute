import { Module } from '@nestjs/common';
import { GraphHopperClient } from './graphhopper.client';
import { RoutingController } from './routing.controller';
import { RoutingService } from './routing.service';

@Module({
  controllers: [RoutingController],
  providers: [RoutingService, GraphHopperClient],
  exports: [RoutingService],
})
export class RoutingModule {}

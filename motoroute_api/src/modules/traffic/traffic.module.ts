import { Module } from '@nestjs/common';
import { BoundingBoxParser, TrafficController } from './traffic.controller';
import { TrafficService } from './traffic.service';

@Module({
  controllers: [TrafficController],
  providers: [TrafficService, BoundingBoxParser],
})
export class TrafficModule {}

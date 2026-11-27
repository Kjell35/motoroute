import { Module } from '@nestjs/common';
import { PairingController } from './pairing.controller';
import { PairingPlanPageController } from './pairing-plan-page.controller';
import { PairingService } from './pairing.service';

@Module({
  controllers: [PairingController, PairingPlanPageController],
  providers: [PairingService],
})
export class PairingModule {}

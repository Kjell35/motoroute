import {
  IsBoolean,
  IsInt,
  IsIn,
  IsNotEmpty,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  Length,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

/** Query-Klammer für Listen-Endpunkte (Pagination, Abschnitt 36). */
export class PaginationQueryDto {
  @IsOptional()
  @IsString()
  @MaxLength(64)
  before?: string; // ISO-Timestamp-Cursor

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(50)
  limit?: number;
}

export class SendMessageDto {
  @IsNotEmpty()
  @IsString()
  @MaxLength(2000)
  content: string;

  /**
   * Architektur-Vorbereitung für Bilder/GPX/Routen/Standort
   * (Chat-Vorgabe Abschnitt 20/38). Struktur wird als JSONB gespeichert -
   * die Validierung der einzelnen Typen kommt mit dem jeweiligen Feature
   * ("Route teilen" etc.).
   */
  @IsOptional()
  @IsObject()
  attachment?: Record<string, unknown>;
}

export class UpdateProfileDtoChat {
  @IsOptional()
  @IsString()
  @Length(1, 40)
  username?: string;

  @IsOptional()
  @IsString()
  @Length(1, 80)
  displayName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  avatarUrl?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  vehicleDesc?: string;

  @IsOptional()
  @IsString()
  @MaxLength(280)
  bio?: string;
}

export class CreateGroupDto {
  @IsString()
  @Length(1, 60)
  name: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  imageUrl?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  category?: string;
}

export class UpdateGroupDto {
  @IsOptional()
  @IsString()
  @Length(1, 60)
  name?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  imageUrl?: string;
}

export class JoinByCodeDto {
  @IsString()
  @Length(4, 40)
  code: string;
}

export class CreateInvitationDto {
  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(365 * 2)
  expiresInDays?: number;
}

export class RemoveMemberDto {
  @IsUUID()
  userId: string;
}

export class BlockUserDto {
  @IsUUID()
  userId: string;
}

export class ReportMessageDto {
  @IsUUID()
  messageId: string;

  @IsIn(['spam', 'harassment', 'insult', 'inappropriate', 'fraud', 'other'])
  reason: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  details?: string;
}

export class ReportUserDto {
  @IsUUID()
  reportedUserId: string;

  @IsIn(['spam', 'harassment', 'insult', 'inappropriate', 'fraud', 'other'])
  reason: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  details?: string;
}

export class SearchUsersDto {
  @IsString()
  @Length(2, 40)
  query: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(25)
  limit?: number;
}

export class StartPrivateChatDto {
  @IsUUID()
  otherUserId: string;
}

export class TransferOwnershipDto {
  @IsUUID()
  newOwnerId: string;
}

export class TypingDto {
  @IsUUID()
  conversationId: string;

  @IsBoolean()
  isTyping: boolean;
}

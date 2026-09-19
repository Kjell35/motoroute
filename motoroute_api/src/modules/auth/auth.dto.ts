import { IsEmail, IsOptional, IsString, Length, MaxLength, MinLength } from 'class-validator';

export class LoginDto {
  @IsEmail()
  email: string;

  @IsString()
  @MinLength(6)
  @MaxLength(128)
  password: string;
}

export class RegisterDto extends LoginDto {
  @IsOptional()
  @IsString()
  @Length(1, 80)
  displayName?: string;
}

export class RefreshDto {
  @IsString()
  @Length(10, 512)
  refreshToken: string;
}

/** Antwort-Form für login/register/refresh - Spiegel der App-Seite. */
export interface AuthSession {
  accessToken: string;
  refreshToken: string;
  expiresInSeconds: number;
  user: {
    id: string;
    email?: string;
    displayName?: string;
  };
}

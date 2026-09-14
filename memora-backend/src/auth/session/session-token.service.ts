import { randomUUID } from 'node:crypto';
import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService, JwtSignOptions } from '@nestjs/jwt';

/** Config stores durations as plain strings ("15m", "30d"); jsonwebtoken's
 *  types want its own branded StringValue — cast at this one boundary. */
function expiresIn(ttl: string): JwtSignOptions['expiresIn'] {
  return ttl as JwtSignOptions['expiresIn'];
}

export type SessionTokenType = 'session_access' | 'session_refresh';

export interface SessionJwtPayload {
  sub: string;
  type: SessionTokenType;
  jti: string;
}

export interface IssuedRefreshToken {
  token: string;
  jti: string;
}

/**
 * Issues and validates memora's own session JWTs (access + refresh). A
 * single signing secret is used for both; the `type` claim keeps an access
 * token from being usable as a refresh token and vice versa. Never logs a
 * token or its payload.
 */
@Injectable()
export class SessionTokenService {
  constructor(
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
  ) {}

  issueAccessToken(userId: string): string {
    return this.sign(userId, 'session_access', this.accessTtl);
  }

  issueRefreshToken(userId: string): IssuedRefreshToken {
    const jti = randomUUID();
    const token = this.jwtService.sign(
      { sub: userId, type: 'session_refresh', jti } satisfies SessionJwtPayload,
      { secret: this.secret, expiresIn: expiresIn(this.refreshTtl) },
    );
    return { token, jti };
  }

  verifyAccessToken(token: string): SessionJwtPayload {
    return this.verify(token, 'session_access');
  }

  verifyRefreshToken(token: string): SessionJwtPayload {
    return this.verify(token, 'session_refresh');
  }

  private sign(userId: string, type: SessionTokenType, ttl: string): string {
    return this.jwtService.sign(
      { sub: userId, type, jti: randomUUID() } satisfies SessionJwtPayload,
      { secret: this.secret, expiresIn: expiresIn(ttl) },
    );
  }

  private verify(
    token: string,
    expectedType: SessionTokenType,
  ): SessionJwtPayload {
    let payload: SessionJwtPayload;
    try {
      payload = this.jwtService.verify<SessionJwtPayload>(token, {
        secret: this.secret,
      });
    } catch {
      throw new UnauthorizedException();
    }
    if (payload.type !== expectedType) {
      throw new UnauthorizedException();
    }
    return payload;
  }

  private get secret(): string {
    const secret = this.configService.get<string>('JWT_SESSION_SECRET');
    if (!secret) {
      throw new Error('JWT_SESSION_SECRET is not configured');
    }
    return secret;
  }

  private get accessTtl(): string {
    return this.configService.get<string>('JWT_SESSION_ACCESS_TTL') ?? '15m';
  }

  private get refreshTtl(): string {
    return this.configService.get<string>('JWT_SESSION_REFRESH_TTL') ?? '30d';
  }
}

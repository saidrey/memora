import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import {
  GOOGLE_AUTH_CLIENT,
} from './google-auth/google-auth-client.interface';
import { GoogleOAuthClient } from './google-auth/google-oauth.client';
import { SessionAuthGuard } from './session/session-auth.guard';
import { SessionRegistry } from './session/session-registry';
import { SessionTokenService } from './session/session-token.service';
import { TOKEN_STORE } from './tokens/token-store.interface';
import { InMemoryTokenStore } from './tokens/in-memory-token.store';
import { USER_REPOSITORY } from './users/user-repository.interface';
import { InMemoryUserRepository } from './users/in-memory-user.repository';

@Module({
  imports: [ConfigModule.forRoot(), JwtModule.register({})],
  controllers: [AuthController],
  providers: [
    AuthService,
    SessionTokenService,
    SessionRegistry,
    SessionAuthGuard,
    { provide: GOOGLE_AUTH_CLIENT, useClass: GoogleOAuthClient },
    { provide: USER_REPOSITORY, useClass: InMemoryUserRepository },
    { provide: TOKEN_STORE, useClass: InMemoryTokenStore },
  ],
  // SessionAuthGuard is reused by other modules (e.g. albums) to protect
  // their own endpoints with the same session check — its own dependency
  // (SessionTokenService) must be exported too, or Nest fails to resolve
  // it when instantiating the guard in the importing module's context.
  exports: [SessionAuthGuard, SessionTokenService],
})
export class AuthModule {}

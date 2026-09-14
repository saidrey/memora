import {
  Body,
  Controller,
  HttpCode,
  HttpStatus,
  Post,
  UseGuards,
} from '@nestjs/common';
import { requireStringField } from '../common/validation/require-string-field';
import { AuthService } from './auth.service';
import { CurrentUser } from './session/current-user.decorator';
import { SessionAuthGuard } from './session/session-auth.guard';

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('google')
  async loginWithGoogle(@Body() body: unknown) {
    const serverAuthCode = requireStringField(body, 'serverAuthCode');
    const { session, user } =
      await this.authService.loginWithGoogle(serverAuthCode);

    return {
      sessionAccessToken: session.accessToken,
      sessionRefreshToken: session.refreshToken,
      user,
    };
  }

  @Post('refresh')
  refresh(@Body() body: unknown) {
    const sessionRefreshToken = requireStringField(
      body,
      'sessionRefreshToken',
    );
    const session = this.authService.refreshSession(sessionRefreshToken);

    return {
      sessionAccessToken: session.accessToken,
      sessionRefreshToken: session.refreshToken,
    };
  }

  @Post('logout')
  @UseGuards(SessionAuthGuard)
  @HttpCode(HttpStatus.NO_CONTENT)
  logout(@CurrentUser() user: { id: string }): void {
    this.authService.logout(user.id);
  }

  @Post('drive-token')
  @UseGuards(SessionAuthGuard)
  async getDriveToken(@CurrentUser() user: { id: string }) {
    const token = await this.authService.getDriveAccessToken(user.id);
    return { driveAccessToken: token.accessToken, expiresIn: token.expiresInSeconds };
  }
}

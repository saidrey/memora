import { Controller, Get, HttpStatus, Param, Redirect } from '@nestjs/common';
import { NfcQrResolveService } from './nfc-qr-resolve.service';

/**
 * THE PUBLIC NFC/QR endpoint (spec10-nfc-qr.md). Deliberately has NO
 * `@UseGuards(SessionAuthGuard)` — same mechanism as `SharedController`
 * (spec09): this backend never registers a global `APP_GUARD`, so simply
 * not decorating this controller IS what makes it public.
 *
 * Route is `GET /api/v1/n/:token`, NOT `GET /api/v1/nfc-qr-tags/:id` as the
 * spec's own prose literally says in two places — see
 * memora-backend/README.md "NFC/QR (spec10-nfc-qr)" for the full
 * explanation. `:token` here is the tag's OPAQUE token (what's physically
 * recorded on the NFC/QR), never Memora's internal tag id (that's the
 * owner-only `GET /api/v1/nfc-qr-tags/:id` in `nfc-qr-tag.controller.ts`).
 *
 * Still gets the uniform error contract and `x-request-id` "for free" via
 * `configureApp()` (global filter/middleware, independent of guards).
 */
@Controller('n')
export class NfcQrResolveController {
  constructor(private readonly resolveService: NfcQrResolveService) {}

  @Get(':token')
  @Redirect()
  async resolve(@Param('token') token: string) {
    const url = await this.resolveService.resolve(token);
    return { url, statusCode: HttpStatus.FOUND };
  }
}

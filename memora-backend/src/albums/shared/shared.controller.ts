import { Controller, Get, Param } from '@nestjs/common';
import { SharedViewService } from './shared-view.service';

/**
 * THE FIRST PUBLIC ENDPOINT of this backend (spec09-compartir-visor.md, D2).
 *
 * Deliberately has NO `@UseGuards(SessionAuthGuard)` — and needs no
 * "opt-out" mechanism to achieve that. This codebase never registers a
 * global `APP_GUARD`; every other controller (AlbumsController,
 * PhotosController, InvitationsController, ...) applies
 * `@UseGuards(SessionAuthGuard)` explicitly on itself. So the absence of
 * that decorator here IS the entire mechanism — there is nothing else to
 * wire. See `memora-backend/CLAUDE.md` for the note documenting this for
 * future controllers.
 *
 * It still gets the uniform error contract (`{code,message,requestId}`)
 * and `x-request-id` correlation "for free": `configureApp()`
 * (`src/bootstrap.ts`) applies `AllExceptionsFilter` and the request-id
 * middleware globally, ahead of routing and independent of any guard.
 *
 * Management (`POST`/`DELETE .../share-link`) stays authenticated and
 * owner-only — see `share-link.controller.ts`.
 */
@Controller('shared')
export class SharedController {
  constructor(private readonly sharedViewService: SharedViewService) {}

  @Get(':token')
  get(@Param('token') token: string) {
    return this.sharedViewService.resolve(token);
  }
}

import { All, Controller, NotFoundException } from '@nestjs/common';

/**
 * Catch-all for any path that doesn't match a real route, so a nonexistent
 * resource goes through Nest's pipeline (and AllExceptionsFilter) instead of
 * the platform's raw 404. Must stay the LAST controller registered — see
 * NotFoundModule's placement at the end of AppModule.imports.
 */
@Controller()
export class NotFoundController {
  @All('*')
  handle(): never {
    throw new NotFoundException('Resource not found');
  }
}

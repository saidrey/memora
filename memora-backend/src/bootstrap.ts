import { INestApplication } from '@nestjs/common';
import { AllExceptionsFilter } from './common/filters/all-exceptions.filter';
import { requestIdMiddleware } from './common/middleware/request-id.middleware';

/**
 * Applies the API's base contract (global/spec02-contrato-api.md) to a Nest
 * application instance. Shared by main.ts and the e2e test bootstrap so both
 * exercise the exact same request pipeline.
 */
export function configureApp(app: INestApplication): void {
  app.use(requestIdMiddleware);

  // Unversioned health probe for infrastructure (load balancers, uptime
  // checks), per the updated spec01-fundacion-backend.md. Registered on the
  // raw HTTP adapter — bypassing Nest's controller routing entirely — so it
  // can coexist with the versioned /api/v1/health controller below without
  // colliding: both declare the same sub-path ("health"), and
  // setGlobalPrefix's `exclude` matches by path pattern, not by controller,
  // so it can't tell the two apart.
  app.getHttpAdapter().get('/health', (_req, res) => {
    res.status(200).json({ status: 'ok' });
  });

  app.setGlobalPrefix('api/v1');
  app.useGlobalFilters(new AllExceptionsFilter());
}

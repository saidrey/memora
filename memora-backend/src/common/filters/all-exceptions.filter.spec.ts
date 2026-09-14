import { ArgumentsHost, HttpException, HttpStatus } from '@nestjs/common';
import { AllExceptionsFilter } from './all-exceptions.filter';
import { REQUEST_ID_HEADER } from '../middleware/request-id.middleware';

function createHost(requestId?: string) {
  const json = jest.fn();
  const status = jest.fn().mockReturnValue({ json });
  const response = { status } as any;
  const request = {
    headers: requestId ? { [REQUEST_ID_HEADER]: requestId } : {},
  } as any;

  const host = {
    switchToHttp: () => ({
      getRequest: () => request,
      getResponse: () => response,
    }),
  } as unknown as ArgumentsHost;

  return { host, status, json };
}

describe('AllExceptionsFilter', () => {
  const filter = new AllExceptionsFilter();

  it('maps an HttpException to its status, a machine-readable code, and the requestId', () => {
    const { host, status, json } = createHost('req-1');

    filter.catch(new HttpException('Not allowed', HttpStatus.FORBIDDEN), host);

    expect(status).toHaveBeenCalledWith(403);
    expect(json).toHaveBeenCalledWith({
      code: 'FORBIDDEN',
      message: 'Not allowed',
      requestId: 'req-1',
    });
  });

  it('maps an unknown thrown value to a generic 500 without leaking internals', () => {
    const { host, status, json } = createHost('req-2');

    filter.catch(new Error('db connection string leaked'), host);

    expect(status).toHaveBeenCalledWith(500);
    expect(json).toHaveBeenCalledWith({
      code: 'INTERNAL_SERVER_ERROR',
      message: 'Internal server error',
      requestId: 'req-2',
    });
  });

  it('omits requestId when the client sent none', () => {
    const { host, json } = createHost(undefined);

    filter.catch(new HttpException('Nope', HttpStatus.BAD_REQUEST), host);

    expect(json).toHaveBeenCalledWith({
      code: 'BAD_REQUEST',
      message: 'Nope',
      requestId: undefined,
    });
  });
});

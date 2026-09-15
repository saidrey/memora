import { Injectable } from '@nestjs/common';
import { SessionRegistry } from './session-registry.interface';

/** In-memory mock behind the `SessionRegistry` interface — same shape as
 *  every other `in-memory-*.repository.ts` in this backend. */
@Injectable()
export class InMemorySessionRegistry implements SessionRegistry {
  private readonly activeJtiByUser = new Map<string, Set<string>>();

  register(userId: string, jti: string): void {
    const jtis = this.activeJtiByUser.get(userId) ?? new Set<string>();
    jtis.add(jti);
    this.activeJtiByUser.set(userId, jtis);
  }

  isActive(userId: string, jti: string): boolean {
    return this.activeJtiByUser.get(userId)?.has(jti) ?? false;
  }

  revokeAll(userId: string): void {
    this.activeJtiByUser.delete(userId);
  }
}

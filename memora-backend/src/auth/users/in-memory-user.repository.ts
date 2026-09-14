import { randomUUID } from 'node:crypto';
import { Injectable } from '@nestjs/common';
import { User, UserRepository } from './user-repository.interface';

@Injectable()
export class InMemoryUserRepository implements UserRepository {
  private readonly usersById = new Map<string, User>();
  private readonly idByGoogleId = new Map<string, string>();

  async findByGoogleId(googleId: string): Promise<User | null> {
    const id = this.idByGoogleId.get(googleId);
    return id ? (this.usersById.get(id) ?? null) : null;
  }

  async create(user: Omit<User, 'id'>): Promise<User> {
    const created: User = { id: randomUUID(), ...user };
    this.usersById.set(created.id, created);
    this.idByGoogleId.set(created.googleId, created.id);
    return created;
  }
}

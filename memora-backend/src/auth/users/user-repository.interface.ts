export const USER_REPOSITORY = Symbol('USER_REPOSITORY');

export interface User {
  id: string;
  googleId: string;
  email: string;
  name?: string;
}

/** Migrating to a real database later means implementing this interface. */
export interface UserRepository {
  findByGoogleId(googleId: string): Promise<User | null>;
  create(user: Omit<User, 'id'>): Promise<User>;
}

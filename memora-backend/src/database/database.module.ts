import { Global, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Kysely, PostgresDialect } from 'kysely';
import { Pool } from 'pg';
import { Database, KYSELY } from './database.types';

@Global()
@Module({
  providers: [
    {
      provide: KYSELY,
      inject: [ConfigService],
      useFactory: (config: ConfigService) => {
      const url =
        config.get<string>('DATABASE_URL_POOLED') ??
        config.get<string>('DATABASE_URL') ??
        (process.env.NODE_ENV === 'test'
          ? 'postgres://localhost/memora'
          : undefined);
        if (!url) throw new Error('DATABASE_URL is not configured');
        return new Kysely<Database>({
          dialect: new PostgresDialect({
            pool: new Pool({
              connectionString: url,
              ssl: { rejectUnauthorized: false },
            }),
          }),
        });
      },
    },
  ],
  exports: [KYSELY],
})
export class DatabaseModule {}

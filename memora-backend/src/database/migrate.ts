import 'dotenv/config';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { Pool } from 'pg';

async function main() {
  const connectionString =
    process.env.DATABASE_DIRECT_URL ?? process.env.DATABASE_URL;
  if (!connectionString)
    throw new Error('DATABASE_URL or DATABASE_DIRECT_URL is required');
  const pool = new Pool({
    connectionString,
    ssl: { rejectUnauthorized: false },
  });
  const client = await pool.connect();
  try {
    await client.query(
      'CREATE TABLE IF NOT EXISTS schema_migrations (version text PRIMARY KEY, applied_at timestamptz NOT NULL)',
    );
    const migrations = [
      ['001_initial', 'migrations/001_initial.sql'],
      ['003_album_drive_folder', 'migrations/003_album_drive_folder.sql'],
    ] as const;
    for (const [version, file] of migrations) {
      const applied = await client.query(
        'SELECT 1 FROM schema_migrations WHERE version = $1',
        [version],
      );
      if (applied.rowCount !== 0) continue;
      await client.query('BEGIN');
      await client.query(await readFile(join(__dirname, file), 'utf8'));
      await client.query(
        'INSERT INTO schema_migrations(version, applied_at) VALUES ($1, NOW())',
        [version],
      );
      await client.query('COMMIT');
    }
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
    await pool.end();
  }
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

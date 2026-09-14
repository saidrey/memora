import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';

/**
 * spec08-abstraccion-almacenamiento.md (normative): "El dominio (álbumes,
 * colaboradores, disponibilidad, biblioteca) NO SHALL referirse a 'Drive'
 * ni a driveFileId; SHALL usar Photo.storageRef y ... la interfaz
 * PhotoStorage." This test enforces that mechanically instead of trusting
 * it stays true by convention — it scans every .ts source file under
 * src/albums, excluding:
 *  - src/albums/photos/storage/ — the one place allowed to know the
 *    concrete provider (that's the point of the abstraction: it's isolated
 *    there).
 *  - *.module.ts — the composition root necessarily names the concrete
 *    class (GoogleDrivePhotoStorage) to wire it up via DI, same as it
 *    already names InMemoryPhotoRepository etc.; that's wiring, not
 *    business logic.
 *  - *.spec.ts files anywhere — test fixtures legitimately use fake ids
 *    like 'drive-file-1' as opaque strings; that's test data, not the
 *    domain's own business logic referencing the provider.
 */
const ALBUMS_SRC_ROOT = join(__dirname);
const EXCLUDED_DIR_SEGMENT = `${sep}photos${sep}storage${sep}`;

function collectTsFiles(dir: string): string[] {
  const entries = readdirSync(dir);
  return entries.flatMap((entry) => {
    const fullPath = join(dir, entry);
    const stats = statSync(fullPath);
    if (stats.isDirectory()) {
      return collectTsFiles(fullPath);
    }
    if (!fullPath.endsWith('.ts')) return [];
    return [fullPath];
  });
}

describe('Domain storage neutrality (spec08-abstraccion-almacenamiento)', () => {
  it('no file under src/albums (outside photos/storage/ and test specs) references "driveFileId" or "Drive" literally', () => {
    const offenders: { file: string; matches: string[] }[] = [];

    for (const file of collectTsFiles(ALBUMS_SRC_ROOT)) {
      const isStorageImplementation = file.includes(EXCLUDED_DIR_SEGMENT);
      const isTestSpec = file.endsWith('.spec.ts');
      const isModuleWiring = file.endsWith('.module.ts');
      if (isStorageImplementation || isTestSpec || isModuleWiring) continue;

      const content = readFileSync(file, 'utf8');
      const matches = [...content.matchAll(/driveFileId|Drive/g)].map(
        (m) => m[0],
      );
      if (matches.length > 0) {
        offenders.push({ file: relative(process.cwd(), file), matches });
      }
    }

    expect(offenders).toEqual([]);
  });
});

// Golden files live gzipped in the repo (test/golden/*.json.gz, ~2 MB instead of ~12): `pnpm parity` regenerates
// the JSON and compresses it. A plain .json next to it (a fresh run) wins.

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { gunzipSync } from "node:zlib";

export const goldenDir = join(import.meta.dirname, "golden");

export function loadGolden<T>(name: string): T | null {
  const plain = join(goldenDir, name);
  if (existsSync(plain)) return JSON.parse(readFileSync(plain, "utf8"));
  const gz = plain + ".gz";
  if (existsSync(gz)) return JSON.parse(gunzipSync(readFileSync(gz)).toString("utf8"));
  return null;
}

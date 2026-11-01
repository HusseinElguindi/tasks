import { defineConfig } from "vitest/config";

// The core port and parity run in Node (pure TypeScript, Intl with full ICU). The Worker tests (test/workers) run
// in workerd: vitest.workers.config.ts.
export default defineConfig({
  test: { include: ["test/**/*.test.ts"], exclude: ["test/workers/**"] },
});

import { defineConfig } from "vitest/config";

// Phase 1: the core port and parity run in Node (pure TypeScript, Intl with full ICU).
// The Worker tests (Replica DO, code mode, OAuth) get the Cloudflare pool in later phases.
export default defineConfig({
  test: { include: ["test/**/*.test.ts"] },
});

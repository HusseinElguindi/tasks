import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";
import { goldenHandler, syncHandler, TOKEN } from "./test/workers/servers.ts";

// The Worker tests: the Replica DO in workerd, its SYNC binding a Node function that forwards to local copies of
// server/ with a dummy token (test/workers/servers.ts). One file at a time: they share that function's state.
export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: { bindings: { SYNC_TOKEN: TOKEN, SETUP_SECRET: "test-setup-secret" }, serviceBindings: { SYNC: syncHandler, GOLDEN: goldenHandler } },
    }),
  ],
  test: {
    include: ["test/workers/**/*.test.ts"],
    globalSetup: ["./test/workers/global-setup.ts"],
    fileParallelism: false,
    testTimeout: 60_000,
    hookTimeout: 180_000,
  },
});

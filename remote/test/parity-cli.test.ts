// The command layer against the real CLI (test/cli-parity.ts), in Node with a sucrase + Function sandbox. Error
// positions are compared in the Worker test, where scripts run on Worker Loader as they do in production.

import { describe, expect, it } from "vitest";
import { logEntries, runCase, type Golden } from "./cli-parity.ts";
import { loadGolden } from "./golden.ts";
import { nodeSandbox } from "./sandbox.ts";

const golden = loadGolden<Golden>("cli-scenarios.json");

describe.skipIf(!golden)("cli-scenarios.json", () => {
  const entries = golden ? logEntries(golden) : [];
  for (const c of golden?.cases ?? []) {
    // The 10 s limit is real time, as in the CLI.
    it(c.name, { timeout: 20_000 }, async () => {
      const r = await runCase(golden!, entries, c, nodeSandbox, { positions: false });
      expect(r.got).toEqual(r.want);
      // Key order too: the MCP tool returns this object's JSON text.
      expect(JSON.stringify(r.got)).toBe(JSON.stringify(r.want));
      expect(r.ourOps).toEqual(r.theirOps);
    });
  }
});

import { reset } from "cloudflare:test";
import { afterEach, beforeEach, vi } from "vitest";
import { NOW } from "./helpers";

// Each test starts with an empty log and a fixed server clock (the DO runs in this isolate).
beforeEach(async () => {
  await reset();
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(NOW);
});
afterEach(() => {
  vi.useRealTimers();
});

// A sandbox for the tests: the script runs in this process, its TypeScript stripped by sucrase, with the bridge's
// semantics (calls answered asynchronously, errors rebuilt from their JSON, results and arguments through JSON).
// The Worker uses Worker Loader instead (phase 3); the call and error shapes are the same.

import { transform } from "sucrase";
import type { CallResult } from "../src/cli/commands.ts";
import type { Json } from "../src/cli/render.ts";
import { scriptError, show, wireArgs, type Sandbox, type SandboxOutcome } from "../src/cli/run.ts";

/** The CLI's limit (TASKS_RUN_TIMEOUT, 10 s by default). */
export const TIMEOUT_SECONDS = 10;

export const nodeSandbox: Sandbox = async (source, call) => {
  const logs: string[] = [];
  const log = (...a: unknown[]) => logs.push(a.map(show).join(" "));
  const consoleShim = { log, info: log, warn: log, error: log, debug: log };
  const tasks = new Proxy({}, {
    get: (_, name) => (typeof name !== "string" || name === "then" ? undefined : async (...args: unknown[]) => {
      const r: CallResult = await call(name, wireArgs(args));
      if ("error" in r) {
        const e = new Error(r.error.message);
        e.name = r.error.type;
        Object.assign(e, r.error);
        throw e;
      }
      return r.result;
    }),
  });
  let fn: (tasks: unknown, console: unknown) => Promise<unknown>;
  try {
    const js = transform("(async () => {\n" + source + "\n})", { transforms: ["typescript"], disableESTransforms: true }).code;
    fn = new Function("tasks", "console", "return " + js.trim().replace(/;$/, "")) as typeof fn;
  } catch (e) {
    return { ok: false, error: { type: "SyntaxError", message: String((e as Error).message) }, logs } satisfies SandboxOutcome;
  }
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timedOut = new Promise<SandboxOutcome>((resolve) => {
    timer = setTimeout(() => resolve({
      ok: false, hostError: true, error: { type: "Limit", message: `The script ran longer than ${TIMEOUT_SECONDS} s, so it was stopped.` }, logs,
    }), TIMEOUT_SECONDS * 1000);
  });
  const ran = (async (): Promise<SandboxOutcome> => {
    try {
      const result = await (fn(tasks, consoleShim) as unknown as () => Promise<unknown>)();
      return { ok: true, result: result === undefined ? null : (JSON.parse(JSON.stringify(result) ?? "null") as Json), logs };
    } catch (e) {
      return { ok: false, error: scriptError(e), logs };
    }
  })();
  try {
    return await Promise.race([ran, timedOut]);
  } finally {
    clearTimeout(timer);
  }
};

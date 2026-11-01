// A sandbox for the Node tests: the script runs in this process, its TypeScript stripped by sucrase, with the
// bridge's semantics (script-sandbox.ts).

import { transform } from "sucrase";
import { functionSandbox, type ScriptFn } from "./script-sandbox.ts";

export { TIMEOUT_SECONDS } from "./script-sandbox.ts";

export const nodeSandbox = functionSandbox((source) => {
  const js = transform("(async () => {\n" + source + "\n})", { transforms: ["typescript"], disableESTransforms: true }).code;
  const make = new Function("tasks", "console", "return " + js.trim().replace(/;$/, "")) as (tasks: unknown, console: unknown) => () => Promise<unknown>;
  return ((tasks, console) => make(tasks, console)()) as ScriptFn;
});

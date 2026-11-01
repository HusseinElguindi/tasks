// Stops the local servers test/workers/servers.ts started (they're shared through globalThis).
import { closeAll } from "./servers.ts";

export default () => closeAll;

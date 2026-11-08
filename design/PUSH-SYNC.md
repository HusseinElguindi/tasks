# Push sync: a WebSocket poke instead of polling

Status: design study, 2026-11-08 (coord title-design T20). Nothing here is built.

The question (the user, 2026-11-08): "what do you think about push notifs (websocket or sse) for the clients? how
expensive is that and what benefits over what we have now?"

**Short answer.** Build a WebSocket "head is now N" poke on the existing `UserLog` Durable Object, using the Hibernation
API, and keep `/v1/sync` exactly as it is. A change made on one device would reach the other devices that are online in
about 1–2 s. Today it takes 0–30 s with a window open and 0–60 s without one. For this account the cost stays at the
$5 Workers Paid minimum: today's polling already fits inside the included quotas, and push lowers request volume about
3×. The Mac gains the most. The iPhone gains only while the app is in front. Background delivery on iOS would need
APNs, which needs the paid Apple Developer Program. SSE and long-polling keep the object awake and cost far more at
scale for no extra benefit.

`SPEC.md` §5 "Realtime" already names this as the way forward if realtime is ever wanted ("the socket only needs to
send 'head is now N'"). This document works that out in detail.

---

## 1. Today

### Server

- One Worker (`server/src/index.ts`) with a single route, `POST /v1/sync`, a bearer token (`API_TOKEN`), and one RPC
  to the `UserLog` DO (`idFromName("me")`). There's one DO for the one user, not one per user yet.
- `UserLog.sync()` (`server/src/log.ts`) is synchronous: it checks the log, appends (dedup and the hash chain in one
  `transactionSync`), and returns a page of up to 1,000 entries. Push and pull are the same call.
- The DO has no timers, alarms or sockets, so it can hibernate as soon as a request ends. It's billed only for the
  milliseconds each request runs.

### Clients and their triggers

| Client | When it syncs | Latency for a change made elsewhere |
|---|---|---|
| **Mac app** (`AppModel.startTriggers`, `SyncSchedule`) | at launch and on becoming active; ~1 s after a local edit (`Store.perform` → `requestSync(after: 1 s)`); every 30 s with a window visible; every 60 s with none (Settings ▸ "Sync with no window open", on by default); ⌘R; the CLI's Darwin nudge (0.5 s debounce, 5 s cap) | 0–30 s with a window (15 s on average), 0–60 s without one. A CLI command on the **same** Mac shows in ~0.5 s through the nudge. |
| **Mac widgets** | the feed is written 1 s after a change, at most once per 20 s with a window and once per 2 min without (`WidgetFeedPace`) | sync latency plus up to 2 min while windowless |
| **iPhone app** (`ios/Tasks/Model/Sync.swift`) | on open and on coming to the front (`cameToFront`); ~1 s after a local edit; every 30 s while in front; pull to refresh | 0–30 s while in front; while closed, only on open or on a background refresh |
| **iPhone background** (`BackgroundRefresh`) | `BGAppRefreshTask`, earliest 15 min after the last, but iOS chooses the time (usually hours apart; never after a swipe-away, in Low Power Mode, or with Background App Refresh off) | hours |
| **CLI** (`TasksCLI`) | each command: a pull before commands that need fresh state, a push of its ops; afterwards it posts the Darwin nudge | always fresh, since it pulls on every command |
| **Remote MCP** (`remote/`, Replica DO) | each `tasks_run`: pull, run, push through the `SYNC` service binding to the same Worker; the alarm retries queued ops | always fresh on each run. Its writes reach the Macs only at their next tick: there's no nudge across machines. |

### Request volume (estimate for this account)

The assumptions: each Mac is awake 14 h a day, 6 h with a window and 8 h without; the iPhone is in front about 1 h a
day; 50 CLI commands and 20 MCP runs a day.

| Source | Syncs/day |
|---|---|
| Mac ×2 (720 window ticks + 480 windowless ticks + ~30 edits, each) | ~2,460 |
| iPhone (120 ticks in front, ~20 opens, ~10 background refreshes) | ~150 |
| CLI (pull + push) | ~100 |
| MCP (pull + push) | ~40 |
| **Total** | **~2,750/day ≈ 83k/month** |

Each sync is one Worker request and one DO request. If both Macs kept a window open 24 h a day, the total would be about
175k/month. Either way it's under 20% of the 1M DO requests included each month. Almost all of these syncs return
nothing new.

---

## 2. Options

Pricing and limits were read on 2026-11-08 from the pages listed under Sources. The relevant Workers Paid figures:

- **DO requests:** 1M/month included, then $0.15/million. A WebSocket connection costs one request to open. Incoming
  messages are billed at 20:1. **Outgoing messages are free, and so are incoming protocol pings.**
- **DO duration:** 400,000 GB-s/month included, then $12.50/million GB-s, billed on 128 MB per object. Objects that are
  idle and eligible to hibernate aren't billed for duration, even before they're actually hibernated. A socket accepted
  with `ws.accept()` (rather than `ctx.acceptWebSocket()`) is billed for the whole time it's connected.
- **Hibernation:** an object can hibernate after about 10 s with no events, no timers, no pending I/O and no
  non-hibernatable socket. "Hibernated WebSocket connections stay connected." The runtime answers protocol pings
  "without interrupting hibernation". The limit is 32,768 hibernatable sockets per object.
- **Workers:** 10M requests/month included, then $0.30/million. A WebSocket upgrade counts as one request. "WebSocket
  messages routed through a Worker do not count as requests." Duration isn't billed, only CPU (30M ms included).
- **Deploys:** a forced code update disconnects the WebSockets on the running instance.

| | **WebSocket + Hibernation** | **SSE** | **Long-polling** | **APNs** |
|---|---|---|---|---|
| Latency for online clients | ~1–2 s end to end (mostly the writer's 1 s edit debounce) | same | same, plus a gap at each re-poll | 1 s to minutes; silent pushes are throttled by iOS |
| How it works | the client holds a socket to the DO; the DO sends `{"head":N}` after each append | the DO streams events into a held response | the client's request waits in the DO until head > cursor or ~60 s | the server signs a JWT (ES256 `.p8` key) and POSTs over HTTP/2 to `api.push.apple.com` per device token |
| DO duration | **≈ 0**: hibernated between appends | **whole time a client is connected**: an open response stream keeps the object active | whole time a request waits: always, while a client is listening | none |
| Other cost | 1 request per connect | 1 request per connect, plus reconnects | 1 request per client per ~60 s | $99/year Apple Developer Program; subrequests from the Worker aren't billed |
| 1 user | $0 extra | $0 extra, but ~324k GB-s/month (81% of the included amount) for an object awake 24 h | $0 extra, but the same duration plus ~170k requests/month | $99/year |
| 1k users | ~$15/month in total (§4) | ~$4,050/month in duration alone | ~$4,050/month duration + ~$75 in requests | $99/year + negligible |
| Mac battery and wakeups | one idle TCP connection with a protocol ping every 30 s; no TLS handshake, HTTP request, JSON decode or Store pass per tick. The fallback poll drops to every 5–10 min. | same as a socket | a request every ~60 s, about as now | n/a: the Mac keeps a socket |
| iPhone | only while in front: iOS suspends the app seconds after it goes to the background and the socket dies | same | same | **the only way** to wake the app in the background for new data. Silent pushes are low priority, and Apple advises at most two or three an hour. |
| Client support | `URLSessionWebSocketTask` (Foundation; macOS 10.15+, iOS 13+), with an `Authorization` header on the `URLRequest`, and `sendPing` | no `EventSource` on Apple platforms; a hand-written `URLSession.bytes` line parser | plain `URLSession` | `registerForRemoteNotifications`, the `aps-environment` entitlement, and a device-token upload route |
| Complexity | small: ~60 server lines, a ~250-line `SyncSocket` in TasksCore, wiring in each app | similar on the server, more on the client, and it costs more | simplest client, but a hot DO and many requests | most: Apple account, key handling, a token table on the server, push sends, and iOS background handling |

**SSE has no advantage here.** It's one-way, which is all a poke needs, but so is a socket used one way. The deciding
factor is that only WebSockets hibernate in a Durable Object: an open response stream counts as a request in flight, and
"DOs remain active while a request, RPC call, response stream, WebSocket, or pending I/O is in flight" (limits page).
Moving the stream into the Worker doesn't help either: the Worker would have to hold an RPC or stream from the DO to
learn about appends, and that keeps the DO awake.

**APNs is a separate decision.** It's the only option that changes the iPhone's background behaviour, and so the iPhone
widgets'. It needs the paid program: the free Personal Team can't use the Push Notifications capability (the Apple
Developer Forums threads under Sources; I couldn't read Apple's capability table directly because it needs
JavaScript). It's possible from a Worker: there's a community Workers APNs client, `@fivesheepco/cloudflare-apns2`, that
uses token auth over HTTP/2. I haven't tested it. It can be added later on top of the WebSocket design, since it sends
the same "head moved" signal by another route.

---

## 3. The recommended design

### Server (`server/`)

1. **A route:** `GET /v1/events` with `Upgrade: websocket` and `Authorization: Bearer <token>`. The Worker applies the
   same check order as `/v1/sync`: 404 for an unknown path, 426 without `Upgrade: websocket`, 401 for a bad token
   (the existing constant-time `authorized`). Then it forwards the request to the DO with `stub.fetch(request)`. A
   WebSocket upgrade goes through `fetch`, not the RPC. This makes it the server's second route, against the "one
   endpoint" stance in `SPEC.md` §5; the poke carries no data and the protocol is unchanged, so I think it's justified.
2. **`UserLog.fetch()`:** creates a `WebSocketPair`, calls `this.ctx.acceptWebSocket(server)` (the hibernatable
   form, never `server.accept()`), sends `{"head":<head>}` at once, and returns `101` with the client end. Sending the
   head on connect means a client that missed pokes while it was disconnected catches up at once.
3. **Broadcast on append:** at the end of `sync()`, if `append` moved `head`, it sends `{"head":<head>}` to every
   socket in `this.ctx.getWebSockets()`, catching errors from sockets that are closing. `ws.send` is synchronous, so
   `sync()` still never awaits and the "requests can't interleave" invariant holds. A pull or a push of only
   duplicates sends nothing. All writers go through `sync()`: the apps, the CLI, and the remote MCP through its `SYNC`
   service binding into the same Worker. So all of them broadcast with no change to `remote/`.
4. **Handlers:** `webSocketMessage` ignores what clients send (they send nothing; pings are handled by the runtime and
   never reach it). `webSocketClose` needs nothing: the compatibility date `2026-08-15` is past `2026-04-07`, so the
   runtime answers the close frame itself. `webSocketError` does nothing.
5. **Unchanged:** the format, `/v1/sync`, and storage. The constructor runs again on each wake from hibernation and
   re-reads `head` and the last hash through the primary key (O(log n)), as it does now on a cold start.

The writer gets its own poke too. It's harmless: the client handles a poke only once any sync in flight has ended, and
ignores it when `head ≤ cursor`. Tagging the writer's socket to skip it would need a client id on `/v1/sync`, which
isn't worth it.

Rotating the token means redeploying, which disconnects every socket, and each client then re-authenticates on
reconnect. A socket authenticated with the old token never outlives the deploy.

### Clients (TasksCore, shared by the Mac and the iPhone)

A `SyncSocket` in TasksCore owns one `URLSessionWebSocketTask` for the configured server and token, plus a pure
`SocketPolicy` (tested like `SyncSchedule`, with no timers) that decides when to connect, back off and give up.

- **On a poke** `{"head":N}`: if `N > store.cursor` once any sync in flight has ended, `store.requestSync()` through
  the same debounce the Darwin nudge uses (`SyncNudge.Debounce`, 0.5 s quiet and a 5 s cap), so a burst of CLI commands
  costs each client one pull. The changes still come through `/v1/sync`.
- **Connecting:** when sync is configured and the policy says to hold the socket (below). After `401` on the upgrade,
  the socket stops, as `checkToken` does, and restarts when the token changes. After `404` or `426` (an old server),
  it retries once an hour and the client keeps today's polling.
- **Reconnecting:** backoff from 1 s, doubling to a 5 min cap, with ±20% jitter so that a deploy doesn't bring every
  client back at the same moment. The backoff resets once a connection has lasted 60 s.
- **Liveness:** `sendPing` every 30 s. No pong within 10 s means a reconnect. Protocol pings are free and don't wake the
  DO. They also keep the connection under any idle timeout on Cloudflare's edge. Third-party sources cite 100 s, and
  Cloudflare's docs say an idle WebSocket is closed without giving a number (see the open questions).
- **Network changes:** an `NWPathMonitor` path becoming satisfied, or changing interface, reconnects at once and
  skips the backoff.
- **Fallback polling:** with the socket connected, the periodic sync runs every **5 min with a window and 10 min
  without** (the Mac), and every 5 min in front (the iPhone). It's a safety net against a half-open socket or a lost
  poke. With the socket down, the periodic sync goes back to today's 30 s / 60 s. `SyncSchedule.tickSyncs` takes one
  more input, `socketConnected`.

**Mac:**
- Hold the socket while the app runs, with or without a window, following Settings ▸ "Sync with no window open". When
  that's off and no window is visible, close the socket, since no periodic sync would run either.
- Sleep and wake: close on `NSWorkspace.willSleepNotification`. On `didWakeNotification`, reconnect and sync at once.
  A socket that lived through sleep is usually dead without knowing it.
- Keep the CLI's Darwin nudge. It's local, it's instant, and it works when the socket is down. With the socket up, the
  nudge and the poke land in the same debounce and give one sync.
- Desktop widgets: the windowless feed gap (2 min, for WidgetKit's reload budget) now dominates their latency. Push
  makes the data fresh within ~2 s; the widgets still redraw at most every 2 min while windowless. Shortening that gap
  is a separate decision about the reload budget, not part of this one.

**iPhone:**
- Open the socket on `.active` (`cameToFront`). On `.background`, close it with `cancel(with: .goingAway)`, next to
  the existing `persistNow`.
- `BGAppRefreshTask` stays as it is and never opens a socket: it has about 30 s and does one sync.
- iPhone widgets don't change: they refresh when the app is open or after a background refresh. Only APNs would
  change that.

### Old clients and old servers

- **Old clients on a new server:** nothing changes for them. They never call `/v1/events` and keep polling at 30 s and
  60 s.
- **New clients on an old server:** the upgrade gets `404`, so the client polls at today's cadence and tries the socket
  again once an hour. That allows deploying in any order.
- The two Macs and the iPhone can be updated at different times, and each one gains on its own.

### Testing

- **Server** (vitest in workerd, `server/test/`): upgrade without `Upgrade` → 426; a bad token → 401; the first message
  is the current head; a push with new ops pokes every connected socket with the new head; a pull, or a push of only
  duplicates, pokes nothing; a socket that closed doesn't break `sync()`. Check that the pool supports opening a
  WebSocket to a DO in tests. It's supported upstream, but whether this harness can force hibernation is an open
  question.
- **Remote MCP** (`remote/test/workers/`): a `tasks_run` that pushes produces a poke on a socket connected to the
  `SYNC` server.
- **TasksCore:** `SocketPolicy` as pure cases (the backoff sequence with jitter bounds, the reset after 60 s, 401 stops,
  404 waits an hour, the fallback interval for each state); poke handling (`head ≤ cursor` → no sync; a poke during a
  sync → one check afterwards); `SyncSchedule` with `socketConnected`.
- **End to end** against a local `wrangler dev` (no Cloudflare resources): a Debug Mac app and a CLI with a different
  data folder. Measure the time from a CLI write to the app's `state syncing` in the `-debugNudgeLog` log, with the
  Darwin nudge disabled for that run. The target is under 2 s. Then kill and restart `wrangler dev` to check the
  reconnect, and toggle Wi-Fi.
- **By hand on the devices:** Mac sleep and wake, a deploy with the apps running (all of them reconnect within the
  backoff), the iPhone going to the background and coming back.

---

## 4. Cost estimate

### This account (2 Macs, 1 iPhone, the CLI, the MCP)

| | Polling now | With the WebSocket poke |
|---|---|---|
| Syncs/day | ~2,750 | ~860 (fallback ticks ~240, pokes ~200, reconnects + their syncs ~150, iPhone ~70, CLI 100, MCP 40, local edits ~60) |
| DO requests/month | ~83k (8% of the included 1M) | ~26k + ~4k connects |
| DO duration | a few ms per request | the same: hibernated between requests, and the poke is sent inside a request that's already running |
| Monthly bill | **$5** (the minimum) | **$5** |

For one user, the benefit is latency, not cost.

### A heavier future: 1k users with the same profile

This assumes one DO per user, as `SPEC.md` §7 plans. Today there's a single DO and a single token, so multi-user needs
auth work first, whichever sync option is chosen.

| | Polling | WebSocket + Hibernation | Non-hibernating socket, SSE or long-poll |
|---|---|---|---|
| DO requests | 83M → $12.30 | 30M → $4.35 | similar to polling, plus long-poll's ~170M → ~$26 |
| Worker requests | 83M → $21.90 | 30M → $6.00 | |
| DO duration | ~52k GB-s (inside the 400k included) → $0 | ≈ $0 | ~324M GB-s → **~$4,045** |
| Worker CPU | ~$1 | ~$0 | |
| **Monthly bill** | **~$40** | **~$15** | **~$4,000+** |
| Concurrent sockets | – | ~3k in total, ~3 per object (the limit is 32,768 per object) | |

---

## 5. Risks and open questions

1. **Edge idle timeout.** I didn't find the number in Cloudflare's docs. Third-party sources say 100 s with no data
   either way. A 30 s protocol ping makes it moot, as long as the ping really reaches the edge as traffic, which it
   should, being a real frame.
2. **Pings while a windowless Mac is napped.** App Nap coalesces timers, so a ping could slip past an idle timeout
   and cause a reconnect now and then. That's cheap (1 request) but worth measuring. Not worth a
   `beginActivity` assertion at the start.
3. **Broadcasting from inside the RPC** to sockets that were hibernated: the docs say hibernated sockets "stay
   connected" and `getWebSockets()` returns them after a wake. I'm inferring, not quoting, that `ws.send` works from an
   RPC method on such a socket. The first server test should prove it.
4. **Deploys disconnect every socket.** With backoff and jitter that's a small reconnect wave. It also means each
   deploy costs a request per client and one extra sync each. Fine.
5. **A half-open socket** (NAT timeout, a captive portal): the 10 s pong deadline and the 5–10 min fallback poll
   bound it.
6. **The second route** against the one-endpoint stance in `SPEC.md` §5. It's a decision for the user. The
   alternative is upgrading `POST /v1/sync` itself, but a WebSocket upgrade must be a `GET`, so it would be a separate
   method on the same path, which is less clear.
7. **iPhone background and widgets** stay as they are without APNs. Is that acceptable, or is the $99/year program
   wanted for that? If so, there's more design to do: the token route, key storage as a Worker secret, the silent-push
   budget, and `@fivesheepco/cloudflare-apns2` or a small hand-written HTTP/2 client.
8. **The Mac's desktop widgets** redraw at most every 2 min while windowless (`WidgetFeedPace`). Push won't make them
   faster unless that gap changes, which costs WidgetKit reload budget.
9. **Should the Mac's windowless socket follow the existing setting**, or get a setting of its own? I recommend
   following "Sync with no window open", so there's no new setting.

## Sources (read 2026-11-08)

- Durable Objects pricing (page updated 2026-10-18): https://developers.cloudflare.com/durable-objects/platform/pricing/
- Durable Objects WebSockets best practices (2026-10-30): https://developers.cloudflare.com/durable-objects/best-practices/websockets/
- Durable Objects lifecycle (2026-10-30): https://developers.cloudflare.com/durable-objects/concepts/durable-object-lifecycle/
- Durable Object State API (2026-09-30): https://developers.cloudflare.com/durable-objects/api/state/
- Durable Object Base API (2026-06-15): https://developers.cloudflare.com/durable-objects/api/base/
- Durable Objects limits (2026-11-07): https://developers.cloudflare.com/durable-objects/platform/limits/
- Workers pricing (2026-10-02): https://developers.cloudflare.com/workers/platform/pricing/
- Workers WebSockets (2026-10-12): https://developers.cloudflare.com/workers/runtime-apis/websockets/
- The edge idle timeout (third-party): https://websocket.org/guides/infrastructure/cloudflare/
- Push on a free Personal Team: https://developer.apple.com/forums/thread/768748,
  https://takazudo-zudo-tauri.pages.dev/pj/zudo-tauri/docs/mobile/ios-signing-free-team
- APNs from Workers: https://npmjs.com/package/@fivesheepco/cloudflare-apns2
- Apple's limit of two or three silent pushes an hour is from "Pushing background updates to your App" and is quoted
  from memory: Apple's pages didn't render for fetching.

# Push sync's connection: in Settings and in the sync indicator

Status: **decided, 2026-11-08; built** (coord tasks-ios-sc T53). The user, on §4: "all the recommended are good for sync
indicator", so every decision below is its recommendation: A (a row of its own), C (the bolt cloud under the pointer),
green, hidden until sync is set up, Sync Now reconnects, "Last one 2 min ago" kept, the iPhone's B, "Live updates".
The words and states are TasksCore's `LiveStatus` (tested in `LiveStatusTests`); the Mac's §26 is updated. What the
build found for §5 is at its end. (Proposed T49; design only until then.) The user's words: "it
would be cool to have in the settings, an indication of the websocket connection. maybe also in the sync indicator or
something. idk, use claude design."

Mock-ups (a private Claude Design canvas, five boards, Mac and iPhone, dark and light):
https://claude.ai/artifact/Syjoj1cU99t7YfsVF9D1qL

- **Mac · Settings ▸ Sync · A** (recommended): the new row in place, then every state.
- **Mac · Settings ▸ Sync · B**: the same news folded into the Status row.
- **iPhone · Settings ▸ Sync**: the new row in place, dark and light, then every state.
- **Mac · Sync indicator (§26)**: options A–E, with push live and push down, at rest and under the pointer.
- **iPhone · the home screen's sync line**: options A–C.

It builds on design/PUSH-SYNC.md (the socket), INTERACTIONS-v2 §26 (the Mac's sync indicator), `SyncSocket` and
`SocketPolicy` in TasksCore, and both apps' `SettingsView`. The colours are the app's one theme (Rex with the Ember
accent, `TasksTheme.Theme.rex`), and the type is Pane's on the Mac and `Typo` on the iPhone.

**Short version.** Settings ▸ Sync gets one more row, **Live updates**, on both devices. It shows a dot and a word on
the right ("Live", "Connecting…", "Reconnecting in 8 s", "Offline", "Not available", "Token rejected", "Off") and a
detail line under the title. The Mac's sync indicator stays empty at rest. Under the pointer it shows a cloud with a
small bolt while push is live and the plain cloud while it isn't, and the tooltip gets a second line. The iPhone's home
sync line uses the same bolt cloud while live. Its words don't change.

---

## 1. The states, and what the socket has to say

Push being down never loses data: the periodic sync goes back to 30 s with a window and 60 s without (§3 of PUSH-SYNC).
So nothing here is an error except a rejected token, and that one already shows as the indicator's bad-token state.

| State | When | `SyncSocket` today |
|---|---|---|
| **Live** | the server's first message arrived | `.connected` |
| **Connecting** | the first try, after a wake, a network change, coming to the front | `.connecting` |
| **Reconnecting** | a drop; waiting out the backoff (1 s doubling to 5 min, ±20%) | `.waiting(seconds)` after `.dropped` |
| **Offline** | no network path | not distinct: `.waiting`/`.connecting` while `NWPathMonitor` says unsatisfied |
| **Not available** | an old server: 404, 405 or 426 on the upgrade; retried hourly | `.waiting(~3600)`, indistinguishable from a long backoff |
| **Token rejected** | 401 on the upgrade, until the token changes | `.stopped` |
| **Off** | Mac: Sync with no window open off and no window. iPhone: in the background. Or sync isn't set up | `.off` |

So the socket needs to publish a little more (TasksCore, no protocol change):

- **Why it's waiting**: `.waiting(until: Date, why: SocketPolicy.Close)`, so an old server's hourly retry reads as
  "Not available" and not as "Reconnecting in 58 min". A `Date` rather than seconds, so the countdown is live.
- **Offline**: the path monitor's `satisfied` as a published property (it already has it in `PathSummary`).
- **Since when**: when the current connection opened and when the last drop happened ("Lost the connection at 9:38").
- **The last change heard**: when a poke last moved the head, not counting the first message on connect. Your own
  edits poke too, which is right: it's "the last time the server's data changed", heard live.
- On the iPhone, the socket (wiring in progress) has to be reachable from Settings and the home line, as `store` is.

---

## 2. Settings ▸ Sync

### Options

- **A · A Live updates row (recommended).** A row of its own: the title "Live updates", the detail line under it, and on
  the right a dot and a word, like macOS's own Settings shows a network's status. On the Mac it's last in the Sync
  card, under Status. On the iPhone it sits between Status and Background refresh, so the card reads: how sync is
  doing, how it hears about changes in front, and how it does in the background.
- **B · Folded into Status.** No new row. Status's detail gains a second line with a small dot ("Live updates: changes
  arrive within seconds."). It's smaller, but two kinds of news share one row, and the longer states wrap at 600pt.

### The row (A)

| State | Dot (7pt Mac, 8pt iPhone) | Word | Detail |
|---|---|---|---|
| Live | filled, `list-green` (#3FB950 / #116329) | Live | Changes from your other devices arrive within seconds. Last one 2 min ago. (iPhone: "…within seconds while Tasks is open.") |
| Connecting | ring, 1.5pt `ink-tertiary` | Connecting… | Checking every 30 s until it connects. |
| Reconnecting | ring, `ink-tertiary` | Reconnecting in 8 s (Mac); Reconnecting (iPhone) | Lost the connection at 9:38. Checking every 30 s meanwhile. (iPhone puts "Trying again in 8 s" here, as the word has less room.) |
| Offline | filled, `ink-quiet` | Offline | No network. Reconnects as soon as it's back. |
| Not available | filled, `ink-quiet` | Not available | This server doesn't have them yet. Checking every 30 s; trying again at 10:41. |
| Token rejected | filled, `attention` (#D29922 / #9A6700) | Token rejected (iPhone: Rejected), in `attention` | The server didn't accept the token. Save it again above. |
| Off (Mac) | ring, `ink-quiet` | Off | Only while a window is open. Turn on Sync with no window open to keep them. |
| Off (iPhone) | ring, `ink-quiet` | Off | Only while Tasks is open. In the background, Background refresh takes over. |

- **"Every 30 s"** is the current pace: 30 s with a window or in front, "every minute" on a windowless Mac.
- **Live with Sync with no window open off** (Mac): the detail reads "…within seconds, until you close the last
  window." instead of the last-change time.
- **Type and colour:** the Mac uses Pane's row (13pt `ink` title, 11pt `ink-secondary` detail); the word is 13pt
  `ink-secondary`. The iPhone uses its Settings rows (`Typo.body` 15pt title, `Typo.meta` 12pt `ink-secondary` detail);
  the word is 15pt `ink-secondary`. The dot is the only colour except for the rejected token. Green is new to the app's
  chrome. It's the list-green token, used only here. I think that's acceptable in Settings, where macOS itself uses a
  green dot for "connected" (decision 3).
- **The countdown** ticks once a second while Settings is open. No other state animates. No pulse on Connecting.
- **When sync isn't set up**, or on the iPhone's sample data, the row is hidden: Status already says "Off. Set the
  server URL and token." (decision 4).
- **The iPhone's Off state is never seen live.** Settings only shows in front, and coming back reads "Connecting…" for
  a moment. Its words are for VoiceOver's value and for completeness.
- **VoiceOver:** one element, "Live updates, Live. Changes from your other devices arrive within seconds."
  The state changes aren't announced.
- **Sync Now** (and ⌘R, and pull to refresh) also reconnects the socket at once (`reconnectNow`), skipping the backoff
  or an old server's hourly wait (decision 5).

---

## 3. The sync indicator

### The Mac (§26): options

Each is drawn on the canvas with push live and push down, at rest and under the pointer. Offline, stopped and the bad
token keep §26's glyphs in every option. The title band still shows only offline and stopped. Push being down never
shows there.

| Option | At rest | Under the pointer | What it changes in §26 |
|---|---|---|---|
| **A · Settings only** | nothing | the cloud; "Synced 2 min ago ⌘R" | nothing |
| **B · A tooltip line** | nothing | the cloud; a second tooltip line: "Live" or "Checking every 30 s" | the Synced row's tooltip; the tooltip rule (Synced gets a second line too); VoiceOver's value |
| **C · A live cloud on hover** (recommended) | nothing | `bolt.horizontal.icloud` while live, `icloud` while not; B's tooltip line | B's changes; the Synced row's hover glyph; a timing row: "not live" only after 5 s down (as offline), so a reconnect doesn't flip it; the 150 ms glyph crossfade covers the swap |
| **D · The cloud at rest while push is down** | live: nothing; down for a minute: `icloud` in `ink-quiet` | as B | breaks "Synced shows nothing at rest"; a new Polling state with its timing; old servers and windowless-off must be left out, or it shows all day |
| **E · A ring at rest while push is down** | a 5pt hollow ring where the cloud sits | as B | D's changes, plus a second mark next to the 4pt accent dot that already means "changes waiting" |

**Recommended: C.** Push being down costs only speed. Sync still runs every 30 s, so it isn't news at rest. That keeps
§26's rule that a healthy app shows nothing. A person who wonders gets the answer one hover away, in the glyph itself
as well as the words, and the bolt cloud is an SF Symbol, so it costs no drawing. D and E put a mark in view for
something nobody needs to act on, and an old server would show it every day.

### The iPhone: its equivalent

The iPhone has no §26 cloud. Its equivalent is the home screen's **sync line** (`SyncLine` in `HomeView.swift`, fed by
`AppModel.syncSummary`): a 12pt `icloud` and words in `ink-tertiary`, always visible under the views.

| Option | Live | Push down | Notes |
|---|---|---|---|
| **A · No change** | `icloud` "Synced 2 min ago" | the same | Settings is the one place |
| **B · The live cloud** (recommended) | `bolt.horizontal.icloud` "Synced 2 min ago" | `icloud` "Synced 2 min ago" | the words don't change; VoiceOver: "Sync: Synced 2 minutes ago. Live." Matches the Mac's C |
| **C · "Live" in words** | "Synced 2 min ago · Live" | "Synced 2 min ago" | plainest, but a word that's there all day, and it widens the long states |

**Recommended: B**, with the same 5 s rule as the Mac so that coming to the front doesn't flash the plain cloud: the
glyph shows the bolt only once connected, and the plain cloud only once push has been down for 5 s. Until then it
keeps whatever it showed last, and on launch that's the plain cloud. The other states (syncing, can't reach,
stopped, waiting) keep `icloud`, since the line's words already say what's wrong.

---

## 4. Decisions for the user

1. **Settings:** A (its own row) or B (folded into Status)? Recommended: **A**.
2. **The Mac's indicator:** A, B, C, D or E? Recommended: **C** (the bolt cloud and a tooltip line, only under the
   pointer).
3. **Green for Live** in Settings, or keep it grey like the rest of the chrome (a filled `ink-secondary` dot)?
   Recommended: **green**. It's only in Settings, and it reads like macOS's own.
4. **Hide the row while sync isn't set up**, or show it as "Off"? Recommended: **hide**.
5. **Sync Now also reconnects** the socket at once? Recommended: **yes**. It's the one thing a person can do when it
   says "Reconnecting in 4 min".
6. **The last-change time** ("Last one 2 min ago") in the Live detail, or just "Live"? Recommended: **keep it**. It's
   the one way to see that pokes are arriving.
7. **The iPhone's home line:** A, B or C? Recommended: **B** (the bolt cloud).
8. **The word:** "Live updates" / "Live", or another ("Push", "Instant sync")? Recommended: **"Live updates"**. "Push"
   sounds like notifications, which this isn't.

## 5. Open questions

- **Does the Mac's Settings window count as a window?** `AppModel.hasVisibleWindow` counts any visible window that
  `canBecomeMain`, and SwiftUI's Settings window may qualify. If it does, the Mac's "Off" state can't be seen from
  Settings: opening Settings holds the socket. Then "Off" is only VoiceOver's, and Live's "until you close the last
  window" detail carries the message. Check it when building.
- **`bolt.horizontal.icloud`**: as far as I know it's been in SF Symbols since the first release (macOS 11, iOS 13).
  Check that it reads at 14pt (Mac) and 12pt medium (iPhone) next to `icloud`. If the bolt is lost at that size, use
  `bolt.horizontal.icloud.fill` or `icloud` with a 1pt-larger weight.
- **Windowless Mac with the toggle on**: the socket holds with no window. Nothing in this design shows then except the
  Settings row, which is right.

What the build found (T53):

- **Settings counts as a window.** SwiftUI's Settings window is an `AppKitWindow` with `canBecomeMain` true, so
  `hasVisibleWindow` is true while it's open, even with every main window ordered out (checked with the Debug app's
  `-debugScript "settings;hidemain;windows:…"`). Opening Settings holds the socket and the 30 s pace. So the Mac's Off
  is only VoiceOver's (and a sleep's moment), and Live's "until you close the last window" carries the message, as
  above. `hasVisibleWindow` is unchanged: leaving Settings out would change when the widgets' feed is written too.
- **The bolt reads** at 14pt regular and 12pt medium, at 2x and 3x, in both appearances' `ink-quiet` and
  `ink-tertiary`: the outline `bolt.horizontal.icloud` stays, no `.fill`.
- **A failed first try** (the socket never opened since the last start, so nothing was "lost"): Reconnecting's detail
  reads "Couldn't connect. Checking every 30 s meanwhile."
- **Times** are the system's short time ("9:38 AM" in English), so an old server's detail can wrap to two lines at
  600pt; the row lets it. A wait past midnight reads "tomorrow at 12:20 AM".

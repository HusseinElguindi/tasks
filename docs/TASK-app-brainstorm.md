# Brainstorm: another app

The user, in their words: "can we start thinking about making an app". They'll talk it through with you directly in
this tab.

**First, ask what they mean.** It's most likely an **iPhone (and maybe iPad) app** for Tasks: they use an iPhone 15,
and so far everything is macOS. But confirm it before going deep. It could also be a web app, a watch app or
widgets.

**This is a conversation first.** Don't write code. Bring ideas and tradeoffs, ask questions, and push back where
something would cost a lot. When a direction settles, write it up in `docs/` (for example `docs/IOS-PLAN.md`) and
commit it by path.

## What exists (read before proposing)
- `docs/SPEC.md`: the sync server and the append-only op log (`POST /v1/sync`), the hash chain, and one token.
  `server/` is a Cloudflare Worker with a SQLite DO.
- **TasksCore** (`app/TasksCore`): a Swift package with the reducer, projection, ordering, dates, Today, Markdown,
  sync client and persistence. The Mac app's UI is AppKit inside SwiftUI (`app/Tasks/`), so it isn't portable as
  is. Check what in TasksCore is macOS-only: the Phase 0 Wasm spike found `notify`, `UndoManager` and Dispatch,
  most of which do exist on iOS.
- `design/INTERACTIONS-v2.md` (the Mac UI spec), `design/COLOR.md` (A + B + D: the Ember accent and lit tiles),
  `design/MARKDOWN.md`, and `design/THEMES.md`.
- **Design is very important to the user.** Rex (their terminal app) is the design source of truth, and the Pane
  design system is the vocabulary. An iPhone app needs its own design pass, not a squeezed Mac layout.
- `docs/SDK-PLAN.md` and `remote/` (the `tasks-mcp` Worker): context on agents and the remote MCP.

## Questions worth raising
- **Scope:** full parity, or a focused companion (Today, quick add, complete, dates)?
- **Sync:** the same token, pasted or scanned from the Mac? Background refresh? Push (APNs) versus polling? Offline
  queueing as the app does.
- **Sharing code:** TasksCore as is on iOS, and what needs `#if os(iOS)`. Note the user's sensitivity to changing
  existing code; ask before planning changes to TasksCore.
- **UI tech:** SwiftUI-first on iOS, and where it needs UIKit for performance (long lists, drag-reorder).
- **iPhone-only features:** widgets, Live Activities, Shortcuts and App Intents, Share sheet capture, Siri, the
  Action button, notifications for deadlines and When.
- **Distribution:** personal use through Xcode or TestFlight versus the App Store. Signing, which has already been
  painful on the Mac (see "Tasks Local Signing").
- **The order to build in,** and the first slice the user could hold in their hand soonest.

## Rules
- Per-path commits only (`git commit -m … -- <paths>`), ending with `Co-Authored-By: Claude Opus 5.5
  <noreply@anthropic.com>`. Never `git add -A`. Never push.
- Don't touch the installed app, its data, the live servers, or Rex.

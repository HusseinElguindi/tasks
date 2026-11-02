# Tasks app — brief (from the user)

Two parts:
1. **Server infra** on Cloudflare (Workers / Durable Objects / D1 as appropriate).
2. **SwiftUI app — macOS, and iOS (iPhone and iPad).** (Was macOS only; iOS added by the user on 2026-11-02.)

**Simplicity is key**, in both design and architecture.

## Sync
An append-only log. A sync is just: fetch from the client's last known index up to the current head.

## Model
A task has at least: `id`, `title`, `description`, `deadline`, `when` date.

## Screens
- **Today**: rolls up tasks whose `when` ≤ today OR `deadline` ≤ today.
- **Lists**: user-created groupings. Tasks are created inside a list, and can be moved between lists.

## Design
Design is very important. Use the **Pane** design system (it lives in Claude Design).
`design/PaneTheme.swift` is the SwiftUI side of Pane. Pane is based on the **Rex** app
(a terminal app, running on this machine).

## Rules
- Do NOT create or modify any Cloudflare resources (wrangler / cf CLI) without asking the user first.
- Outputs go in this repo under `docs/` (spec) and `design/` (design notes, links).

# Task: logo and app icon directions, in Claude Design

The user wants logo options for the app.

## Context

- **The product.** "Tasks" (a working name) is a simple, fast macOS-only task app for one person.
  - It has lists, a Today view (tasks whose when or deadline is today or earlier) and Markdown notes.
  - It syncs as an append-only log to a Cloudflare Worker. The log works like Git: a hash-chained history of ops, where undo is an inverse op.
  - Read `docs/BRIEF.md` and skim `docs/SPEC.md` §1–6.
- **The look.** It is built to feel like **Rex**, the terminal app on the user's Mac. Rex is the source of truth. The **Pane** design system, which is derived from Rex, is the vocabulary.
  - Pane in Claude Design: https://claude.ai/artifact/MS3VdrN9VHU7A7pTUTzpm8.
  - Tokens: `design/PaneTheme.swift`.
  - Measured Rex colours: `design/REX-REFERENCE.md`. Dark surfaces are `#181818` and `#1C1C1C`; selected capsules are `#444444`.
  - The style is quiet, dense and precise. It is dark first, uses capsule rows, and has small monogram tiles for lists, with colours derived from each list's id.
- **What the user has liked so far:**
  - the v2 interactions prototype (https://claude.ai/artifact/QetdV1H57SC6kLXtNzJRXM, source `design/prototype-v2/`), especially its animations and small details;
  - the detail pane sliding open beside the list.
- **What the user disliked:** the "Ledger" direction (a paper or accounting feel) was dropped.
- **What the user values:** simplicity in design and architecture, and performance.

## Output

- **A Claude Design canvas** with **5–7 distinct logo directions** for the macOS app icon, plus the mark on its own.
  - Ideas to consider, without being limited to them: the checkbox and capsule language; panes and splits; the Today sun; the append-only log or chain; a monogram.
  - Prefer bold, simple marks that hold up at 16pt.
- **For each direction, show:**
  - the macOS icon (the squircle grid, 1024 down to 16) in light and dark appearance, plus the tinted/clear style if it's cheap;
  - the bare mark;
  - the mark in context: the Dock, Finder, and the app's own sidebar header;
  - one line of rationale.
- **Recommend one or two directions.**
- **Originality:** don't imitate any existing app's icon (Things, Reminders, Todoist, OmniFocus and so on) or any brand.
- **Commit** source and notes under `design/logo/`: per path, never `git add -A`, never push. End commit messages with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Don't touch `app/`.
- **When the canvas is ready,** report its link and your recommendation to the coordinator, then stop so the user can review it. You may use subagents.

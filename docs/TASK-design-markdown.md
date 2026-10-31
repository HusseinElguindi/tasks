# Task: design Markdown notes in the detail pane

The user's words: "let's start a design for markdown in the task."

**This is design only.** Nothing goes into `app/` until the user approves.

## Context: don't start from scratch

- **The v2 prototype is the base.** Source in `design/prototype-v2/` (start with its `README.md`), published at https://claude.ai/artifact/QetdV1H57SC6kLXtNzJRXM.
  - The user loves its animations and details.
  - The detail pane is where notes live: title, then List, When and Deadline, a divider, then Notes, edited in place. Copy that code; don't redraw it.
- **The build spec** is `design/INTERACTIONS-v2.md`. Its detail-pane and notes sections describe what's built today.
- **The user's later changes** are in `docs/TASK-v2-feedback.md`. Item 6 is relevant: the detail fields start at the checkbox edge and span the full width.
- **The model** is in `docs/SPEC.md`. Notes are a Markdown string in the task's `notes` field (also §1 and §3). No schema change.
- **The look:** Rex is the source of truth (`design/REX-REFERENCE.md`), with Pane as the vocabulary (`design/PaneTheme.swift`). Don't drive Rex.
- **Screens of the shipped app,** which matches the prototype: `/private/tmp/claude-501/-Users-hus-code-tasks/25e6ce86-274b-4c19-953c-b1ac2f336050/scratchpad/item10/after-*.png`.
- **Another agent is working on the same prototype at the same time,** adding the Completed, Upcoming, Undated and Trash views. To avoid clashes:
  - Copy the prototype into `design/prototype-markdown/` and work only there.
  - Write your spec as `design/MARKDOWN.md`, not inside `INTERACTIONS-v2.md`.
  - The coordinator will merge it later.

## Design

1. **Editing and reading.** Choose between:
   - live inline styling (Markdown syntax that fades or hides away from the caret);
   - raw text while editing and rendered text otherwise;
   - something else.

   Whichever you pick has to feel quiet and native, and it can't fight the in-place editing the user likes.
2. **What to support,** kept simple: bold, italic, inline code, links, headings (probably only a couple of levels), lists, checklists, block quotes and code blocks. Say what's out.
   - Checklists inside a task's notes: whether clicking a box toggles it in the Markdown text, and how they look next to the task's own checkbox.
3. **Details:**
   - links: open on ⌘-click or a plain click, hover state, and pasting a URL;
   - keyboard: ⌘B, ⌘I, ⌘K, and Return continuing a list;
   - pasting rich text;
   - a light preview of the notes in the task row, or none;
   - very long notes and scrolling;
   - the placeholder;
   - typography, using the app's tokens: sizes and line height in the 13pt app;
   - dark and light.
4. **Performance:** the app has strict budgets (`docs/SPEC.md` §9). The approach must render cheaply in AppKit/TextKit; say how.

Where there's a real choice, put two or three variants side by side for the user to pick.

## Output

- **The canvas:** the clickable prototype in `design/prototype-markdown/`, published as a new canvas with boards in dark and light and the variant comparisons.
- **The spec:** `design/MARKDOWN.md`, with rules, tokens, interactions and the AppKit/TextKit approach, citing prototype lines.
- **Commits:** per path, never `git add -A`, never push. End commit messages with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Report:** the link, the choices and your recommendations to the coordinator, then stop.

You may use subagents.

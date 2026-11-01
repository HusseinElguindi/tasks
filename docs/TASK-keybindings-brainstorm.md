# Brainstorm: vim/tmux-style navigation keys

The user wants to talk this through with you directly in this tab. In their words: "i want to think about
keybindings. i am very familiar with tmux and vim bindings (for navigation, let's not change editing). let's
brainstorm."

**This is a conversation first.** Don't write app code. Have ideas, ask questions, and push back where something
would clash. When the user settles on a direction, write it up as a proposed section in `design/INTERACTIONS-v2.md`,
or a new `design/KEYS.md`, and commit it by path (see Rules).

## Context to read first
- `design/INTERACTIONS-v2.md` §17, Keyboard (complete). That's every binding today. Also §6 (adding), §12 (the
  sidebar, including holding ⌘ for ⌘1–⌘9), §22 (views) and §23 (headings, Space to collapse).
- `app/Tasks/Window/Menus.swift` and `app/Tasks/Window/WindowActions.swift`, for how keys are handled now.

## Scope
- **Navigation only:** moving between rows, panes (sidebar, list, detail), views and lists; jumping; selection;
  folding headings; search; opening and closing the detail pane.
- **Editing stays as it is:** text fields, notes and titles keep normal Mac editing. Typing in a field must never be
  hijacked.

## Things worth raising
- Vim motions such as `j`/`k`, `gg`/`G`, `h`/`l` across panes, `zo`/`zc`/`za` for folds, `/` to search, counts like
  `5j`, `dd`/`x` for completing or deleting (if that counts as navigation), `o`/`O` for new task below or above,
  `u` for undo, and `.` for repeat.
- tmux ideas: a prefix key (like `⌃b` or `⌃a`) for pane or list switching, `prefix + 1…9`, a list picker in the
  spirit of `prefix + w`, and pane focus or resize.
- **Conflicts:**
  - Type-select: typing a letter jumps to a matching row today (§12, §17).
  - Space completes a task (Space on a heading collapses it).
  - ⌘ shortcuts and the menus.
  - VoiceOver.
- Should it be a mode or a setting? Options: always on, opt-in "Vim keys" in Settings, or modal
  (normal/insert, like vim). And what shows the user which mode they're in?
- How they're discovered: menus, the shortcuts sheet, hints.
- Mac conventions to keep: arrows, ⌘↑/⌘↓, and Return to rename.

## Rules
- Per-path commits only (`git commit -m … -- <paths>`), ending with `Co-Authored-By: Claude Opus 5.5
  <noreply@anthropic.com>`. Never `git add -A`. Never push.
- Don't touch the installed app, its data, the live server, or Rex.

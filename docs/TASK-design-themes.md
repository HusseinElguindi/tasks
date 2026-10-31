# Task: themes — design what can be themed and how

The user's words: "Let's work on themes. I want to be able to apply themes. Figure out the tokens we can change, etc."

**This is design only.** Nothing goes into `app/` until the user approves.

## Start from the references

- **The tokens as they exist today:**
  - in the app: `app/Tasks/Theme/TK.swift` (and `Draw.swift`, which draws with them);
  - in the prototype: `design/prototype-v2/tasks-v2.css` and `markdown.css`;
  - the original vocabulary: `design/PaneTheme.swift`.
- **The look:** `design/REX-REFERENCE.md` holds the measured Rex colours. Rex is the source of truth, and its look is the default theme.
- **How the UI uses the tokens:** the prototype, `design/prototype-v2/` (start with its `README.md`), and the spec, `design/INTERACTIONS-v2.md`.
  - The app has Light, Dark and System appearances, plus Classic and Glass (§4 and `docs/TASK-v2-feedback.md` items 9–10).
  - List colours are derived from each list's id.
  - Today, the views, headings, the large title and Markdown notes all draw from these tokens.
- **Another agent is changing the prototype at the same time** (date indicators in `design/prototype-v2/`). Copy the prototype into `design/prototype-themes/` and work only there. Write your spec as `design/THEMES.md`. The coordinator will merge later.
- **What the user likes:** quiet, precise, Rex-like details; nothing clunky; simplicity.

## Design

1. **A token inventory.** List every colour, shadow, radius, font and opacity in use. Group them into semantic tokens:
   - surfaces, ink levels, lines and edges, fills (hover, selected, pressed);
   - accent, focus ring, danger, attention, success;
   - list colours, chips, checkboxes, Markdown, glass material;
   - shadows.

   Flag hard-coded values that bypass the tokens.
2. **What a theme may change.**
   - A small, safe set: for example, the surface colours, ink, accent, list palette, and maybe the corner radius and font.
   - What stays fixed for layout and quality: metrics, timings, the ink contrast floor.
   - How a theme relates to Light, Dark and System. Does a theme define both appearances, or is it one appearance?
   - How a theme relates to Glass.
   - Derived tokens, so a theme only needs a few base colours. For example, hover and selected fills come from the surface and ink.
   - A contrast check that rejects a theme that fails WCAG for body text and chips.
3. **A theme format.** Keep it simple: a small JSON or plist with the base tokens. Decide where it lives and whether it syncs. The recommended answer is local only, in Settings; say if you disagree.
4. **The picker.** Theme selection in Settings, with live previews. Perhaps a menu item. How switching animates (the item 9 bugs show that appearance switches have to update everything).
5. **Sample themes.**
   - **The default** is Rex itself.
   - **Five to seven others with distinct moods,** such as warm paper, high contrast, a muted dark, a cool blue and a vivid accent.
   - **Name them generically.** Don't copy existing branded themes or apps.

Where there's a real choice, show two or three variants side by side for the user to pick.

## Output

- **The canvas:** a clickable prototype in `design/prototype-themes/` with a working theme switcher, published as a new canvas. Show every sample theme across key screens (Today, a list with headings, the detail pane with notes, the date popover) in both appearances, plus the token inventory as a board.
- **The spec:** `design/THEMES.md`, covering the inventory, the themable set, derivation rules, the format, the picker, contrast rules, and how the app (`TK.swift`) would read a theme cheaply, with no per-frame cost.
- **Commits:** per path, never `git add -A`, never push. End commit messages with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Report:** the link, the choices and your recommendations to the coordinator, then stop.

You may use subagents.

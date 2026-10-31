# Tasks: Markdown notes (design spec)

Status: **draft for the user's picks, 2026-10-31.** Design only; nothing here is built. The brief is
`docs/TASK-design-markdown.md`.

**Canvas:** https://claude.ai/artifact/CmypwyraQx28AYcHSfb5c5 (private until shared from its Share menu). Press Play
on the top board, then click in the notes of "Review CS 489 lectures 10–14". The strip under it switches every choice
below; the boards under it show each variant side by side, in dark and light.

**Source:** `design/prototype-markdown/`, a copy of `design/prototype-v2/` with the notes replaced. This spec cites it
by line:

- `dc:N` is line N of `design/prototype-markdown/Main.dc.html`.
- `md:N` is line N of `design/prototype-markdown/markdown.css`, which holds every new value. `tasks-v2.css` is
  unchanged.

**What it replaces.** `design/INTERACTIONS-v2.md` §7 Notes (rendered inline Markdown at rest, a raw textarea while
editing) and the display line of `docs/SPEC.md` §2 ("`AttributedString(markdown:)` … headings and lists show as their
raw text"). It also does SPEC §11's "Block Markdown rendering". **The model doesn't change:** notes stay one Markdown
string in `notes`, ≤ 20,000 characters, last-writer-wins, committed once per editing session (SPEC §2, §5).

Everything else in the detail pane (title, List, When, Deadline, the separator, the footer, item 6's full-width
fields) is v2 as built.

---

## 1. Decisions to make

The user picks; the canvas has each one side by side. My recommendation is first.

| # | Choice | Options | Recommendation |
|---|---|---|---|
| 1 | Editing and reading | **A Live** · B Faint marks · C Raw while editing | **A.** One view that never switches. The marks of the word under the caret and of its line (`#`, `>`) fade in; everything else stays rendered. The first click lands exactly where it was aimed. |
| 2 | Checklist boxes | **Square, neutral** · Round, accent | **Square.** The round blue box stays the task's alone; a notes item is smaller, square, and fills gray when checked. |
| 3 | A hint in the row | **Glyph (or the checklist's count)** · Excerpt · None | **Glyph.** Quiet, keeps the row's one line, and "2/5" is worth knowing from the list. |
| 4 | Opening links | **Click** · ⌘-click | **Click.** NSTextView's default and v2's current spec. The cost (you can't click into a link to edit it) is covered by ⌘K and the arrow keys. |

One knock-on the user should confirm: **⌘K means Add Link while the notes have the caret** (§6). Everywhere else it
stays Complete.

### Why A over B and C

- **C (today's spec)** fights in-place editing. The rendered text and the source differ in length and shape (bullets,
  boxes, hidden `**`), so the switch reflows the paragraph under the pointer and the caret can't land where you
  clicked. Lists lose their boxes the moment you edit. Board row 1, third column.
- **B** never moves anything, and it's the cheapest to build (§9). But every `**`, `_`, `[`, `](url)` and `#` sits in
  the text forever, which reads busy in a 400pt pane and makes links twice as long. It's the fallback if A's reveal
  feels jumpy in the app.
- **A** reads as finished text at rest and while typing, and shows syntax only where you're working. The shift is one
  token wide (`retrieval` → `**retrieval**`) and the marks fade in over 100 ms (`md:26`).

---

## 2. Principles

1. **The text is the source.** The editor's string is the Markdown, character for character. Styling is attributes;
   hidden marks are still in the string. Saving is reading the string. Nothing converts on the way in or out.
2. **One view, edited in place.** No Edit/Preview switch, no font switch, no relayout on focus. Clicking the notes
   puts the caret where you clicked; that starts the editing session (`dc:2165`).
3. **Lines are the unit.** Every source line is one paragraph (SPEC §2 already keeps line breaks; a blank line is an
   empty line). A keystroke re-reads one line (`dc:518`).
4. **Quiet.** Syntax is ink-quaternary and regular weight. Bullets, numbers, boxes and quote bars sit in the
   checkbox's 16pt column, so list text lines up with the title's text at 26.
5. **Existing tokens only.** No new colors. The one derived value is the link underline at 40% of `accent-text`.

---

## 3. What's supported

| Markdown | Shows as | Marks (variant A) | Source |
|---|---|---|---|
| `**bold**`, `__bold__` | Semibold | `**` at the caret | `md:12`, `dc:566–569` |
| `_italic_`, `*italic*` | Italic | `_` at the caret | `md:13`, `dc:566–569` |
| `` `code` `` | 12/16 SF Mono on `fill-control`, padding 1 / 4, radius 4 | `` ` `` (mono) at the caret | `md:14`, `md:27` |
| `[text](url)` | `text` as a link | `[` and `](url)` at the caret | `md:16–18`, `dc:558–561` |
| A bare `https://…` | A link | none | `dc:562–564` |
| `# Heading` | 14/20 semibold, 6 above | `# ` while the caret is on the line | `md:32`, `md:34` |
| `## Heading` (and `###`–`######`) | 13/19 semibold, 4 above | `## ` on the caret's line | `md:33`, `md:35` |
| `- item`, `* item`, `+ item` | A 5pt dot in the gutter column; text at 26 | never (the dot is the mark) | `md:38–39` |
| `1. item`, `1) item` | The number, right-aligned to 18, tabular, `ink-secondary` | never | `md:41` |
| `- [ ] item`, `- [x] item` | A checklist box in the gutter (§5) | never | `md:45–62` |
| Two spaces before a list item | One level in (26pt), at most two levels; the second level's dot is a ring | never | `dc:2332`, `md:40` |
| `> quote` | `ink-secondary` at 26, a 2pt `fill-strong` bar in the gutter column | `> ` on the caret's line | `md:65–68` |
| ```` ``` ```` fenced block | 12/17 SF Mono on `fill-control`, radius 6, padding 6 / 10, full width, wrapping | the fence lines, while the caret is anywhere in the block | `md:71–75` |

**Ordered lists number themselves** from the first item's number, as CommonMark does: `1. 1. 1.` shows 1, 2, 3, so
inserting an item never rewrites the others (`dc:2336`). Return types the next number anyway, so the source reads
right elsewhere.

**Out** (shown as typed): tables, images and attachments, HTML, strikethrough (`~~`), horizontal rules, footnotes,
reference-style links, setext headings, nested quotes, heading levels past two, a third list level, emphasis nested
more than one deep. ⌘E (code) and ⇧⌘X (strikethrough) are out; ⌘E is the system's Use Selection for Find.

---

## 4. Showing the marks

| Variant | At rest | Editing |
|---|---|---|
| A Live (`md-reveal`) | Fully rendered | Rendered; the inline marks of every token the selection touches (its ends included), the `#` / `>` of each line it's on, and both fences of a code block it's in, in `ink-quaternary` | 
| B Faint (`md-faint`) | Every mark shown, `ink-quaternary` | The same |
| C Raw (`md-raw`) | Fully rendered | Every line plain 13/19 `ink`, exactly as typed |

List prefixes (`- `, `1. `, `- [ ] `) are never shown as text in A or B: the dot, number or box is the mark, and
Backspace at the start of the item's text removes it (§6). Revealed marks fade in over `icon` (100 ms) and go at once
(`md:26`); nothing else animates. The rule is `mdView` (`dc:2298–2354`).

---

## 5. Checklists

- **Clicking a box toggles it in the text**: the character between the brackets flips between a space and `x`
  (`dc:2228–2243`). It never moves the caret or takes the keys, editing or not.
- **Outside an editing session** a toggle is its own undo step, "Check Item" / "Uncheck Item", with the usual notice.
  **Inside one** it's a step of the notes' own undo, and part of the session's single "Edit Notes".
- **Square** (recommended, `md:45–55`): 12pt, radius 3.5, a 1.25pt `line-field` ring, centered in the 16pt gutter
  column on the first line (3.5 from its top). Hover: the ring goes `ink-secondary` (`hoverIn` / `hoverOut`). Press:
  scale 0.86 over 80 ms, back on `snappy`. Checked: `ink-tertiary` fill, a white check drawn on over 160 ms, the
  task checkbox's pop. Hit area 20×20.
- **Round** (`md:56–59`): the task checkbox at 14pt, accent when checked. It puts two blue circles on top of each
  other in the pane, which is why it isn't the recommendation.
- **A checked item reads like a completed task:** `ink-tertiary`, struck through in `ink-quaternary` (`md:61`), the
  same as a done row (`tasks-v2.css:171`).
- Return on an item makes a new unchecked item; Return on an empty one ends the list (§6).

---

## 6. Interactions

### Pointer

| Where | Result |
|---|---|
| Text | The caret, there; starts the session if it hadn't started. A drag selects. Marks stay put until the button comes up (`dc:2176`, `dc:1949`) |
| A link (Click variant) | Opens it. No caret. Pointing hand. The underline goes from 40% to full on hover; after 600 ms the address shows in the usual tooltip (`dc:2182`) |
| A link (⌘-click variant) | Plain click places the caret. With ⌘ held: pointing hand, full underline, and a click opens it; the tooltip adds "⌘-click to open" |
| A dot or number | Nothing (it never takes the caret) |
| A box | Toggles it (§5) |
| Empty space under the notes | The caret at the end |
| Anywhere outside the notes | Commits the session (as today) |

### Keys while editing

| Keys | Result | Source |
|---|---|---|
| Return | In a list item, checklist item or quote: a new one below with the same prefix (numbers + 1, boxes unchecked, the same indent). On an empty item: one level out; at the left edge, the prefix goes and the list ends. In a code block: a new line with the same indent. Elsewhere: a new line | `dc:2042–2062` |
| ⇧Return | A plain line break, no continuation | `dc:1993` |
| Backspace at the start of an item's text | One level out; at the left edge, the prefix goes and it becomes a plain line. At the start of a heading or quote, the `#`s or `>` go | `dc:2064–2077` |
| Tab / ⇧Tab | In list items (or a selection over several): in or out one level (two spaces, two levels at most). Elsewhere Tab types a tab and ⇧Tab goes back to the title, as before | `dc:2079–2091` |
| ⌘B / ⌘I | Wrap the selection in `**` / `_` (spaces at either end stay outside; over several lines, each line's text). No selection: the word at the caret, or an empty pair with the caret inside. Inside that style already: take it off | `dc:2093–2124` |
| ⌘K | The link popover (below) | `dc:2126–2163` |
| ⌘Z / ⇧⌘Z | The notes' own undo, typing coalesced per 1.5 s pause. After the session commits, the whole session is one "Edit Notes" step in the app's undo, as today | `dc:1951–1978` |
| ⌥⇧⌘V | Paste as plain text | `dc:2255` |
| Esc, ⌘Return | Done: commit, the keys go to the list | `dc:2248` |
| ⌘D, ⌘S, ⇧⌘D, ⌘T, ⇧⌘M, ⌘1–9 | Unchanged: end the session, then run (INTERACTIONS-v2 §17) | |

**⌘K in the notes.** The app's menu has ⌘K = Complete. While the notes have the caret, the text view takes ⌘K first
(`performKeyEquivalent`) for Add Link, as TextEdit, Notes, Pages and Bear do; Space and ⌘K complete again the moment
the keys are back in the list. Complete stays one click away on the pane's own checkbox. The Edit menu gains "Add
Link… ⌘K" (shown while notes are focused), Bold ⌘B, Italic ⌘I.

### The link popover (⌘K)

The date popover's field and footer, 300 wide, 6 under the selection (above it if it would leave the window),
`Popover in` motion (`dc:213–218`, `md:89–91`).

| Caret or selection | Field starts with | Footer | Return |
|---|---|---|---|
| In a `[text](url)` link | Its address | "Edits “text”", **Remove Link** | Writes the new address; an empty field removes the link and keeps the text |
| In a bare URL | The URL | "Edits “…”" | Replaces it |
| A selection | Empty, or the selection if it's a URL | "Links “selection”" | `[selection](address)` |
| Nothing selected | Empty | "Inserts the link at the caret" | The bare address (`https://` added if it has no scheme; `name@host` becomes `mailto:`) |

Esc closes it and gives the caret back where it was. A press outside closes it without applying.

### Pasting

| Clipboard | Result | Source |
|---|---|---|
| A URL, over selected text | Links the text: `[text](url)` | `dc:2213` |
| A URL alone | The URL, which shows as a link | |
| Rich text (HTML, RTF) | Markdown: bold, italic, code, links, H1 → `#`, H2–H6 → `##`, lists (two levels, checkboxes kept), quotes, `<pre>` → a fenced block, table rows → cells joined by " · ". Fonts, colors, sizes, images and everything else are dropped. Paragraphs get a blank line between them; list items don't | `dc:652–712` |
| Several lines or a block, mid-line | Starts on its own line, and the rest of the line moves below it | `dc:2220–2226` |
| Anything, in a code block or with ⌥⇧⌘V | Plain text | `dc:2210` |
| Past 20,000 characters | Trimmed to fit, with the notice "Notes hold up to 20,000 characters" | `dc:1965–1970` |

**Copy and cut** put the source on the clipboard (`dc:2190`): what you copy is what you'd paste back.

---

## 7. Rows: a hint of the notes

| Variant | Shows | Source |
|---|---|---|
| **Glyph** (recommended) | A three-line glyph, 11pt `ink-quaternary`, first in the chips' slot. When the notes have checkboxes, their count instead: a small box glyph and "2/5", 11/14 medium tabular `ink-tertiary` (all done: `ink-quaternary`) | `dc:85–86`, `md:84–86` |
| Excerpt | The first non-empty line, marks stripped, `ink-tertiary`, 8 after the title inside its fade. Hidden on done rows | `dc:82`, `md:82–83` |
| None | Nothing | |

The row's 30pt shape and 32pt pitch don't change. The summary (has notes, first line, checked / total) is computed
once when the notes change, never while drawing (§9).

---

## 8. Layout, type and states

| Thing | Value | Source |
|---|---|---|
| Body | 13/19 `ink`, SF Pro, wrapping anywhere, tab width 4 | `md:6` |
| Placeholder | "Notes", `ink-tertiary`, shown while the text is empty, focused or not | `md:8` |
| Gutter | The checkbox's 16pt column; item and quote text at 26, a level is 26 more | `md:38`, `dc:517` |
| Headings | `#` 14/20 semibold, 6 above; `##` 13/19 semibold, 4 above; none above the first line | `md:32–35` |
| Inline code | 12/16 SF Mono, `fill-control`, padding 1 / 4, radius 4 (as v2) | `md:14` |
| Code block | 12/17 SF Mono, `fill-control`, radius 6, padding 6 / 10, 2 above and below | `md:71–75` |
| Link | `accent-text`, 1pt underline at offset 2, 40% at rest, full on hover | `md:16–18` |
| Marks | `ink-quaternary`, regular, upright, no underline | `md:26–27` |
| Quote | `ink-secondary`; bar 2pt `fill-strong`, x 7, inset 2 at the ends | `md:65–68` |
| Footer | v2's "Created …", plus " · 19,412 / 20,000" from 18,000 characters | `dc:2668` |
| Inert (untitled new task) | v2's 45%, no caret | |

**Long notes.** The pane body scrolls as one, title and dates included, as today; the notes never get their own
scroller. The notes take their full height so the footer follows the last line (`md:95–96`). Typing keeps the caret
at least one line (19pt) inside the visible body (`dc:2287–2295`). Board: "Long notes".

**Dark and light** use the same tokens (every board row has both). Checked squares are `ink-tertiary` with a white
check in both: 3.8:1 in dark, 5.4:1 in light.

**Reduce Motion:** the marks' fade is 0, like everything else (`tasks-v2.css:376`).

---

## 9. Building it (AppKit / TextKit)

One `NSTextView` for the notes, always editable, never swapped for a label. SwiftUI hosts it through
`NSViewRepresentable`; the title row and fields above stay SwiftUI.

**Storage is the source.** `textStorage.string` is the Markdown. On commit the string goes into `task.update` as it
is. There's no model-to-view conversion, so nothing can drift and nothing costs O(document) on open or save.

**Styling is attributes, applied per line.** A small hand-written scanner (no regex engine, no `AttributedString(markdown:)`,
which drops the marks and can't map back) classifies a line and finds its inline tokens. In
`NSTextStorageDelegate.textStorage(_:didProcessEditing:range:changeInLength:)` restyle only the edited paragraphs.
Code fences are the one non-local rule: keep the sorted fence positions; an edit that adds or removes a fence
restyles to the next fence.

**Hiding marks (variant A).** Use TextKit 1 (`NSLayoutManager`): touching `textView.layoutManager` opts out of TextKit
2 anyway, and TK1 gives two things this needs.

- `NSLayoutManagerDelegate.layoutManager(_:shouldGenerateGlyphs:properties:characterIndexes:font:forGlyphRange:)`
  marks hidden ranges `.null`, so they take no space and the caret skips them.
- `allowsNonContiguousLayout = true`, so a 20,000-character note lays out only what's on screen.

A selection change computes the newly revealed and newly hidden ranges (the token or line under the old and new
caret), then calls `invalidateGlyphs(forCharacterRange:)` and `invalidateLayout` on just those. That's O(token), not
O(document). Variant B needs no glyph work at all: the marks are just a foreground color, and TextKit 2 would do. C
swaps the whole attribute set on focus, which is O(document) once and reflows.

**The gutter and blocks are drawn, not typed.** An `NSLayoutManager` subclass draws the dots, numbers, boxes, the
quote bar and the code blocks' rounded background in `drawBackground(forGlyphRange:at:)`, from a custom attribute on
the paragraph. The prefix characters are hidden as above. Hanging indents are `NSParagraphStyle.headIndent` and
`firstLineHeadIndent`; heading space is `paragraphSpacingBefore`.

**Boxes** hit-test in `mouseDown(with:)`: `characterIndexForInsertion(at:)` → the paragraph → if the point is in its
box rect, flip the one character with `shouldChangeText(in:replacementString:)` / `replaceCharacters` /
`didChangeText` (so it's undoable) and don't call `super`.

**Links** are `.link` attributes; `textView(_:clickedOnLink:at:)` opens them with `NSWorkspace`. The ⌘-click variant
returns `false` without ⌘. Cursor and hover underline come from `NSTextView`'s link handling plus one tracking area.

**Keys** live in the text view subclass: `performKeyEquivalent` for ⌘B, ⌘I, ⌘K (before the menu), `insertNewline`,
`insertNewlineIgnoringFieldEditor` (⇧Return), `insertTab`, `insertBacktab`, `deleteBackward` for the list rules.
Each edit goes through `shouldChangeText` so `NSUndoManager` groups it; typing coalesces by itself.

**Paste** overrides `readSelection(from:type:)`. Prefer `.rtf` (`NSAttributedString(rtf:)` is fast) and walk the
attributes: bold and italic font traits, `.link`, `NSTextList` on the paragraph style. Fall back to `.html` only when
there's no RTF; `NSAttributedString(html:)` loads WebKit, so measure it and cap the input at the 20,000-character
limit. ⌥⇧⌘V is `pasteAsPlainText(_:)`.

**Rows** never parse. When the notes change (one op, one task), the projection computes the summary (has notes,
checked / total, the first line) and assigns only the fields that differ on `TaskModel` (SPEC §9 Fine-grained
observation). A row reads two small fields.

### Against the budget (SPEC §9)

| Operation | Cost | Holds because |
|---|---|---|
| A keystroke | Re-scan one line (~100 characters, µs), restyle it, TextKit relays that paragraph | Per-paragraph delegate; no op is sent (one per session) |
| Moving the caret (A) | Invalidate the old and new token's glyphs | O(token) |
| Opening a task with 20,000 characters | One linear scan (well under 1 ms) plus visible-only layout | Non-contiguous layout |
| Committing | Unchanged: one `task.update` per session, one row redraws | SPEC §5, §9 |
| Toggling a box at rest | One op; the row's count changes | Summary fields on the model |
| Syncing a remote notes change | As today: the open view reloads if not editing; while editing, last writer wins at commit | SPEC §5 |

Add an XCTest `measure` for "open a 20,000-character note" and "type 100 characters into it" to the existing
benchmarks.

---

## 10. In the prototype only

- The browser's contenteditable stands in for NSTextView. Each piece of text carries its source offset (`data-a`), so
  DOM points and source offsets map 1:1 (`dc:589–633`). Every edit is `beforeinput` turned into a source change
  (`dc:1979–2033`); the runtime writes the DOM a frame later, so the caret is put back once the editor carries the
  model's revision (`dc:2264–2296`). In the app none of this exists: NSTextView edits its storage directly.
- IME and dead keys (é with ⌥E) work by writing the composition's result into the source (`dc:2035`). Long IME
  compositions can flicker in the browser; NSTextView handles marked text natively.
- Opening a link shows a notice ("Opens …") instead of leaving the canvas.
- The strip's Notes, Checklists, Rows and Links stand in for the user's choice; the app has one of each, and no
  setting.
- Boards that start part-way through (`dc:768–791`): the caret in "retr|ieval", the popover open, a link hovered, the
  long note scrolled.

## 11. Open questions

1. The four choices in §1.
2. ⌘K = Add Link inside the notes (§6). If the user would rather keep ⌘K as Complete everywhere, Add Link moves to
   ⇧⌘K.
3. VoiceOver: hidden marks are still in the string. The text view should expose the rendered text through
   `accessibilityValue` (and the boxes as checkboxes); to verify in the build.

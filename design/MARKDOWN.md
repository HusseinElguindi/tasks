# Tasks: Markdown notes (build spec)

Status: **final, 2026-10-31, and built** (`app/Tasks/Detail/NotesView.swift`, `NotesMarkdown.swift`, `NotesPaste.swift`,
TasksCore `Markdown.swift`; `app/NOTES-v2.md` "Markdown notes" has how it was checked). The user picked from the
variants (§1). The brief is `docs/TASK-design-markdown.md`. Where the build differs from the text below, §11 says so.

**Canvas:** https://claude.ai/artifact/CmypwyraQx28AYcHSfb5c5 (private until shared from its Share menu). Press Play
on the top board, then click in the notes of "Review CS 489 lectures 10–14". The boards under it start part-way
through, in dark and light.

**Source:** `design/prototype-markdown/`, a copy of `design/prototype-v2/` with the notes replaced. This spec cites it
by line:

- `dc:N` is line N of `design/prototype-markdown/Main.dc.html`.
- `md:N` is line N of `design/prototype-markdown/markdown.css`, which holds every new value. `tasks-v2.css` is
  unchanged.

The prototype is the reference implementation. If this text and the prototype disagree, the prototype is right.

**What it replaces.** `design/INTERACTIONS-v2.md` §7 Notes (rendered inline Markdown at rest, a raw textarea while
editing) and the display line of `docs/SPEC.md` §2 ("`AttributedString(markdown:)` … headings and lists show as their
raw text"). It also does SPEC §11's "Block Markdown rendering". **The model doesn't change:** notes stay one Markdown
string in `notes`, ≤ 20,000 characters, last-writer-wins, committed once per editing session (SPEC §2, §5).

Everything else in the detail pane (title, List, When, Deadline, the separator, the footer, v2 feedback 6's
full-width fields) is v2 as built.

---

## 1. Decisions

| Question | Decision |
|---|---|
| Editing and reading | **Live.** One rendered view, edited in place. Marks show, faintly, only around the caret (§4) |
| Checklist boxes | **Square and neutral.** The round blue box stays the task's alone (§5) |
| A hint in the row | **The notes glyph, or the checklist's count (2/5), right after the title** (§7) |
| A link shortcut | **None.** No ⌘K or ⇧⌘K link action and no link popover. **⌘K stays Complete everywhere**, the notes included (§6) |
| Opening links | **A plain click opens** (NSTextView's default; v2's spec already said so). Not picked by the user; my recommendation stands (§6) |

The alternatives they didn't pick (marks always shown faintly; raw text while editing; round accent boxes; a
first-line excerpt in the row; ⌘-click links; the ⌘K link popover) were removed from the prototype and the canvas.

---

## 2. Principles

1. **The text is the source.** The editor's string is the Markdown, character for character. Styling is attributes;
   hidden marks are still in the string. Saving is reading the string. Nothing converts on the way in or out.
2. **One view, edited in place.** No Edit/Preview switch, no font switch, no relayout on focus. Clicking the notes
   puts the caret where you clicked, and that starts the editing session (`dc:2125–2130`).
3. **Lines are the unit.** Every source line is one paragraph (SPEC §2 already keeps line breaks; a blank line is an
   empty line). A keystroke re-reads one line (`dc:509`).
4. **Quiet.** Marks are `ink-quaternary` and regular weight. Bullets, numbers, boxes and quote bars sit in the
   checkbox's 16pt column, so list text lines up with the title's text at 26.
5. **Existing tokens only.** No new colors. The one derived value is the link underline at 40% of `accent-text`.

---

## 3. What's supported

| Markdown | Shows as | Marks near the caret | Source |
|---|---|---|---|
| `**bold**`, `__bold__` | Semibold | `**` | `md:12`, `dc:557–560` |
| `_italic_`, `*italic*` | Italic | `_` | `md:13`, `dc:557–560` |
| `` `code` `` | 12/16 SF Mono on `fill-control`, padding 1 / 4, radius 4 | `` ` `` (mono) | `md:14`, `md:22`, `dc:546–548` |
| `[text](url)` | `text` as a link | `[` and `](url)` | `md:16–18`, `dc:549–552` |
| A bare `https://…` | A link | none | `dc:553–555` |
| `# Heading` | 14/20 semibold, 6 above | `# ` while the caret is on the line | `md:26`, `md:28` |
| `## Heading` (and `###`–`######`) | 13/19 semibold, 4 above | `## ` on the caret's line | `md:27`, `md:29` |
| `- item`, `* item`, `+ item` | A 5pt dot in the gutter column; text at 26 | never (the dot is the mark) | `md:32–33` |
| `1. item`, `1) item` | The number, right-aligned to 18, tabular, `ink-secondary` | never | `md:35` |
| `- [ ] item`, `- [x] item` | A checklist box in the gutter (§5) | never | `md:39–52` |
| Two spaces before a list item | One level in (26pt), at most two levels; the second level's dot is a ring | never | `dc:2289`, `md:34` |
| `> quote` | `ink-secondary` at 26, a 2pt `fill-strong` bar in the gutter column | `> ` on the caret's line | `md:55–58` |
| ```` ``` ```` fenced block | 12/17 SF Mono on `fill-control`, radius 6, padding 6 / 10, full width, wrapping | both fence lines while the caret is anywhere in the block | `md:61–65` |

**Ordered lists number themselves** from the first item's number, as CommonMark does: `1. 1. 1.` shows 1, 2, 3, so
inserting an item never rewrites the others (`dc:2293`). Return types the next number anyway, so the source reads
right elsewhere.

**Out** (shown as typed): tables, images and attachments, HTML, strikethrough (`~~`), horizontal rules, footnotes,
reference-style links, setext headings, nested quotes, heading levels past two, a third list level, emphasis nested
more than one deep. No shortcuts for code, strikethrough or links.

---

## 4. Showing the marks

At rest the notes are fully rendered: no marks at all. While editing, the view stays rendered and shows, in
`ink-quaternary`:

- the inline marks of every token the selection touches, its ends included (the caret right after `**bold**` shows
  them);
- the `#`s or `>` of each line the selection is on;
- both fence lines of a code block the selection is in (otherwise they take no space).

List prefixes (`- `, `1. `, `- [ ] `) are never shown as text: the dot, number or box is the mark, and Backspace at
the start of the item's text removes it (§6). A box being typed (`- [`) is the one exception (§5). Revealed marks fade in over `icon` (100 ms) and go at once (`md:21`);
nothing else animates. A drag-select doesn't reveal anything until the button comes up, so the text never moves under
the pointer (`dc:2135–2140`, `dc:1948`). The rule is `mdView` (`dc:2257–2311`).

---

## 5. Checklists

- **Clicking a box toggles it in the text**: the character between the brackets flips between a space and `x`
  (`dc:2186–2200`). It never moves the caret or takes the keys, editing or not.
- **Outside an editing session** a toggle is its own undo step, "Check Item" / "Uncheck Item", with the usual notice.
  **Inside one** it's a step of the notes' own undo, and part of the session's single "Edit Notes".
- **The box** (`md:39–49`): 12pt square, radius 3.5, a 1.25pt `line-field` ring, centered in the 16pt gutter column
  on the item's first line (3.5 from its top). Hover: the ring goes `ink-secondary` (`hoverIn` / `hoverOut`). Press:
  scale 0.86 over 80 ms, back on `snappy`. Checked: an `ink-tertiary` fill and a white check drawn on over 160 ms,
  with the task checkbox's pop. Hit area 20×20.
- **A checked item reads like a completed task:** `ink-tertiary`, struck through in `ink-quaternary` (`md:51`), as a
  done row is (`tasks-v2.css:171`).
- Return on an item makes a new unchecked item; Return on an empty one ends the list (§6).
- **Typing a box** (the user, 2026-11-01; the prototype doesn't do this):
  - `- ` makes the dot at once. While the item's whole text is the start of a box (`[`, `[ `, `[x`, `[X`) and the
    selection is on the line, that text shows beside the dot as faint marks (`ink-quaternary`), not as the item's
    text. Away from the caret it's what it is, a bullet whose text is `[`.
  - The `]` that closes the box makes it, and types the space after it as well, with the caret after that space.
    Typing straight on gives `- [ ] text`, never `- [ ]text` (a bullet), so the stored Markdown is what other readers
    take for a checklist item. A space typed there anyway isn't doubled. If a space already follows the caret, `]`
    goes in alone.
  - The `]` and its space are one typing step: one ⌘Z takes both. Backspace right after the box takes the whole
    prefix, as at the start of any item (§6).
  - The same for `*` and `+`, at both levels, and in front of an existing bullet's text. Numbered items have no
    boxes, and pastes go in as they are: a pasted `- [ ]text` stays a bullet.

---

## 6. Interactions

### Pointer

| Where | Result |
|---|---|
| Text | The caret, there; starts the session if it hadn't started. A drag selects |
| A link | Opens it, no caret, pointing hand. The underline goes from 40% to full on hover (`hoverIn` / `hoverOut`); after 600 ms the address shows in the usual tooltip, without its scheme (`dc:2135–2147`, `md:16–18`) |
| A dot or number | Nothing (it never takes the caret) |
| A box | Toggles it (§5) |
| Empty space under the notes | The caret at the end |
| Anywhere outside the notes | Commits the session (as today) |

To edit a link's text or address, put the caret in it with the keys (or click just beside it): its `[`, `](` and
address appear and edit as text.

### Keys while editing

| Keys | Result | Source |
|---|---|---|
| Return | In a list item, checklist item or quote: a new one below with the same prefix (numbers + 1, boxes unchecked, the same indent). On an empty item: one level out; at the left edge, the prefix goes and the list ends. In a code block: a new line with the same indent. Elsewhere: a new line | `dc:2041–2060` |
| ⇧Return | A plain line break, no continuation | `dc:1992` |
| Backspace at the start of an item's text | One level out; at the left edge, the prefix goes and it becomes a plain line. At the start of a heading or quote, the `#`s or `>` go | `dc:2063–2075` |
| Tab / ⇧Tab | In list items (or a selection over several): in or out one level (two spaces, two levels at most). Elsewhere Tab types a tab and ⇧Tab goes back to the title, as before | `dc:2078–2090` |
| ⌘B / ⌘I | Wrap the selection in `**` / `_` (spaces at either end stay outside; over several lines, each line's text). No selection: the word at the caret, or an empty pair with the caret inside. Inside that style already: take it off | `dc:2092–2113` |
| ⌘Z / ⇧⌘Z | The notes' own undo, typing coalesced per 1.5 s pause. After the session commits, the whole session is one "Edit Notes" step in the app's undo, as today | `dc:1950–1977` |
| ⌥⇧⌘V | Paste as plain text | `dc:2214` |
| Esc, ⌘Return | Done: commit, the keys go to the list | `dc:2207` |
| ⌘K, ⌘D, ⌘S, ⇧⌘D, ⌘T, ⇧⌘M, ⌘1–9 | Unchanged: end the session (committing it), then run. **⌘K completes the task** (INTERACTIONS-v2 §17) | `dc:1607` |

The Edit menu gains Bold ⌘B and Italic ⌘I, enabled while the notes have the caret. There is no Add Link command.

### Pasting

| Clipboard | Result | Source |
|---|---|---|
| A URL, over selected text | Links the text: `[text](url)`. This is the way to make a named link | `dc:2171–2175` |
| A URL alone | The URL, which shows as a link | |
| Rich text (HTML, RTF) | Markdown: bold, italic, code, links, H1 → `#`, H2–H6 → `##`, lists (two levels, checkboxes kept), quotes, `<pre>` → a fenced block, table rows → cells joined by " · ". Fonts, colors, sizes, images and everything else are dropped. Paragraphs get a blank line between them; list items don't | `dc:643–703` |
| Several lines or a block, mid-line | Starts on its own line, and the rest of the line moves below it | `dc:2178–2183` |
| Anything, in a code block or with ⌥⇧⌘V | Plain text | `dc:2168` |
| Past 20,000 characters | Trimmed to fit, with the notice "Notes hold up to 20,000 characters" | `dc:1964–1969` |

**Copy and cut** put the source on the clipboard (`dc:2148`): what you copy is what you'd paste back.

---

## 7. Rows: a hint of the notes

A task with notes shows one small hint **right after its title**, 6pt after the text, inside the title's slot. The
chips stay at the right (`dc:82`, `dc:1880–1890`, `md:67–77`).

| Notes | Hint |
|---|---|
| No checkboxes | A three-line glyph, 11pt, `ink-quaternary` |
| Checkboxes | A small box glyph and the count, "2/5": 11/14 medium, tabular, `ink-tertiary`; `ink-quaternary` once all are checked |
| None (or only whitespace) | Nothing |

- **A long title** shrinks first and fades its last 24pt into the hint, which always stays whole. A title that fits
  doesn't fade at all (the fade is applied only when the title is actually cut off: `dc:1891–1906`, `md:72–73`).
  In SwiftUI: `HStack(spacing: 6) { title.lineLimit(1); hint.fixedSize() }`, then `Spacer`, then the chips; apply
  the fade mask only when the title is truncated (measure it, or use `ViewThatFits`).
- A done row's hint is `ink-quaternary`.
- The row's 30pt shape and 32pt pitch don't change. While renaming in the row, the hint hides with the title.
- The count updates when the notes commit (or a box is toggled outside editing), not per keystroke.
- The summary (has notes, checked / total) is computed once when the notes change, never while drawing (§9).

---

## 8. Layout, type and states

| Thing | Value | Source |
|---|---|---|
| Body | 13/19 `ink`, SF Pro, wrapping anywhere, tab width 4 | `md:6` |
| Placeholder | "Notes", `ink-tertiary`, shown while the text is empty, focused or not | `md:8` |
| Gutter | The checkbox's 16pt column; item and quote text at 26, a level is 26 more | `md:32`, `dc:508` |
| Headings | `#` 14/20 semibold, 6 above; `##` 13/19 semibold, 4 above; none above the first line | `md:26–29` |
| Inline code | 12/16 SF Mono, `fill-control`, padding 1 / 4, radius 4 (as v2) | `md:14` |
| Code block | 12/17 SF Mono, `fill-control`, radius 6, padding 6 / 10, 2 above and below | `md:61–65` |
| Link | `accent-text`, 1pt underline at offset 2, 40% at rest, full on hover | `md:16–18` |
| Marks | `ink-quaternary`, regular, upright, no underline | `md:21–22` |
| Quote | `ink-secondary`; bar 2pt `fill-strong`, x 7, inset 2 at the ends | `md:55–58` |
| Footer | v2's "Created …", plus " · 19,412 / 20,000" from 18,000 characters | `dc:2624` |
| Inert (untitled new task) | v2's 45%, no caret | |

**Long notes.** The pane body scrolls as one, title and dates included, as today; the notes never get their own
scroller. The notes take their full height so the footer follows the last line (`md:81–82`). Typing keeps the caret
at least one line (19pt) inside the visible body (`dc:2245–2253`). Board: "Long notes".

**Dark and light** use the same tokens (the boards show both). Checked boxes are `ink-tertiary` with a white check in
both: 3.8:1 in dark, 5.4:1 in light.

**Reduce Motion:** the marks' fade is 0, like everything else (`tasks-v2.css:376`).

---

## 9. Building it (AppKit / TextKit)

One `NSTextView` for the notes, always editable, never swapped for a label. SwiftUI hosts it through
`NSViewRepresentable`; the title row and the fields above stay SwiftUI.

**Storage is the source.** `textStorage.string` is the Markdown. On commit the string goes into `task.update` as it
is. There's no model-to-view conversion, so nothing can drift and nothing costs O(document) on open or save.

**Styling is attributes, applied per line.** A small hand-written scanner (no regex engine, and not
`AttributedString(markdown:)`, which drops the marks and can't map back) classifies a line and finds its inline
tokens. In `NSTextStorageDelegate.textStorage(_:didProcessEditing:range:changeInLength:)` restyle only the edited
paragraphs. Code fences are the one non-local rule: keep the sorted fence positions; an edit that adds or removes a
fence restyles to the next fence.

**Hiding marks.** Use TextKit 1 (`NSLayoutManager`): touching `textView.layoutManager` opts out of TextKit 2 anyway,
and TK1 gives two things this needs.

- `NSLayoutManagerDelegate.layoutManager(_:shouldGenerateGlyphs:properties:characterIndexes:font:forGlyphRange:)`
  marks hidden ranges `.null`, so they take no space and the caret skips them.
- `allowsNonContiguousLayout = true`, so a 20,000-character note lays out only what's on screen.

A selection change works out the newly revealed and newly hidden ranges (the token or line under the old and new
caret), then invalidates glyphs and layout for just those ranges: O(token), not O(document). Don't reveal during a
mouse drag (wait for mouse-up), as the prototype does.

**The gutter and blocks are drawn, not typed.** An `NSLayoutManager` subclass draws the dots, numbers, boxes, the
quote bar and the code blocks' rounded background in `drawBackground(forGlyphRange:at:)`, from a custom attribute on
the paragraph. The prefix characters are hidden as above. Hanging indents are `NSParagraphStyle.headIndent` and
`firstLineHeadIndent`; heading space is `paragraphSpacingBefore`.

**Boxes** hit-test in `mouseDown(with:)`: `characterIndexForInsertion(at:)` → the paragraph → if the point is in its
box rect, flip the one character with `shouldChangeText(in:replacementString:)` / `replaceCharacters` /
`didChangeText` (so it's undoable) and don't call `super`. Outside a session, write it straight to the task as its
own op and undo step.

**Links** are `.link` attributes; `textView(_:clickedOnLink:at:)` opens them with `NSWorkspace`. The pointing hand
comes with `.link`; the hover underline needs one tracking area.

**Keys** live in the text view subclass: `performKeyEquivalent` for ⌘B and ⌘I only (⌘K falls through to the menu's
Complete, which ends the session first, as the other task commands do), `insertNewline`,
`insertNewlineIgnoringFieldEditor` (⇧Return), `insertTab`, `insertBacktab`, `deleteBackward` for the list rules.
Each edit goes through `shouldChangeText` so `NSUndoManager` groups it; typing coalesces by itself.

**Paste** overrides `readSelection(from:type:)`. A single URL over a non-empty selection becomes `[selection](url)`.
For rich text, prefer `.rtf` (`NSAttributedString(rtf:)` is fast) and walk the attributes: bold and italic font
traits, `.link`, `NSTextList` on the paragraph style. Fall back to `.html` only when there's no RTF;
`NSAttributedString(html:)` loads WebKit, so measure it and cap the input at the 20,000-character limit. ⌥⇧⌘V is
`pasteAsPlainText(_:)`.

**Rows** never parse. When the notes change (one op, one task), the projection computes the summary (has notes,
checked / total) and assigns only the fields that differ on `TaskModel` (SPEC §9 Fine-grained observation). A row
reads two small fields.

**Accessibility.** Hidden marks are still in the string, so VoiceOver would read them. Expose the rendered text as
the view's `accessibilityValue`, and each box as a checkbox element with its item's text. Check this in the build.

### Against the budget (SPEC §9)

| Operation | Cost | Holds because |
|---|---|---|
| A keystroke | Re-scan one line (~100 characters, µs), restyle it, TextKit relays that paragraph | Per-paragraph delegate; no op is sent (one per session) |
| Moving the caret | Invalidate the old and new token's glyphs | O(token) |
| Opening a task with 20,000 characters | One linear scan (well under 1 ms) plus visible-only layout | Non-contiguous layout |
| Committing | Unchanged: one `task.update` per session, one row redraws | SPEC §5, §9 |
| Toggling a box at rest | One op; the row's count changes | Summary fields on the model |
| Syncing a remote notes change | As today: the open view reloads if not editing; while editing, last writer wins at commit | SPEC §5 |

Add XCTest `measure` benchmarks for "open a 20,000-character note" and "type 100 characters into it".

---

## 10. In the prototype only

- The browser's contenteditable stands in for NSTextView. Each piece of text carries its source offset (`data-a`), so
  DOM points and source offsets map 1:1 (`dc:580–624`). Every edit is a `beforeinput` turned into a source change
  (`dc:1978–2032`); the canvas runtime writes the DOM a frame after the component updates, so the caret is put back
  once the editor carries the model's revision (`dc:2222–2254`). None of this exists in the app: NSTextView edits its
  storage directly.
- IME and dead keys (é with ⌥E) work by writing the composition's result into the source (`dc:2034`). Long IME
  compositions can flicker in the browser; NSTextView handles marked text natively.
- Opening a link shows a notice ("Opens …") instead of leaving the canvas.
- The title's fade is switched on per row after measuring (`dc:1891–1906`); in SwiftUI it's a layout question (§7).
- Boards that start part-way through (`dc:759–781`): the caret in "retr|ieval", a link hovered, the long note
  scrolled.
- The strip under the main board is v2's (theme, Edit tasks); it isn't part of the app.

---

## 11. As built

Where the app does something other than the text above:

- **Hidden marks** are zero-advance control glyphs, not `.null` ones. A null glyph at the start of a paragraph was laid
  on the line before it, which moved that line's paragraph spacing and its gutter. A hidden fence line is a 0.1pt
  line (a tiny font and line height), never with its newline hidden: a hidden newline stops breaking the paragraph.
- **Restyling** waits until an edit is done (`textDidChange`), not `didProcessEditing`. Attributes changed while the
  storage processes an edit widen its edited range, and NSTextView put the caret at the end of the restyled line. On
  each edit the whole note is re-scanned (0.15 ms at 20,000 characters, optimized), and only the touched lines (to
  the end, when a fence is involved) are restyled.
- **Opening a 20,000-character note** takes about 25 ms: the scan 0.15 ms, styling 11.5 ms and TextKit's layout
  13 ms. SwiftUI needs the notes' full height, so layout is the whole note, not just what's on screen. That's two
  frames at the limit; a note of a couple of thousand characters is about 2 ms. A keystroke is 0.4 ms (median of 100
  in that note; the session's first one is about 12 ms, once).
- **The benchmarks** are TasksCore's `MarkdownTests.testScanBudget` (an XCTest, enforced in release: ≤ 1 ms for the
  scan) and the app's `nbench:` debug step (open and typing, above). The app has no XCTest target for an XCTest
  `measure` of the editor.
- **A box toggled at rest** is its own undo step with no notice, as in the prototype (§5's "usual notice" isn't
  there).
- **Undoing a box toggled in a session** selects the flipped character, as NSTextView's undo does, instead of putting
  the caret back where it was.
- **Links** are drawn and opened by the editor (`.mdLink`), not NSTextView's `.link`, which drew its own underline.


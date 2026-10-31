# Task: design headings and text inside a list, and a clearer list title

The user's words: "i want to think about having some headings and texts within a list, to seperate and describe todos under 1 list. Under the same related note, the title of a list is not very clear. it's not that big, just a small bit of text at the top. can we also explore designs for that. As before, make designs and start with the references."

**This is design only.** Nothing goes into `app/` until the user approves.

## Start from the references, not from scratch

- **The prototype:** `design/prototype-v2/`, including your four views and the brand header. Its canvas is https://claude.ai/artifact/EnWEe86TBSG8voqqwbf7uf.
- **Markdown notes:** the prototype is `design/prototype-markdown/` and the spec is `design/MARKDOWN.md`, both built into the app. Reuse its rendering for any descriptive text, so text in a list and a task's notes look and behave the same.
- **The specs:**
  - `design/INTERACTIONS-v2.md` covers the list pane header (§4 and §12), rows, drag with a gap, selection, keys and §22.
  - `docs/SPEC.md` §1–4 covers the model and ordering: fractional `order` keys, with `list` and `order` written together.
  - `docs/TASK-v2-feedback.md` has the user's accepted tweaks.
- **The look:** Rex is the source of truth (`design/REX-REFERENCE.md`), with Pane as the vocabulary. Look at how Rex itself separates and labels groups. Don't drive Rex; ask the coordinator if you need something measured.
- **What the user likes and dislikes:**
  - The user loves the prototype's animations and quiet details.
  - The user dislikes anything clunky.
  - The user wants simplicity in design and architecture.

## Design

1. **Headings in a list.**
   - What a heading is: a row in the list's order that groups the tasks under it until the next heading.
   - How it looks, how you add one (⌘⇧N? typing in the add row? a context menu?), and how you rename, reorder and delete it, including what happens to its tasks.
   - Collapsing a heading, if it earns its place.
   - Dragging a task under a heading, and dragging a heading with its tasks.
   - How a heading shows up in Today, Upcoming and the other views (probably as context on the row, such as "School › Lab", or not at all).
   - Keyboard navigation over headings.
2. **Text in a list.** Choose between:
   - a list description at the top;
   - free text blocks between tasks;
   - a description under a heading.

   Pick the simplest form that serves "describe todos". Markdown, rendered like the notes.
3. **A clearer list title.**
   - Explore a bigger, clearer title area at the top of the list pane: its size, its weight, the list's colour or tile, its count, and whether the description sits under it.
   - How it fits the window-controls line (§4) and the pane header buttons.
   - Renaming it in place.
   - How it behaves on scroll (a large title that collapses into the header?), and for Today and the four views.
   - It must stay quiet and Rex-like, not a big banner.
4. **Model and sync consequences.** Propose the smallest change:
   - Is a heading a task with `kind: "heading"`, or a new entity with its own ops?
   - Is list text a `description` field on the list?
   - The server's validation may only loosen, so say what it would need.
   - What the CLI/SDK (`docs/SDK-PLAN.md`, `app/TasksCLI`) would need.

   Don't build any of it.

Where there's a real choice, show two or three variants side by side for the user to pick; don't make a menu out of obvious answers.

## Output

- **The prototype:** extend `design/prototype-v2/`, keeping it clickable, and publish a new canvas with boards in dark and light, the variant comparisons, and an example list (a course with headings such as "Lectures", "Labs" and "Exam prep", plus a description).
- **The spec:** add a new spec section to `INTERACTIONS-v2.md`, marked proposed, plus a short model note.
- **Commits:** per path, never `git add -A`, never push. End commit messages with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Report:** the link, the choices and your recommendations to the coordinator, then stop.

You may use subagents.

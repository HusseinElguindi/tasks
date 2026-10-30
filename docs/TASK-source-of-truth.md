# Standing guidance from the user (applies to all remaining UI work)

1. **Rex is the source of truth, not the Pane design system.** Pane (design/PaneTheme.swift, the Claude Design canvases,
   design/DIRECTIONS.md) is a starting point. Don't get stuck copying it explicitly. Wherever Pane and the real Rex app
   disagree (sizes, colors, hover, motion, behavior), match Rex, measured as in design/REX-REFERENCE.md.
2. **Feed learnings upstream.** Keep `design/PANE-UPSTREAM.md`: each time you find something Pane gets wrong or is missing
   compared with Rex (a token value, a component like the checkbox/date chip/row, a hover or motion rule, a timing), add an
   entry: what Pane says now, what Rex actually does (with the measurement), and the proposed change to Pane. The coordinator
   will take these back into the Pane design system later. Commit it with your other commits.

Keep this file (it's standing guidance); don't delete it.

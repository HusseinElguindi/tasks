# Task: build the sync indicator (§26)

The user approved §26 as proposed, including the design agent's calls:
- it goes in the header row, not a footer;
- rejected ops don't turn it amber;
- server errors and timeouts read as offline, in grey;
- the blue dot only shows after 3 s.

The spec is `design/INTERACTIONS-v2.md` §26 (9e1ea5b) and the canvas is https://claude.ai/artifact/9mgrscG1x6wgwXtPSyGT5v. A sidebar footer may come later; don't build it.

**Do this after the calendar (§25) is built and reported.** It can go to a worktree subagent if that doesn't collide.

- **Hook it to the app's existing sync status:** in flight, pending count, last success, offline and retry, a stopped reason or bad token, and sync off. Add only what's missing.
- **Mark §26 final in the spec** (a one-line edit).
- **Verify the states and timings** with the debug hooks:
  - fast polls never flicker;
  - a slow sync shows the pulse for at least 600 ms;
  - a 2 s wake blip shows nothing, and 8 s offline shows the slash;
  - a bad token turns amber and a click opens Settings;
  - the hidden-sidebar button, Reduce Motion, VoiceOver and the inactive app all behave.
- **Rules as before:** scratch instance only, commit per path with the co-author line, never push. Make a Release build and report back.

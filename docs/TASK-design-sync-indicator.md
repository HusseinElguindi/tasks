# Task: a small sync indicator (mock-up only)

The user's words: "i want a small indicator to show refreshing, like a quick cloud icon or something." They want a mock-up of the small piece only: no full-prototype integration and no end-to-end testing.

## The coordinator's proposal, to design against

**Where:** the right end of the sidebar's brand header row ("Tasks"), opposite the mark. With the sidebar collapsed, only problem states show, as a small icon next to the sidebar toggle in the title bar. Mock both. You may also show the sidebar-footer placement as a variant.

**States:**

| State | Shows |
|---|---|
| Synced, nothing pending | Nothing, or a faint cloud on hover |
| Syncing | A small cloud with a gentle pulse, shown only if the sync takes longer than about 300 ms and then held for at least 600 ms (no flicker from the 30 s polls and the ~100 ms syncs) |
| Changes waiting to send | A small dot on the cloud |
| Offline | A grey cloud with a slash, shown only after a few seconds offline (not on a wake blip); it goes away by itself |
| Error (bad token, server error, rejected ops) | An amber cloud with "!", which stays until fixed |
| Long sync (first sync, 409 recovery) | Optionally "Syncing…" text |
| Sync off | A crossed-out cloud, or "Sync off" |

**Interaction:**
- A hover tooltip: "Synced 2 min ago", or the problem in plain words.
- Clicking syncs now (⌘R). For a bad token, it opens Settings.
- Reduce Motion means no pulse. VoiceOver reads the state. Nothing animates while the app is inactive.

## Output

- **A small canvas:** the header row in dark and light, each state as a board (with its tooltip), the collapsed title-bar version, and the pulse timing as a tiny clickable demo. Use SF Symbols-style glyphs that match the app's 12–14pt icon sizes, and Rex-quiet colours from the tokens (`design/THEMES.md` §1).
- **The spec:** a short section, §26, marked proposed, with the states, timings, tokens, glyphs, and how it hooks into the app's existing sync status.
- **Don't** rebuild the full prototype or retest other features.
- **Commits:** per path with the co-author line, never push.
- **Report:** the link and any choices to the coordinator.

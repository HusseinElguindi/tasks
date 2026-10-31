# Themes prototype (Claude Design)

Canvas: https://claude.ai/artifact/Hq16S8JLKGyQqTsbKzNukG (private until shared from its Share menu). The spec is
`design/THEMES.md`, which cites these files.

A copy of `design/prototype-v2/` at commit 16e9625 (before the date-indicator work), with themes added. Press Play
on the first board, click inside once, and use the strip at its foot: Dark or Light, the theme, Classic or Glass,
and whether a switch is instant or fades.

- `themes.js`: the sample themes in the file format, the derivation rules and the contrast check, as
  `window.TasksThemes`. Every board loads it.
- `Main.dc.html`: the prototype. Its additions are the `themeId`, `glass`, `shape` and `font` props, the strip's
  controls, `applyTheme`, `demoTheme` (`demo="theme"`) and notes on PHYS 122's Lab 3 task.
- `tasks-v2.css`, `markdown.css`: prototype-v2's, unchanged. `themes.css` overrides them where a value was hard-coded,
  and adds Glass, the shape and type variants and the cross-fade.
- `Picker.dc.html`, `ThemeCard.dc.html`, `Tokens.dc.html`, the three `*-Variants` / `Shape-Type` boards, the Glass
  boards and the 28 theme boards (`<Theme>-List-*`, `<Theme>-Today-*`).
- `canvas.json`: the canvas layout and its notes. The canvas runtime (`support.js`) comes from the Design artifact
  type and isn't stored here.

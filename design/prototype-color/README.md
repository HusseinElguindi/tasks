# Colour prototype (Claude Design)

Canvas: https://claude.ai/artifact/ANUrtropTfm2GwdAAXWAYv (private until shared from its Share menu). The proposal
is `design/COLOR.md`, which describes these files.

A copy of `design/prototype-v2/` at 54681b8, with four colour directions added. Press Play on the first board and
click inside it once. The strip at its foot picks Dark or Light, a direction (Now, A · Ember, B · Tiles, C · Rooms,
D · Moments, the pick) or each feature on its own.

- `Main.dc.html`: the prototype. Its additions are the `dir` prop, `DIRS` and `FEATS`, `colorCls` and `dpListCls`,
  `demoColor` (`demo="colorlist|alldone"`), the strip's Colour controls, the spark in the checkbox, and the all-done sun.
- `color.css`: the directions. `tasks-v2.css` and `markdown.css` are prototype-v2's, unchanged.
- `Palette.dc.html`: the tokens and contrast board. `Spark.dc.html`: D's spark, looping.
- `<Direction>-List-*`, `-Today-*`, `-Done-*`: the boards.
- `canvas.json`: the layout. The canvas runtime (`support.js`) comes from the Design artifact type and isn't stored
  here. `ds/pane/tokens.json` is copied onto the canvas from the Pane design system and isn't stored here either.

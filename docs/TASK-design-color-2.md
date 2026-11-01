# Colour, follow-up: the tile's finish

The user sent a second, sharper crop of the reference: `docs/feedback/color-reference-orange-2.png`. They asked what
makes it look different: "it has almost a 3d look. and maybe like a very thin black border idk."

The coordinator measured it pixel by pixel. The screenshot is @2x, so 2 px = 1 pt.

- **Size:** 40×32 px = **20×16 pt with radius ≈4 pt**. That's exactly our tile (`TileLayer`, 20×16, r4). It's very
  likely Rex's own program tile, filled with colour.
- **A thin dark outer border:** 1 px (0.5 pt), about #2F2623 on the #444444 tab. That's roughly black at 35–50%,
  antialiased with the orange. It's the "thin black border" the user noticed. It separates the tile from the surface.
- **An inner highlight ring:** 1 px (0.5 pt) inside the edge, lighter all the way round and strongest at the top:
  - top: #E48F71 over a #DA7C59 fill, about +15–20% white;
  - sides: #DF825F over #D66E49, about +15%;
  - bottom: #D47A5B over #CE6B46, about +10%.

  This bevel is most of the "3D" look.
- **A vertical gradient in the fill:** #DA7C59 at the top, #D66F49 in the middle and #CE6B46 at the bottom. That's
  about 5% darker toward the bottom. It's subtle, like light from above.
- **The glyph:** a white 12-ray spark with soft edges, sitting flat on the fill with no shadow you can see.

So the recipe is: a solid fill with a top-to-bottom gradient, plus a 0.5 pt inner light ring (brighter at the top),
plus a 0.5 pt dark outer ring. Our current tile is `tile-fill` with a 0.5 pt `tile-ring` border and a coloured letter.

## Do
1. Add this finish to **direction B (Tiles)**, and to the pick, as the treatment for coloured tiles: sidebar rows,
   list headers, and the brand mark. Give the exact layer recipe the app can build with CALayers: the gradient
   stops as offsets from the hue, the inner ring's white alpha at the top and bottom, and the outer ring's black
   alpha. The rule must derive from any list hue, not only from orange.
2. Show it at 1× and 2× zoom on the canvas, next to the current flat tile, in dark and light. Light mode may want
   a lighter outer ring.
3. Check that the white letter or glyph stays readable on every list hue. Give each contrast figure.
4. Update `design/COLOR.md`. Republish the same canvas URL. Commit per path with the co-author line. Never push.

Report in a few lines when done.

## Update: the source, not a measurement

The user supplied the tile's actual SVG: `docs/feedback/reference-tile.svg`. **Use it instead of the measurements
above.** It draws the tile at about 2.9× our 20×16 (58.5×45.5, radius 13.8). Its layers, bottom to top:

1. **The halo:** the shape grown by 0.5, black at 40%. It's a soft dark outer edge.
2. **The base:** the shape grown by 0.23, solid black. That leaves a crisp hairline of black around the fill.
   Together with the halo, this is the thin black border.
3. **The fill:** flat #E6683D.
4. **The light:** a radial gradient centred at the top-middle. Its ellipse is about 1.4× the tile's width and 1.1×
   its height.
   - It starts at white 21.6% and eases to 0 at 58%.
   - Past that it's black, from 0 to 7.2% at the rim, so the bottom corners darken.

   This is the 3D look: lit from above.
5. **The specular line:** a 1-unit strip along the top edge, white fading 0 → 36% → 0 from left to right, eased.
6. **The inner ring:** a 1-unit ring just inside the edge, white at 10%, all the way around.

Scale these to 20×16 at 1× and 2×. Hairlines will need snapping to device pixels. Rebuild direction B's tiles and
the brand mark with this recipe on every list hue, and keep the same deliverables as above. Note how the app can draw
it: CAGradientLayer has a `.radial` type, and the rings are bordered sublayers.

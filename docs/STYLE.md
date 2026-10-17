# Style

The art rules for Spellmerge, written so a person, an agent or a script can check an asset against them. The vision is in [DESIGN.md](DESIGN.md) (pillar 4, "Readable chaos"); the plan is in [PLAN.md](PLAN.md) ("Art and music").

**Status: provisional.** Claude drafted this style in M1 so Art contributors have something to follow. In M2 an art direction call picks the final style; its golden examples are then recorded in `docs/DESIGN.md` and this file is updated to match. Until then these rules are the ones art is rated against.

## The short version

1. Everything sits on a **32×32 pixel grid**. One art pixel is one screen pixel at 1×.
2. **Light comes from the top-left.** Highlights go on the top and left edges, shadows on the bottom and right.
3. Every object has a **1 px dark outline**.
4. **At most 3 shades per material** (shadow, base, light).
5. **Only palette colours.** No gradients, no blur, no antialiasing, no partial transparency.
6. Four players on screen must stay readable: bold silhouettes, and the four player colours are never mistaken for each other.

## The 32×32 grid

- A sprite or tile is **32×32 px**. Bigger things (a boss, a wide prop) are a whole multiple: 64×64, 96×64 and so on.
- Characters stand on the lower half of the cell with their feet about 2 px above the bottom edge, so they overlap correctly in the top-down view. Leave 1 px of empty border where you can; the outline needs it.
- Tiles fill the whole 32×32 cell and must repeat without a visible seam. A tile's lit edge is its top and left.
- Pixel positions are whole numbers. No half-pixel offsets, no rotation by angles other than 90°, no scaling other than whole multiples.
- Backgrounds are transparent (fully, never partly). Tiles are the exception: they are fully opaque.

## Palette

31 colours: one outline colour and ten materials of three shades each. Write hex values in lower case. No other colour is allowed in a final or placeholder asset.

| Material | Shadow | Base | Light | Use |
| --- | --- | --- | --- | --- |
| **Outline** | `#14121f` | | | The outline of every object; also the deepest shadow |
| **Stone** | `#2b2840` | `#4a4663` | `#7a7694` | Floors, walls, props |
| **Bone** | `#a39fb8` | `#d4d0e0` | `#f4f1ea` | Skulls, text, pale highlights |
| **Fire** | `#8f2d2a` | `#e0592f` | `#ffa23c` | Fire spells, fire enemies, damage |
| **Spark** | `#b8801f` | `#f2c230` | `#fff3a6` | Hit sparks, gold, light sources |
| **Wood** | `#3d2a2e` | `#7a4a35` | `#b27a4a` | Staffs, doors, furniture |
| **Skin** | `#8a5a44` | `#d99a74` | `#f5cfa8` | Faces and hands |
| **Player 1** (blue) | `#1d3a6b` | `#3b73c9` | `#7fc0f0` | Player 1's robe, hat, panel and markers |
| **Player 2** (rose) | `#7a2347` | `#d9477a` | `#f59ab8` | Player 2 |
| **Player 3** (green) | `#1f4a3a` | `#3f8f4f` | `#8fd46a` | Player 3 |
| **Player 4** (purple) | `#4a2a6b` | `#8a4fc4` | `#c99af0` | Player 4 |

The player colours belong to the players: enemies, props and tiles don't use them, so a colour on screen always means a player. Everything else shares the other materials. New element colours (ice, poison and so on) are added to this table when their spells are built; until then, don't invent one.

## Light and shading

- Light comes from the **top-left**. On a rounded shape the highlight sits at the upper left, the shadow at the lower right.
- Shade with the three shades of the material. The base shade covers most of the shape, the light shade the top-left edge and the shadow shade the bottom-right edge.
- **No gradients, no dithering for smooth fades, no glow halos.** A glow is one or two flat rings in the light shade.
- **No baked drop shadow** under a sprite (it needs partial transparency). The game draws shadows.
- Never mix shades of different materials on one surface to fake a fourth shade.

## Outline

- **1 px**, colour `#14121f`, around the whole outside of every sprite and around the main inner parts that need to read (a hat against a face).
- Outlines are closed: no gaps, and no missing corner pixels. Diagonal runs step one pixel at a time.
- Visual effects (bolts, sparks) may use the shadow shade of their own material as the outline instead, so they glow rather than sit in a black box. Tiles have no outline on their outer edge, so they join; their inner details (a crack, a brick joint) use the shadow shade.

## Readability

- A silhouette must read at 1× in solid black. Check it before adding detail.
- Enemy telegraphs use Fire colours and are larger and brighter than anything else on screen.
- Colour is never the only signal for who a player is; the HUD adds a number or a shape next to the colour.
- Player sprites differ only in the player colour ramp. The same shapes in four colours are fine.

## Animation frame counts

One animation is one horizontal strip: frame 1 at the left, each frame 32 px wide, so a 6-frame animation is 192×32. File names end with the animation: `idle.png`, `walk.png`. Playback speed is set in the scene, not in the art. Use fewer frames rather than more: held frames cost nothing.

| Animation | Frames | Loops | Speed | Notes |
| --- | --- | --- | --- | --- |
| Idle | 4 | yes | 6 fps | Breathing or a small bob; 1 px of movement is enough |
| Walk / move | 6 | yes | 12 fps | Same silhouette height in every frame |
| Dodge | 4 | no | 16 fps | Reads as a quick roll or dash; the last frame returns to idle |
| Cast | 4 | no | 16 fps | Frame 3 is the release; the game sends the spell then |
| Hurt | 2 | no | 12 fps | One frame of recoil, one of recovery |
| Downed | 2 | yes | 4 fps | The player lies down in their colour; the revive ring is drawn by the game |
| Death | 6 | no | 12 fps | Ends on an empty frame, never a partly transparent one |
| Enemy attack | 6 | no | 12 fps | Frames 1–3 are the telegraph (wind-up, hold); the hit lands on frame 4 |
| Projectile | 2–4 | yes | 12 fps | Loops while it flies |
| Impact / spark | 4 | no | 20 fps | Over in 0.2 s |
| Animated tile | 4 | yes | 4 fps | Optional (torches, water); still tiles are 1 frame |

A single still image has 1 frame and is a plain 32×32 file.

## File formats

- Art is `.png` or `.svg` (`AGENTS.md`, hard rule 2), at most 1 MB.
- PNGs are 8-bit with colours exactly as in the palette.
- Godot imports every sprite with **filtering off** (nearest neighbour) so pixel edges stay crisp; set this in the file's `.import`.
- Every asset has an entry in `art/manifest.json` with its origin and tier ([art/README.md](../art/README.md)).

## Placeholder SVGs

Sessions and contributors without an image editor may write a pixel sprite as an SVG, listed in the manifest with tier `placeholder`. They follow every rule above and these:

- The root element is `<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32" shape-rendering="crispEdges">`. The size is exactly the grid (or a whole multiple), and `shape-rendering="crispEdges"` is always set.
- **Only `<rect>` elements**, with whole-number `x`, `y`, `width` and `height`, one rect per run of pixels. No `<path>`, `<circle>`, `<ellipse>`, `<polygon>`, `<text>` or `<image>`, because curves and diagonals are antialiased.
- **Palette colours only.** Every `fill` is a lower-case `#rrggbb` from the table above. No named colours, no `rgb()`, no `currentColor`.
- **No antialiasing and no partial transparency:** no `opacity`, `fill-opacity`, `stroke`, `filter`, gradient, pattern, mask, clip path or blend mode, and no `transform` except a whole-number `translate`.
- A background is simply absent; tiles cover all 32×32 with rects.
- Rects don't overlap, so every pixel gets exactly one colour.

A minimal valid example, a stone tile with its lit top-left edge and shaded bottom-right edge:

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32" shape-rendering="crispEdges">
  <rect x="0" y="0" width="31" height="1" fill="#7a7694"/>
  <rect x="0" y="1" width="1" height="30" fill="#7a7694"/>
  <rect x="1" y="1" width="30" height="30" fill="#4a4663"/>
  <rect x="31" y="0" width="1" height="32" fill="#2b2840"/>
  <rect x="0" y="31" width="31" height="1" fill="#2b2840"/>
</svg>
```

## Checklist

Before opening an art PR:

- [ ] 32×32 per frame (or a whole multiple); strips have the frame count from the table.
- [ ] Only palette colours; no gradients, no antialiasing, no partial transparency.
- [ ] 1 px outline, closed; light from the top-left; at most 3 shades per material.
- [ ] Reads as a silhouette at 1×, and next to four players.
- [ ] Imports with filtering off.
- [ ] Manifest entry with the honest origin (and tool and prompt for AI).
- [ ] A screenshot of it in the game in the PR.

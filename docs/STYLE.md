# Style

The art rules for Spellmerge, written so a person, an agent or a script can check an asset against them. The vision is in [DESIGN.md](DESIGN.md) (pillar 4, "Readable chaos"); the plan is in [PLAN.md](PLAN.md) ("Art and music").

**Status: chosen, not provisional.** Claude drafted this style in M1; on 2026-10-23 the owner picked the look from Claude's samples: style N, recorded in [DESIGN.md](DESIGN.md) ("Art direction (locked)"). The wizard is drawn in it (`content/wizard/base/`: a narrow dusk robe with a Spark placket, belt and hem, two big tall eyes and no mouth, under a big pointed hat in the player's colour). Everything else is redrawn in the same spirit, one area at a time, over later milestones. These rules are the ones art is reviewed against.

## The short version

1. Everything sits on a **32×32 pixel grid**. One art pixel is one screen pixel at 1×.
2. **Light comes from the top-left.** Highlights go on the top and left edges, shadows on the bottom and right.
3. Every object has a **1 px dark outline**.
4. **At most 3 shades per material** (shadow, base, light).
5. **Only palette colours.** No gradients, no blur, no antialiasing, no partial transparency.
6. Four players on screen must stay readable: bold silhouettes, and the four player colours are never mistaken for each other.

## The 32×32 grid

- A sprite or tile is **32×32 px**. Bigger things (a boss, a wide prop) are a whole multiple: 64×64, 96×64 and so on.
- Characters stand on the lower half of the cell with their feet about 2–3 px above the bottom edge, so they overlap correctly in the top-down view. Leave 1 px of empty border where you can; the outline needs it.
- Tiles fill the whole 32×32 cell and must repeat without a visible seam. **Floor tiles are flat**: Stone base with a few inner details (a crack, a joint) in Stone shadow or light, and nothing on the outer edge pixels. The top-left lit edge and bottom-right shaded edge apply only to **walls and raised props**.
- Pixel positions are whole numbers. No half-pixel offsets, no rotation by angles other than 90°, no scaling other than whole multiples.
- Backgrounds are transparent (fully, never partly). Tiles are the exception: they are fully opaque.

## Palette

40 colours: one outline colour and thirteen materials of three shades each. Write hex values in lower case. No other colour is allowed in a final or placeholder asset.

| Material | Shadow | Base | Light | Use |
| --- | --- | --- | --- | --- |
| **Outline** | `#14121f` | | | The outline of every object; also the deepest shadow |
| **Stone** | `#2b2840` | `#4a4663` | `#7a7694` | Floors, walls, props |
| **Bone** | `#a39fb8` | `#d4d0e0` | `#f4f1ea` | Skulls, text, pale highlights |
| **Fire** | `#8f2d2a` | `#e0592f` | `#ffa23c` | Fire spells, fire enemies, damage |
| **Spark** | `#b8801f` | `#f2c230` | `#fff3a6` | Hit sparks, gold, light sources |
| **Wood** | `#3d2a2e` | `#7a4a35` | `#b27a4a` | Staffs, doors, furniture |
| **Skin** | `#8a5a44` | `#d99a74` | `#f5cfa8` | Faces and hands |
| **Ice** | `#1f7080` | `#4fd6dc` | `#c4f6f2` | Frost spells, ice, cold effects |
| **Void** | `#4a1450` | `#a0309a` | `#e08ad8` | Void spells, void effects |
| **Arc** | `#3f6b10` | `#b4e82a` | `#eeffa6` | Lightning spells and the static charge: an acid lime, apart from Spark's gold, the players' greens and Ice's cyan |
| **Player 1** (blue) | `#1d3a6b` | `#3b73c9` | `#7fc0f0` | Player 1's robe, hat, panel and markers |
| **Player 2** (rose) | `#7a2347` | `#d9477a` | `#f59ab8` | Player 2 |
| **Player 3** (green) | `#1f4a3a` | `#3f8f4f` | `#8fd46a` | Player 3 |
| **Player 4** (purple) | `#4a2a6b` | `#8a4fc4` | `#c99af0` | Player 4 |

The player colours belong to the players: enemies, props and tiles don't use them, so a colour on screen always means a player. Everything else shares the other materials. New element colours (poison and so on) are added to this table when their spells are built; until then, don't invent one.

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
- Player sprites differ only in the player colour ramp. The ramp covers the hat (and the panel and markers) and nothing else on the wizard: the robe is Stone and Spark for every player, the face and hands use Skin, the staff uses Wood. The hat is its own picture (`wizard_hat_pN.svg`), drawn over one shared body strip.
- The four player base colours (`#3b73c9`, `#d9477a`, `#3f8f4f`, `#8a4fc4`) are the comparison set: any two must differ clearly in hue, and nothing else on screen may use a colour close to one of them.
- Floors use only Stone base and light, with Stone shadow only for small inner details. Players and enemies don't use Stone shadow for their own surfaces, so a silhouette doesn't melt into the floor.

## Animation frame counts

One animation is one horizontal strip: frame 1 at the left, each frame 32 px wide, so a 6-frame animation is 192×32. File names end with the animation: `idle.png`, `walk.png`. Playback speed is set in the scene, not in the art. Use fewer frames rather than more: held frames cost nothing.

| Animation | Frames | Loops | Speed | Notes |
| --- | --- | --- | --- | --- |
| Idle | 4 | yes | 6 fps | Poses, not motion: eyes open, eyes closed (the blink), glance left, glance right. The game orders them (a blink every few seconds, a glance now and then) and adds the breathing bob itself: body and hat sit 1 px lower for part of each breath (`IDLE_SEQUENCE`, `BREATH_STEPS`) |
| Walk / move | 4 | yes | 8 fps | Same silhouette height in every frame; the game dips the body on alternate frames (`WALK_BOB`) |
| Dodge | 2 | no | 16 fps | A crouch, then lifted off the ground (`DASH_BOB`); the last frame holds, then idle returns |
| Cast | 4 | no | 16 fps | Frame 3 is the release; the game sends the spell then |
| Hurt | 2 | no | 12 fps | One frame of recoil, one of recovery |
| Downed | 2 | yes | 4 fps | The player lies down in their colour; the revive ring is drawn by the game |
| Death | 6 | no | 12 fps | Ends on an empty frame, never a partly transparent one |
| Enemy attack | 6 | no | 12 fps | Frames 1–3 show the telegraph (wind-up, hold); the hit pose is frame 4 |
| Projectile | 2–4 | yes | 12 fps | Loops while it flies |
| Impact / spark | 4 | no | 20 fps | Over in 0.2 s |
| Animated tile | 4 | yes | 4 fps | Optional (torches, water); still tiles are 1 frame |

The table is a guide; the wizard's real values are the constants in `gameplay/player/player.gd`.

A single still image has 1 frame and is a plain 32×32 file.

The art only shows timing; it doesn't set it. The telegraph's length and the moment damage lands are set by the AI and the scene (the telegraph frames can be held longer there; 0.25 s is only the shortest), never by the animation.

## File formats

- Art is `.png` or `.svg` (`AGENTS.md`, hard rule 2), at most 1 MB.
- PNGs are 8-bit with colours exactly as in the palette.
- Godot imports every sprite with **filtering off** (nearest neighbour) so pixel edges stay crisp; set this in the file's `.import`.
- Every asset has an entry in `art/manifest.json` with its origin and tier ([art/README.md](../art/README.md)).

## Placeholder SVGs

Sessions and anyone else without an image editor may write a pixel sprite as an SVG, listed in the manifest with tier `placeholder`. They follow every rule above and these:

- The root element is `<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32" shape-rendering="crispEdges">`. The size is exactly the grid (or a whole multiple), and `shape-rendering="crispEdges"` is always set.
- **Only `<rect>` elements**, with whole-number `x`, `y`, `width` and `height`, one rect per run of pixels. No `<path>`, `<circle>`, `<ellipse>`, `<polygon>`, `<text>` or `<image>`, because curves and diagonals are antialiased.
- **Palette colours only.** Every `fill` is a lower-case `#rrggbb` from the table above. No named colours, no `rgb()`, no `currentColor`.
- **No antialiasing and no partial transparency:** no `opacity`, `fill-opacity`, `stroke`, `filter`, gradient, pattern, mask, clip path or blend mode, and no `transform` except a whole-number `translate`.
- A background is simply absent; tiles cover all 32×32 with rects.
- Rects don't overlap, so every pixel gets exactly one colour.

A minimal valid example, a stone **wall** tile with its lit top-left edge and shaded bottom-right edge (a floor tile is flat instead, see "The 32×32 grid"):

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32" shape-rendering="crispEdges">
  <rect x="0" y="0" width="31" height="1" fill="#7a7694"/>
  <rect x="0" y="1" width="1" height="30" fill="#7a7694"/>
  <rect x="1" y="1" width="30" height="30" fill="#4a4663"/>
  <rect x="31" y="0" width="1" height="32" fill="#2b2840"/>
  <rect x="0" y="31" width="31" height="1" fill="#2b2840"/>
</svg>
```

## UI

The HUD (M1 parts 18 and 19) and the Style Guide page build on these.

- **Font:** one pixel font, set in `hud/theme`, at whole-number sizes only. Body text is Bone light on Stone shadow; headings Bone base; warnings Fire light; gold and pickups Spark light. No other text colours.
- **Panels:** a 1 px Outline border, Stone shadow fill, a Stone light top and left inner edge (3 shades at most). Corners are cut by one pixel, not rounded.
- **Player panels:** the border and name tab use that player's ramp (base fill, light top-left edge, shadow bottom-right edge). Next to the colour sit the player's number (1–4) and a shape, so colour is never the only signal. Health bars are Fire and mana bars Bone on a Stone shadow trough; neither uses a player colour.
- **Icons:** 16×16 for spells and relics in the overlay, 8×8 for status marks, with the 1 px outline and at most 3 shades per material.
- Everything snaps to whole pixels at the 640×360 base size, and four panels stay readable there.

## Golden examples

The pieces the Style Guide page shows as "this is the look", listed with what each one shows in [art/kit/golden.json](../art/kit/golden.json). The player character is in the chosen style N; the others are the best placeholder art so far and are redrawn in that style over later milestones, when they move here. Copy their approach, not their pixels.

| Kind | File | What to learn from it |
| --- | --- | --- |
| Player character | `art/kit/golden_wizard.svg` (the game's `content/wizard/base/wizard_idle.svg` under `wizard_hat_p1.svg`) | Style N: a narrow Stone robe with a Spark placket, belt and hem, two big tall eyes (2×3 px with a highlight), no mouth, Skin hands, under a hat in the player ramp; feet about 1 px above the bottom edge |
| Enemy | `content/enemies/ember_imp/idle.svg` | Fire body, Bone horns and Spark eyes, no player colour, a bold silhouette |
| Raised tile | `art/tilesets/crypt/wall.svg` | Lit top and left edge, shaded bottom and right edge |
| Flat tile | `art/tilesets/crypt/floor.svg` | Stone base, a few inner details, nothing on the outer edge |
| Projectile | `art/vfx/bolt.svg` | Neutral Bone streak with a Spark core (the owner tints the Bone, the element colours the core), outlined in its own shadow shade |
| Impact | `art/vfx/hit_spark.svg` | A flat Spark burst, no glow halo |

## The starter kit

The source files are in [art/kit/](../art/kit/README.md): the palette (`spellmerge.gpl.txt` for GIMP-style editors, `palette.hex.txt`), a 32×32 grid and an animation strip template as SVG, `golden.json` and the one-page checklist [art/kit/checklist.md](../art/kit/checklist.md). The palette files and the checklist copy this document; when you change the palette table, frame counts or the checklist below, change them too.

## Checklist

Before an art PR is opened, by the bot or a commissioned artist:

- [ ] 32×32 per frame (or a whole multiple); strips have the frame count from the table.
- [ ] Only palette colours; no gradients, no antialiasing, no partial transparency.
- [ ] 1 px outline, closed; light from the top-left; at most 3 shades per material.
- [ ] Reads as a silhouette at 1×, and next to four players.
- [ ] No baked drop shadow, no glow halo; the background is fully transparent (tiles are fully opaque).
- [ ] Floors are flat; walls and raised props have the lit top-left edge. Tiles repeat without a seam.
- [ ] Imports with filtering off.
- [ ] Manifest entry with the honest origin (and tool and prompt for AI).
- [ ] A screenshot of it in the game in the PR.

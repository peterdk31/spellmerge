# Spellmerge art checklist

One page. Full rules: docs/STYLE.md (the Style Guide page on the website shows them with pictures).

## The six rules

1. **32×32 grid.** One art pixel is one screen pixel. Bigger things are whole multiples (64×64, 96×64).
2. **Light from the top-left.** Highlights on the top and left, shadows on the bottom and right.
3. **1 px dark outline** (`#14121f`) around every object, closed, no gaps.
4. **At most 3 shades per material:** shadow, base, light.
5. **Only the 43 palette colours.** No gradients, blur, antialiasing or partial transparency.
6. **Four players stay readable:** bold silhouettes; the player colours belong to the players only.

## Before you open the PR

- [ ] 32×32 per frame (or a whole multiple); an animation is one horizontal strip with the frame count from the table below.
- [ ] Only palette colours (`palette.hex.txt`, or the `.gpl` palette in your editor).
- [ ] 1 px outline, closed; light from the top-left; at most 3 shades per material.
- [ ] No baked drop shadow, no glow halo; the background is fully transparent (tiles are fully opaque).
- [ ] Reads as a black silhouette at 1×, and next to four players.
- [ ] Floors are flat; walls and raised props have the lit top-left edge. Tiles repeat without a seam.
- [ ] Imports with filtering off (nearest neighbour).
- [ ] Manifest entry in `art/manifest.json` with the honest origin (`human` or `ai`; for AI also tool and prompt).
- [ ] A screenshot of it in the game in the PR.

## Frame counts

| Animation | Frames | Strip size | Loops |
| --- | --- | --- | --- |
| Idle | 4 | 128×32 | yes |
| Walk / move | 6 | 192×32 | yes |
| Dodge | 4 | 128×32 | no |
| Cast | 4 | 128×32 | no |
| Hurt | 2 | 64×32 | no |
| Downed | 2 | 64×32 | yes |
| Death | 6 | 192×32 | no |
| Enemy attack | 6 | 192×32 | no |
| Projectile | 2–4 | 64–128×32 | yes |
| Impact / spark | 4 | 128×32 | no |
| Animated tile | 4 | 128×32 | yes |

## Palette

Outline `#14121f`. Shadow / base / light:

- Stone `#2b2840` `#4a4663` `#7a7694`
- Bone `#a39fb8` `#d4d0e0` `#f4f1ea`
- Fire `#8f2d2a` `#e0592f` `#ffa23c`
- Spark `#b8801f` `#f2c230` `#fff3a6`
- Wood `#3d2a2e` `#7a4a35` `#b27a4a`
- Skin `#8a5a44` `#d99a74` `#f5cfa8`
- Player 1 (blue) `#1d3a6b` `#3b73c9` `#7fc0f0`
- Player 2 (rose) `#7a2347` `#d9477a` `#f59ab8`
- Player 3 (green) `#1f4a3a` `#3f8f4f` `#8fd46a`
- Player 4 (purple) `#4a2a6b` `#8a4fc4` `#c99af0`

## Golden examples

Copy their approach, not their pixels. The list is `art/kit/golden.json`.

- Player character (style N): `art/kit/golden_wizard.svg`
- Enemy: `content/enemies/ember_imp/idle.svg`
- Raised tile: `art/tilesets/crypt/wall.svg`; flat tile: `art/tilesets/crypt/floor.svg`
- Projectile: `art/vfx/bolt.svg`; impact: `art/vfx/hit_spark.svg`

Art is CC-BY-SA-4.0 by default. Only original work: no ripped assets, no fan art, no names from other works.

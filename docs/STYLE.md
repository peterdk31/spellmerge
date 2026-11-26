# Style

The art rules for Spellmerge, written so a person, an agent or a script can check an asset against them. The vision is in [DESIGN.md](DESIGN.md) (pillar 4, "Readable chaos"); the plan is in [PLAN.md](PLAN.md) ("Art and music").

**Status: chosen, not provisional.** Claude drafted this style in M1; on 2026-10-23 the owner picked the look from Claude's samples: style N, recorded in [DESIGN.md](DESIGN.md). On 2026-10-28 the owner made every character a living staff ([milestones/M2-living-staffs.md](milestones/M2-living-staffs.md)): a player is a floating staff with cartoon eyes and brows, an enemy (a stray) a meaner staff with glowing eyes; the style N wizard, robe and pointed hat, is now the villain. Everything else is redrawn in the same spirit, one area at a time, over later milestones. These rules are the ones art is reviewed against.

**More detailed art** (the owner's decision of 2026-11-21, confirmed on 2026-11-25): sprites are redrawn at **64×64 for a 32-unit cell, at the same size on screen, in a 1280×720 picture**. The world keeps its 32-unit tiles and the simulation is untouched: art drawn at 2x detail is drawn at half its size, two art pixels a world unit. The HUD and the font are redrawn at 2x detail at the same size on screen. Everything is redrawn in this order: players and enemies, spells and effects, rooms and props, HUD and font. Until then today's art and redrawn art share the screen ("The picture and the art's detail"). The curl staff is the first redrawn (ART0, the pilot).

## The short version

1. Everything sits on a **grid of 32 world units**. Redrawn art has **64 art pixels per 32 units** (2x detail, named `@2x`); art not yet redrawn has 32. The game draws a 1280×720 picture: at zoom 1 a redrawn art pixel is one picture pixel, an old one two.
2. **Light comes from the top-left.** Highlights go on the top and left edges, shadows on the bottom and right.
3. Every object has a **1 px dark outline**.
4. **At most 3 shades per material** (shadow, base, light).
5. **Only palette colours.** No gradients, no blur, no antialiasing, no partial transparency.
6. Four players on screen must stay readable: bold silhouettes, and the four player colours are never mistaken for each other.
7. **Everything looks smooth.** Nothing changes its look in one jump: a change plays the frames between ("Smooth").
8. **Rooms go further** (the owner, 2026-11-16: "Go past it. The style-guide should be updated"): a room's ground and light may use colours outside the palette, soft light, glow and gradients, drawn per pixel as PNGs (see "Rooms"). The characters, enemies, props, spells and UI keep rules 1 to 7.

## Rooms

The hub (docs/milestones/hub-rework.md) and the crypt (docs/milestones/crypt-rework.md) are drawn past the rules above where it makes them look better. What a room may do, and what it still may not:

- **May:** a ground drawn per pixel from a shape (`tools/ground_shape.py`: content/rooms/README.md, "A room's ground from a shape") as PNGs, not rect-only SVGs; colours and shades outside the palette in its ground, its walls' art, its void and its light (a turf, a cool quiet stone, a deep dark); soft light and glow (a torch's or a candle's pool, a shaft of light from above, an edge's glow, a pit's cold breath); gradients in the void, a beam, a wall's top falling into the dark; organic lines everywhere, never a tile's straight edge where the eye goes (the owner, 2026-11-16).
- **May not:** blur or fade what moves (rule 7 holds: a change of look is frames of whole pixels, never an alpha pulse); use a player's colours or Blight in the world (they mean a player and the enemies' spells); outshine the fight. A room's floor is one quiet value, quieter than every shot, enemy and wizard on it ("Readability"); its dark is at its walls and in its corners, never where the fight is.
- **Still:** the 32-unit grid for where things stand and how big they are, whole pixels (as drawn; on screen see "Smooth", "The default zoom 1 and whole pixels"), the pixel look, light from the top-left on what stands in the room (pillars, props), and the size and file rules (AGENTS.md).

The tile rules below ("Floor tiles are flat", the golden floor and wall) are for tiled rooms and the tests' own stages; a room drawn from a shape follows this section.

## The 32-unit grid

- A sprite or tile covers **32×32 world units**: 32×32 px for art not yet redrawn, **64×64 px for art drawn at 2x detail** ("The picture and the art's detail"). Bigger things (a boss, a wide prop) are a whole multiple: 64×64 units, 96×64 and so on (128×128 px, 192×128 px at 2x).
- Characters stand on the lower half of the cell with their feet about 2–3 units above the bottom edge (4–6 px at 2x), so they overlap correctly in the top-down view. Leave 1 px of empty border where you can; the outline needs it.
- Tiles fill the whole 32×32 cell and must repeat without a visible seam. **Floor tiles are flat**: Stone base with a few inner details (a crack, a joint) in Stone shadow or light, and nothing on the outer edge pixels. The top-left lit edge and bottom-right shaded edge apply only to **walls and raised props**.
- Pixel positions are whole numbers of the art's own pixels. No half-pixel offsets, no rotation by angles other than 90°, no scaling other than whole multiples (and the half of 2x art, below).
- Backgrounds are transparent (fully, never partly). Tiles are the exception: they are fully opaque.

## The picture and the art's detail

The owner's decision of 2026-11-21, confirmed on 2026-11-25 (ART0 built it, after the owner weighed 960×540 with 48 px art and 640×360 laid out beside it): the game draws a **1280×720 picture** (project.godot), showing the same world as the 640×360 picture did, twice as finely. One place says it: `PictureGrid` (core/display/picture_grid.gd: the layout `SIZE` 640×360 times `PICTURE_SCALE`, k = 2), and one the art's detail (`ArtDetail.DETAIL`, d = 2: 64 px a 32-unit cell).

- **Stretched to the window by whole numbers, or by a fraction on a 1080p screen** (the owner's decision of 2026-11-25): the picture is drawn 1, 2 or 3 times (720p, 1440p, 4K) while a whole number fills the screen; where it would leave the screen mostly empty (the largest whole number filling less than 85% of its width or height: a 1920×1080 screen holds 1280×720 once, two thirds of it) it is stretched by the largest fraction that fits, its aspect kept and its pixels hard (nearest): 1080p shows it 1.5 times, each picture pixel 1 or 2 screen pixels, so 64 px art there has uneven rows of 1 or 2 screen pixels, which the owner accepts; 32 px art, two picture pixels an art pixel at zoom 1, stays even (3 screen pixels each). `Display.stretch_for` (core/display/display.gd) decides as the window's size changes.

- **The world is unchanged.** Tiles are 32 units, rooms, bodies, hit circles and speeds are as they were, and nothing in the simulation knows the picture's size. The cameras' zoom 1 shows 640×360 of the world (they rest at 0.8, 800×450 of it).
- **Two details of art, one rule** (`ArtDetail`, core/display/art_detail.gd): a texture whose file is named **`<name>@2x.<ext>`** (`head@2x.png`, `idle@2x.png`) has **2 art pixels a world unit** each way and is drawn at half its size; any other texture has 1 and is drawn at its size. Nothing else says it: no import option, no list. A texture made in the game from art (a `TexturePage` region, a baked floor) carries its source's detail. A sprite's frames, offsets, origins and grips are measured in its own art pixels, its place in the world in world units; its strips and frame counts are the same (a 6-frame strip at 2x is 384×64).
- **The cameras rest at zoom 1** (the owner's decision of 2026-11-25, on ART0; 0.8 from 2026-11-23): 640×360 of the world, so every art pixel shows: today's art as a 2×2 block of the picture (nearest, whole pixels), art at 2x as one picture pixel. A room smaller than the picture is seen closer.
- **Zoomed out to hold a party** (down to 0.5, before the screen splits) the world is resampled into the picture: today's art one or two picture pixels an art pixel, none left out down to zoom 0.5; art at 2x below one picture pixel an art pixel, so some art pixels are left out (one in five at 0.8, one in two at 0.5) and a one-pixel line can break while the party is spread.
- **Whole pixels of the picture:** every sprite's place is snapped to the picture's whole pixels (`rendering/2d/snap/snap_2d_transforms_to_pixel`), so a sprite never shimmers inside itself as it moves; a 2x sprite moves by half world units, which are whole picture pixels at zoom 1 (`ArtDetail.snap` for a look that rounds its own places).
- **What takes it:** sprites and sheets (`ArtDetail.fit`: the node's scale; a look's own stretch times it), faces (`Face`, `FaceArt` at any frame size, a staff's own face, `StaffBase.face`), the staff's head (`StaffLook`), `TexturePage` regions, a MultiMesh batch's quad (`ArtDetail.quad_size`; the cover's shader takes `art_detail`), the floor states drawn by a shader (`CoverFlat.DETAIL`, at 2x since the floor's look, docs/milestones/floor-look.md), and the baked floors (baked at the picture's scale, so their glow keeps its smoothness: `FloorBake.picture_scale`).
- **The light, the mist and the air keep their own resolution:** the light is a grid of world cells, the mist and the tints are worked out a world pixel at a time ("Smooth"), whatever the picture.
- **The screen's layers** (the HUD, the menus, the intro, the markers, the Y map, the split's dividers) are laid out in **layout pixels**, 640×360, and drawn at the picture's scale (`PictureGrid.fit_layer`), so they look the same size; HUD art redrawn at 2x detail goes in them as sprites do. Text is drawn at its whole-number size and scaled with its layer.
- **The palette is unchanged.** Every rule of this guide holds at 2x: the outline is one art pixel, at most 3 shades a material, light from the top-left, no partial transparency.

How to redraw a sprite at 64×64: art/README.md, "Redrawing a sprite at 64x64".

## Palette

55 colours: one outline colour and eighteen materials of three shades each. Write hex values in lower case. No other colour is allowed in a final or placeholder asset.

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
| **Water** | `#0f4a44` | `#1e9c8c` | `#6fdcc0` | Water spells, the soaked status, fountains and puddles: a deep sea teal, greener and darker than Ice's cyan (frost), far from Mana's ultramarine and Player 1's blue, and bluer than Player 3's green |
| **Void** | `#4a1450` | `#a0309a` | `#e08ad8` | Void spells, void effects |
| **Mana** | `#161c55` | `#2c3aa8` | `#6f86f0` | Mana itself, seen moving (a siphon's mana knocked off a body and back into the staff; the owner, 2026-11-16: "mana should be dark blue"): a deep ultramarine, bluer and darker than Player 1's blue so it never reads as a player's |
| **Arc** | `#3f6b10` | `#b4e82a` | `#eeffa6` | Lightning spells and the static charge: an acid lime, apart from Spark's gold, the players' greens and Ice's cyan |
| **Leaf** | `#2f4022` | `#5b7233` | `#a0ad55` | Grass, moss and other growth on the floor (ground cover): a dull olive, darker and yellower than Player 3's green and far duller than Arc's lime |
| **Oil** | `#211a1e` | `#4a3729` | `#b88a3e` | Oil on the floor and the Oil card (docs/milestones/oil-spill.md): a dark umber slick with an amber sheen, the darkest base of the palette, browner than Stone and far darker than Wood's and Blight's |
| **Blight** (ochre) | `#4d3f12` | `#a68a2a` | `#e3cf6b` | Enemies' spells: where a player's colour shows in a shot, an enemy's shows this (the owner, 2026-10-27). A dull ochre, darker than Spark's gold and far from the four player hues |
| **Player 1** (blue) | `#1d3a6b` | `#3b73c9` | `#7fc0f0` | Player 1's robe, hat, panel and markers |
| **Player 2** (rose) | `#7a2347` | `#d9477a` | `#f59ab8` | Player 2 |
| **Player 3** (green) | `#1f4a3a` | `#3f8f4f` | `#8fd46a` | Player 3 |
| **Player 4** (purple) | `#4a2a6b` | `#8a4fc4` | `#c99af0` | Player 4 |

The player colours belong to the players: enemies, props and tiles don't use them, so a colour on screen always means a player. Blight is the enemies' counterpart: it marks an enemy's spell, and nothing else uses it. Everything else shares the other materials. New element colours (poison and so on) are added to this table when their spells are built; until then, don't invent one.

## Light and shading

- Light comes from the **top-left**. On a rounded shape the highlight sits at the upper left, the shadow at the lower right.
- Shade with the three shades of the material. The base shade covers most of the shape, the light shade the top-left edge and the shadow shade the bottom-right edge.
- **No gradients, no dithering for smooth fades, no glow halos.** A glow is one or two flat rings in the light shade.
- **The exception: spell shots glow** (the owner, 2026-10-27). The shot shaders (`core/projectiles/shot_*.gdshader`, one per kind: core/README.md, "The shot shaders") add a soft light in the shot's colour round its core and tail, added to what is below. It is the shader's, never baked into an asset: sprites, tiles and icons keep the rules above.
- **The world may take light from spells** (the owner, 2026-11-04). Shots, blasts, beams and a room's torches light the floor, the walls and the bodies round them (spell light, `gameplay/feel/spell_light.gd`), in the light's own colour, in the steps the light's `bands` sets. The light is drawn by the game over the art, never baked into it: the art is drawn as it is, and a room's `ambient` only darkens it evenly.
- **The exception: the floor mist is soft** (the owner, 2026-11-18; docs/milestones/atmosphere.md, F). A room's low mist (`RoomBase.mist`, drawn by `gameplay/feel/mist.gd`) alone may be soft and see-through: worked out a world pixel at a time, its see-through and its drift soft (not stepped), closing over frames. It is the game's, drawn over the floor and under every body, never baked into art; thin over a fight's middle, thicker at a room's edges and pits ("Readability"). Everything else keeps the pixel rules.
- **No baked drop shadow** under a sprite (it needs partial transparency). The game draws shadows.
- Never mix shades of different materials on one surface to fake a fourth shade.

## Outline

- **1 px**, colour `#14121f`, around the whole outside of every sprite and around the main inner parts that need to read (a hat against a face).
- Outlines are closed: no gaps, and no missing corner pixels. Diagonal runs step one pixel at a time.
- Visual effects (bolts, sparks) may use the shadow shade of their own material as the outline instead, so they glow rather than sit in a black box. Tiles have no outline on their outer edge, so they join; their inner details (a crack, a brick joint) use the shadow shade.

## Readability

- A silhouette must read at 1× in solid black. Check it before adding detail.
- Enemy telegraphs use Fire colours and are subtle (the owner, 2026-11-18; first "larger and brighter than anything else on screen"): a faint wash between dotted edges, fading in smoothly from the caster's end (a smooth gradient by the owner's word, the one exception here to whole-pixel steps), brightening only as the cast is about to leave.
- Colour is never the only signal for who a player is; the HUD adds a number or a shape next to the colour.
- Player sprites differ only in the player colour ramp. The ramp covers the staff's head (the curl's gem, the star, the crescent, the crystal; and the panel and markers) and nothing else: the shaft is Wood with a Spark grip wrap for every player, the eyes are Bone. Each head sheet has one row per player ramp (`content/wizard/staffs/<head>/head@2x.png`).
- The four player base colours (`#3b73c9`, `#d9477a`, `#3f8f4f`, `#8a4fc4`) are the comparison set: any two must differ clearly in hue, and nothing else on screen may use a colour close to one of them.
- Floors use only Stone base and light, with Stone shadow only for small inner details. Players and enemies don't use Stone shadow for their own surfaces, so a silhouette doesn't melt into the floor.

## The living staffs

Every character is a body and a face (living staffs H2–H5; the code is `gameplay/actor/face.gd`):

- **The face** is two floating eyes and two floating brows on their own layers (`art/faces/eyes@2x.svg`, `art/faces/brows@2x.svg`, 16×8 world units a frame, 32×16 art pixels at 2x detail; drawn by `tools/face_art.py`), drawn over the body. No mouth. The game moves them: the eyes trail the body by a tenth of a second and the brows trail the eyes, at most 2 px each; a cast pops them up; blinks, glances and the odd raised brow are timed per character. Draw no face into a body sprite. A boss may wear a face of its own (boss plan OB9): its own eye and brow sheets in its folder, in the same layout (ten eye columns, nine looks and the blink; a brow a mood; a row a look of the face) at a frame size of its own, the eyes drawn pale for the game to tint.
- **Brows carry the mood**, five shapes: neutral, raised, angry, furious, worried, 4 px each, 3 to 5 rows above the eyes. **Eyes carry the personality and the look**: round (the Optimist), round with a sparkle (the Show-off), heavy-lidded (the Dozer), narrow (the Sergeant); the pupils look one of nine ways.
- **A player's body** is a head sheet: 48×48 frames, 16 columns of directions (clockwise from pointing right, 22.5° apart, each drawn, never rotated by the game, so the light stays top-left and an upright head stays upright), 4 rows of player ramps, the grip at (24, 27). The face sits 8 px above the grip ("Close"). It floats and bobs; it has no walk frames.
- **A stray's body** is one 32×32 frame with no player colour; its eyes are drawn white and tinted in its element's light shade (a glow), with slit pupils, and its brows rest angry and turn furious while it winds up. Strays hop (the game lifts the sprite); players float, so the two read apart by motion.
- **Silhouettes:** each head is its own shape family (spiral, spikes, solid curve, arrowhead), so four players read apart in black.

## Animation frame counts

One animation is one horizontal strip: frame 1 at the left, each frame 32 px wide (64 at 2x detail), so a 6-frame animation is 192×32 (384×64 at 2x). File names end with the animation: `idle.png`, `walk.png`. Playback speed is set in the scene, not in the art. A pose that holds needs no more frames (held frames cost nothing), but a change of look is never a single frame ("Smooth", below).

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

The table is a guide, and the living staffs need few of it: a player's body has no strips (a frame per direction, moved by the game) and a stray is one frame; the face's motion is code. The real values are the constants in `gameplay/player/staff_look.gd`, `gameplay/actor/face.gd` and `gameplay/ai/creature_look.gd`.

A single still image has 1 frame and is a plain 32×32 file (64×64 at 2x, `<name>@2x`).

## Smooth

Everything should look smooth (the owner, 2026-11-16). Nothing on screen changes its look in one jump:

- **A change plays the frames between the two looks.** Grass catching fire, burning down, going out and growing back; a door opening; a prop breaking; a state of anything drawn. A change of look not in the table above has at least 3 frames, more when it takes longer than a quarter of a second (about one frame each 0.1 to 0.2 s).
- **Stages hand over.** Each stage's last frame is the next stage's first look (or one step from it), so a chain of stages reads as one movement: the grass's burning ends as short flames, its smouldering starts from those stubs and ends as the ash.
- **A thing keeps its own shape through a change.** A look drawn in variants (six grass tufts) has each variant's own strip for each stage, in the same order, so a tuft burns as itself rather than swapping to another tuft's flames.
- **Pixels stay hard.** Smooth is in-between frames and motion by whole pixels, never sub-pixel blur, cross-fades or partial transparency ("Light and shading": no gradients, no dithering for smooth fades). The floor mist is an exception too ("Light and shading"). The spell light is worked out on a grid of world cells (8 px by default, gameplay/feel/light_grid.gd) and read a whole cell at a time, then cut into its bands; the mist is worked out a world pixel at a time however big the picture is, each world pixel whole. Neither is blurred up. **One jump the owner accepts** (2026-11-22, #907): the split screen's cheaper light, when the frame-time budget takes it or gives it back (seconds apart at the least, `SplitBudget`), changes every view's light cells from 8 to 16 px (and back) in one frame. **And a second** (2026-11-22, the "Effects" setting): a change of the effects' row (Low, Medium, High; chosen in the menu or by Auto as the frames run slow or fast, a few seconds apart at the least, gameplay/feel/effects_auto.gd) changes the light's cells, the mist's layers and the air's share in one frame.
- **The default zoom 1 and whole pixels** (the owner's choice of 2026-11-25, on ART0: "rest the cameras at zoom 1.0", so every art pixel shows; it was 0.8 from 2026-11-23, docs/milestones/connected-biomes.md, "A steady camera"): at rest every art pixel is whole picture pixels (two each way for art not yet redrawn, one for art at 2x). Only while the camera zooms out to hold a spread party (down to 0.5) is the world resampled into the picture, art at 2x losing some of its pixels, which ones shifting as the camera eases ("The picture and the art's detail"). "Whole pixels" and "motion by whole pixels" in this guide hold for the art as it is drawn, the HUD and whatever is drawn in layout pixels (the edge markers), and the world at rest.
- **Code that swaps a look** (a state's frames, a sprite's texture, a node shown or hidden) plays a change's frames or eases it; a test or the reviewer names one that pops. Ground cover does this by data: `CoverState.animation_frames`, `animation_fps`, `animation_loops` (content/cover/README.md). A prop does it by its looks' layers: a strip played once as its state is entered, then held or looped (`PropLayer.loop_from`, content/props/README.md; the crypt pillar's crumbles, the crypt gate's opening).

The art only shows timing; it doesn't set it. The telegraph's length and the moment damage lands are set by the AI and the scene (the telegraph frames can be held longer there; 0.25 s is only the shortest), never by the animation.

## Sound

The game's sound is synthesised from code in a modern style (the owner, 2026-11-18; docs/milestones/sound.md): filtered noise, roaring fire with crackles, bell-like inharmonic glass, FM tones, a little room reverb, all of it kept low (below: deep, never piercing). It is never thin 8-bit beeps, and never imitates a recording of a real thing.

- **Format:** `.ogg` (Vorbis), 44.1 kHz, mono for effects and UI, mono or stereo for music, at most 5 MB.
- **No clicks:** every sound starts and ends at silence (a 2 ms ramp at least). A loop folds its tail over its start, and a duck ramps.
- **Pleasant on the hundredth listen.** A sound heard every few seconds (cast, hit) is short, soft at the top and has its variants. It never sounds like one file four times when four players do the same thing.
- **Deep, never piercing** (the owner, 2026-11-18, after the first listen: "the audio cues are too high which makes them go through and take over too much"). A cue sits low and under the fight: its weight is below about 1 kHz, a ring is a low bell and a hiss is a dull rush. A cast is a soft, muffled pop, like a cork leaving a bottle, each carrier's its own; a hit is like packed snow struck, a soft puff with a faint low bump and a fine dull grain, no ring and no room (the owner, 2026-11-20, after seven rounds of examples; docs/milestones/sound.md, "Hits by carrier"). Sounds heard many times a second sit well under the fight: the `combat` family is at -26 LUFS (it was -20), under the music's loudest moments, and a hit sound that comes again soon plays quieter. Each family has a ceiling for a sound's **top**, its part above the frequency in the table's last column's header, which the bake measures and fails a sound over; the music has none.
- **Each element has a voice,** shared through patches (`audio/patches/`): fire roars and crackles, frost is a low bell of glass, storm is a low gust of wind, lightning is a crackle and a zap, void is a low, hollow swell, water is a soft wash (`fire_roar`, `frost_glass`, `storm_gust` and the others, named by element). A reaction mixes its two elements' voices.

| Family | Loudness (LUFS) | True peak | Variants | Pitch jitter | Volume jitter | Top (above 2 kHz) |
| --- | --- | --- | --- | --- | --- | --- |
| `combat` (cast, hit, small effects) | -26 momentary | -3 dBTP | 4 | ±4% | ±1.5 dB | -10 LU |
| `big` (reactions, deaths, downed, revive) | -17 momentary | -2 dBTP | 3 | ±3% | ±1 dB | -9 LU |
| `boss` (the boss's moves, intro, slams) | -15 momentary | -1 dBTP | 3 | ±2% | ±1 dB | -9 LU |
| `held` (loops) | -24 integrated | -6 dBTP | 1 | none | none | -9 LU |
| `ambience` (a room's accents: drips, gusts, rumbles) | -21 momentary | -6 dBTP | 3 | none | none | -9 LU |
| `ui` | -24 momentary | -6 dBTP | 2 | ±2% | none | -9 LU |
| `music` (all layers together) | -23 integrated | -1 dBTP | 1 | none | none | none |

Momentary is the loudest 400 ms window (most sounds here are shorter than short-term's 3 s); integrated is the whole file, gated (BS.1770). Peaks are held 1 dB under the limit before encoding, as Vorbis can overshoot. The bake places each sound on its family's target (a recipe's `gain`, with a note, places it off it), measuring a loop as it plays round, and fails a variant more than 1 LU from it. The top is the loudness, by the family's measure, of what a sound has above the header's frequency (through a 24 dB an octave high pass), in LU from the whole sound's level: -10 LU is a top 10 LU under the sound, and the bake fails a variant whose top is over its family's (a recipe's `top`, with a note, gives it a ceiling of its own). These numbers are a first tuning; the owner changes them by ear.

## File formats

- Art is `.png` or `.svg` (`AGENTS.md`, hard rule 2), at most 1 MB.
- PNGs are 8-bit with colours exactly as in the palette.
- Godot imports every sprite with **filtering off** (nearest neighbour) so pixel edges stay crisp; set this in the file's `.import`.
- Every asset has an entry in `art/manifest.json`, or in an `assets.json` in its content folder, with its origin and tier ([art/README.md](../art/README.md)).

## Placeholder SVGs

Sessions and anyone else without an image editor may write a pixel sprite as an SVG, listed in the manifest with tier `placeholder`. They follow every rule above and these:

- The root element is `<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32" shape-rendering="crispEdges">`. The size is exactly the grid (or a whole multiple), and `shape-rendering="crispEdges"` is always set. Art at 2x detail is `width="64" height="64" viewBox="0 0 64 64"` (or a whole multiple) in a file named `<name>@2x.svg`.
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

- **Font:** one pixel font, set in `hud/theme`, at whole-number sizes only, and one title type beside it for the names of bosses (and later biomes) only: a bitmap face drawn for the game on the pixel grid, `TitleLabel` in `hud/theme/title_theme.tres`, the game's first font file (docs/milestones/boss-intro.md, rule 7). Body text is Bone light on Stone shadow; headings Bone base; warnings Fire light; gold and pickups Spark light. No other text colours.
- **Panels:** a 1 px Outline border, Stone shadow fill, a Stone light top and left inner edge (3 shades at most). Corners are cut by one pixel, not rounded.
- **Player panels:** the border and name tab use that player's ramp (base fill, light top-left edge, shadow bottom-right edge). Next to the colour sit the player's number (1–4) and a shape, so colour is never the only signal. Health is a thin line of a strong red, `#e01a2b`, the one UI colour outside the palette, by the owner's word ("a very red line", 2026-11-19); mana is a thin line of Mana light under each staff's row; both on a dark trough, and neither uses a player colour (`hud/widgets/meter_line.gd`).
- **Icons:** 16×16 for spells and relics in the overlay, 8×8 for status marks (32×32 and 16×16 at 2x detail, `@2x`), with the 1 px outline and at most 3 shades per material.
- The HUD is laid out at the **640×360 layout size** and drawn at the picture's scale (2 in the 1280×720 picture; "The picture and the art's detail"). Everything snaps to whole layout pixels, art at 2x to whole picture pixels, and four panels stay readable there. Text is drawn at whole-number sizes.

## Golden examples

The pieces the Style Guide page shows as "this is the look", listed with what each one shows in [art/kit/golden.json](../art/kit/golden.json). The player and the stray are the living staffs (body and face as the game layers them); the others are the best placeholder art so far and are redrawn in that style over later milestones, when they move here. Copy their approach, not their pixels.

| Kind | File | What to learn from it |
| --- | --- | --- |
| Player character | `art/kit/golden_staff@2x.svg` (the curl's head sheet at 2x detail, player 1, pointing up and to the right, under the Optimist's eyes and neutral brows at 2x; the first art redrawn at 64×64) | A floating staff: a Wood shaft with a Spark grip wrap, a one-art-pixel outline, the player colour on the head only, the face 8 world units (16 art pixels) above the grip and drawn over the staff; the pupils look where it points |
| Enemy | `art/kit/golden_stray.svg` (the Cinder Rod, its 1x body as it was, with its face; the body itself is `content/enemies/ember_imp/idle@2x.svg` since ART1) | A stray: a charred rod with a burning crown, no player colour, eyes glowing in its element's light shade with slit pupils, angry brows |
| Raised tile | `art/tilesets/crypt/wall.svg` | Lit top and left edge, shaded bottom and right edge |
| Flat tile | `art/tilesets/crypt/floor.svg` | Stone base, a few inner details, nothing on the outer edge |
| Projectile | `art/vfx/bolt.svg` | Neutral Bone streak with a Spark core (the owner tints the Bone, the element colours the core), outlined in its own shadow shade |
| Impact | `art/vfx/hit_spark.svg` | A flat Spark burst, no glow halo |

## The starter kit

The source files are in [art/kit/](../art/kit/README.md): the palette (`spellmerge.gpl.txt` for GIMP-style editors, `palette.hex.txt`), a 32×32 grid, a 64×64 grid for art at 2x detail and an animation strip template as SVG, `golden.json` and the one-page checklist [art/kit/checklist.md](../art/kit/checklist.md). The palette files and the checklist copy this document; when you change the palette table, frame counts or the checklist below, change them too.

## Checklist

Before an art PR is opened, by the bot or a commissioned artist:

- [ ] 64×64 per frame at 2x detail, named `<name>@2x` (or 32×32 for art not yet redrawn; or a whole multiple); strips have the frame count from the table.
- [ ] Only palette colours; no gradients, no antialiasing, no partial transparency.
- [ ] 1 px outline, closed; light from the top-left; at most 3 shades per material.
- [ ] Reads as a silhouette at its size in the world, and next to four players; looked at at zoom 1 and zoomed out (0.8, 0.5), where a one-pixel line at 2x can break.
- [ ] No baked drop shadow, no glow halo; the background is fully transparent (tiles are fully opaque).
- [ ] Floors are flat; walls and raised props have the lit top-left edge. Tiles repeat without a seam.
- [ ] Imports with filtering off.
- [ ] Manifest entry with the honest origin (and tool and prompt for AI).
- [ ] Smooth: a change of look has the frames between (at least 3), each stage ends where the next begins, and a variant keeps its own shape ("Smooth").
- [ ] A screenshot of it in the game in the PR.

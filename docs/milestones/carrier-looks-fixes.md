# Carrier looks: fixes after #642

**Status: done (2026-11-10): phases 1 to 4 (#659, #660, #661, phase 4's PR). Planned 2026-11-09 from a review of #642 the day it merged.** The owner asked for #642 to be merged as it was, then reviewed "with good software architecture and low coupling", and the fixes saved as a plan to follow. #642 gave five carriers new looks on the owner's picks (rune C hovering seal, pool B+ glowing mire, swap B chasing pair, wall H rising motes, portal I mote rift), and still cards real motes (`gameplay/feel/still_motes.gd`). The owner's rule since: **motes for everything we can**, they are the world's magic building blocks.

Phases 1 and 2 are the architecture fixes and come first: they change how the rest are built. Each phase is one PR.

**Phase 1 done (2026-11-09, `owner/carrier-looks-p1`).** As planned, with these choices: the manager fills the view by reading back the rows it drew (`read_still_rows`, beside `_write_quad`), so the native kernel needs no change (its rows are the same to the bit, `test_native_kernel`) and a frame costs nothing more for a body nobody watches; bodies are watched by number (`watch_body`, both batches of the pair; the view names its body and ramp half); `body_of` answers 0 for none, the manager's "no body" everywhere else, not -1; a still card's look is shaped by `look_shape` (its hit size as drawn, `STILL_HIT` of its quad, now one constant in the manager and the include) and comes and goes by `look_open` and `look_fade`, handed to its shader as the uniforms `look_shape` and `look_clock` (`set_body_shape`; Spells shapes a body wherever it numbers one, at start or at a launch, from the card's `CardLook`, which Feel's motes read too, and no default is copied: a body no card shaped keeps its shader's own; cards sharing a shader must share these, checked by `test_card_looks`); the pool's shader draws its own splash and drying, so it reads only the shape. The include's `STILL_*`, `TRACE_*` and `STILL_HIT` are compared with the manager's by `test_projectile_looks`.

## What the review found

### Coupling (the main finding)

1. **Feel reads the projectile manager's raw draw rows.** `still_motes.gd` takes each batch's upload buffer (`rows_drawn`) and decodes it by hand: float indices 3, 7, 8 to 15 of `DRAW_STRIDE`, the ramp and look bits packed in the colour bytes, the kind and still clock packed in the custom alpha (`strength()` undoes `_write_quad`'s `1 - (kind + code) / 16`). That is the manager's private, GPU-facing layout. If a row changes (a new float, the colour packing, the kernel's writer), the motes break and no test of the manager notices. Feel should read still shots through a typed view, not a buffer.
2. **The same numbers live in four places.** `STILL_START`, `STILL_END`, `TRACE_FROM`, `TRACE_SPAN` are in `projectile_manager.gd`, `native/src/shot_kernel.cpp` and `shot_palette.gdshaderinc`. A pool's oval and a wall's seam (`HIT` 0.15, `OVAL` 1.3 x 0.75, `ROW_SPAN`, `ROW_FOOT`) and the come and go (`OPEN` 0.3, `FADE` 0.8) are copied between `still_motes.gd` and `pool.gdshader` / `stone.gdshader`, by comment only. The manager's two copies are compared by `test_native_kernel`. Nothing compares the shader's, nor the shape numbers. Change one and the motes leave from the wrong place, silently.
3. **A view-side helper numbers bodies.** `still_motes.attach` calls `projectiles.register_body(shader, MESH_QUAD)` to learn a card's batch number. Numbering is a write on the manager (it makes batches the first time), done here only as a lookup. It should be a read (`body_of(shader, mesh)`, -1 for none), or Spells, which numbers the bodies already, should hand the numbers out.
4. **Duck-typed calls by name across areas.** `still_motes` calls `spells.call(&"still_mote_cards")` and `spells.call(&"look_of", ...)` behind `has_method`; `portal_rings.gd` calls `_portals.call("portal_infusions", at)` and `call("portal_seconds", at)` on the carrier object. A misspelt name fails quietly at run time. Feel already holds Spells typed elsewhere; these should be typed calls (or an interface script) so the compiler checks them.
5. **The portal's look is not the card's.** The rest of the carriers' looks moved into their card folders (card-looks.md: "every carrier's look in its own folder"); #642 rewrote the portal's look inside `gameplay/feel/portal_rings.gd`, its carrier still `LOOK_NONE`, with its colours worked out from the infusion tints rather than the palette (`palette_of`) every other look uses, and its "motes" drawn by `_draw()` as pixels, not by the mote system. It reads the carrier's rows (`portal_seconds`, `portal_infusions`, new in #642) straight from `CarrierPortal`. That is the old pattern the card-looks work removed elsewhere.
6. **A shared read-only look is mutated.** `Spells._remember_look` builds a `CardLook` with `CardLook.of(...)` and then sets `motes`, `mote_rate`, `motes_from` on it. `CardLook` is documented as shared and read-only; it should be made whole in one place (`CardLook.from_card(card)`).
7. **One meaning, three spellings.** `CarrierCard.look_motes_from` is an `@export_enum("area", "row")` int, `CardLook` documents "0 the oval, 1 along a row", `still_motes` has its own `FROM_AREA`/`FROM_ROW`, and the field's doc names `LOOK_MOTES_*` constants that do not exist.

### What is fine

- Layering of the simulation: everything new is view only. `_watched`, the signal and the still clock are in the manager's `VIEW`; still motes keep nothing the simulation reads, and their dice are their own (Feel's RNG). The native kernel's `still_code` matches the GDScript's (tested). Walls are drawn by the GDScript only, so the quad turn needs no kernel change.
- No area calls another's gameplay: Feel only draws.
- Card data stays data: a still card naming a mote kind and a rate is the right direction.

### Looks still short of the picks (the PR's own list)

- The wall's stream doesn't part where a shot hits it, and its motes read as one bright bar, not the shield's distinct motes.
- The pool's outline is lumpier than the mockup's smooth wobble.
- The rune's dripping light and rising motes, and the portal's lips and drift, are drawn pixels, not real motes.
- The rune's go-off slam-down is missing (the `rune_burst` cue as before).
- Not measured on a real GPU: the rune's fragment stage grew (two mote loops), the pool keeps a 12-particle and a 9-drop loop.
- `docs/milestones/card-looks.md` still says the swap keeps the plain head; `shot_portal_rifts` shows a run's telegraphs and "Wave 1" banner over the rifts.

## Phase 1: still shots read through a view, numbers in one place

- **A typed view of still shots, in core.** The projectile manager offers, per watched body, what a viewer may know of each still shot drawn this frame: place, hit size, which way its row runs, ramp and look bits, core colour, and its still clock as two numbers (seconds since, seconds left). One small class, `StillShotView` (core/projectiles), filled where the rows are written (`_write_stones`) for watched bodies only, so it costs nothing when no card asks. The signal hands that view, not the buffer. `still_motes.gd` reads only it: no stride, no byte packing, no alpha decoding.
- **Decoding in one place.** If a raw row must be read anywhere (tests), the manager owns the decoding (`ProjectileManager.read_row(rows, i) -> StillShotView` or static helpers beside `_write_quad`), next to the code that writes it.
- **The shape of a card's motes on the card.** Replace the copied `HIT`/`OVAL`/`ROW_*` numbers with data the card gives once: where its motes leave from, in its hit size's units (an oval's half sizes, or a row's span and foot). The pool's and wall's shaders get the same numbers as uniforms set from the card (`ShaderMaterial` per body already exists), so the shader and the motes read one source. The come and go (`OPEN`, `FADE`) likewise.
- **A test that the shader include agrees.** `test_projectile_looks` reads `shot_palette.gdshaderinc`'s text (it already reads shader text for its texelFetch rule) and checks `STILL_START`, `STILL_END`, `TRACE_FROM`, `TRACE_SPAN` equal the manager's. Same for any constant still copied after this phase.
- **Bodies are looked up, not made.** `ProjectileManager.body_of(shader, mesh) -> int` (read only, -1 for none). `still_motes.attach` uses it, or takes the batch numbers from Spells, which numbered them (`Spells.register_bodies`).
- **`CardLook.from_card(card)`** makes the whole look, motes included; `_remember_look` uses it and sets nothing after.
- **One name for where motes leave from:** constants on `CarrierCard` (`LOOK_MOTES_AREA`, `LOOK_MOTES_ROW`) used by `CardLook` and `still_motes`; fix the field doc.
- **Typed calls:** `still_motes.attach(projectiles: ProjectileManager, spells: Spells)` with typed calls (Spells is a class Feel already preloads or can), no `call(&"...")`.
- Tests: `test_still_motes` drives the view, not a hand-built buffer; a test that a watched body's view matches what was drawn; a test that an unwatched frame fills no view.
- Size: medium. Native: no (the view is filled by the GDScript writer of still shots; check the kernel's still path, `draw_shots` writes runes too: if a watched card body can be drawn by the kernel, the kernel fills the same view, compared byte for byte).

## Phase 2: the portal's look in its card, its motes real

**Done (2026-11-09, `owner/carrier-looks-p2`).** `Carrier.LOOK_PORTAL`: the portal card names `carriers/portal/portal.gdshader` (the dark lens, its stars drifting through), core's `shot_portal.gdshader` the fallback, both from `shot_portal.gdshaderinc` (a gate's quad: its axes the lens's width and height now, so how open it is is the quad's size; colour the look, `palette_turn` for the infusions, as every other look). The carrier hands its open portals out through one typed read (`CarrierPortal.read_view` into a `PortalView`: caster, look, core, infusions, seconds open and left, and each gate's place, way, radius and mouth). Feel's `portal_look.gd` (was `portal_rings.gd`) draws every lens in one batch by the one shader `look_shaders(LOOK_PORTAL)` lists (as Entities' orbs; warned if more), and the lips, loose motes and the line to each exit are real `ward` motes placed each frame by `placed_motes.gd`, which the shield's shell (`barriers.gd`) now places its motes by too (its own row writing gone). Not done: the lips' motes are placed, not kept and eased (`barriers.gd`'s way), since a lip has no gaps to close; the stars in the lens stay pixels of the shader (a star a mote would be a mote a pixel of every lens).

- **A drawer for the portal, the card-looks way.** `CarrierPortal.look_drawer()` answers a drawer of its own (Feel's portal drawer), and the portal card names its look (`look_shader` in `content/spells/carriers/portal/`: the dark lens with mote stars, opening tall then wide and closing back). The portal drawer asks `Spells.look_of(&"portal", drawer)` and uses the palette (`palette_of`) like every other look, so infusions show the same way everywhere.
- **The carrier hands out its mouths through one typed read.** Instead of Feel calling five `portal_*` methods by name, the carrier offers a typed snapshot of its open mouths (place, way, seconds since, seconds left, gates, look bits), as the beam offers its rows (`CarrierBeam.of(spells)`). Feel reads that.
- **The lips and the drift are real motes.** Positioned mote rows each frame, the way `barriers.gd` lays the shield's shell (a ring of kept motes eased to even spacing): two lips up one side and down the other, a lip per infusion, loose motes spiralling into the way in and thrown out of the way out. If phase 1's view is general enough (a placed thing with a shape and a clock), the portal's mouths can feed the same still-motes helper.
- Size: medium. Native: no.

## Phase 3: the looks finished

**Done (2026-11-09, `owner/carrier-looks-p3`).** A card's motes are a list of `StillMoteSource` (core/base: kind, rate, from area, row, rim or middle of its `look_shape`, height, start and stop on the still clock, spacing), replacing `look_motes`/`look_mote_rate`/`look_motes_from`; `still_motes.gd` has no case per carrier. **Wall** (owner: the shield's spacing): a new `seam` kind (the ward's twinkle, less glow, no wobble) at 7 a second a piece, its places on a 3.4 px world grid so the pieces line up; a strike on no target (`projectile_impact`, a wall's or a beam's) parts the streams within 5 px for 0.5 s and knocks 6 motes out. **Rune**: the drips (`drip`, a new falling kind, shown at the crystal's foot: `Motes.throw_part` takes a birth height) and the motes rising off its ring are its card's sources from its arming (start 1 s); the shader's two loops are gone and its ring reads `look_shape`; the slam-down (owner: yes) is a `fall` column first in `rune_burst`. **Pool**: its rim is one pixel all round (each neighbour judged at its own place on the wobble, as the mockup's mask; the outline formula already was the mockup's); its 9-drop loop is gone, its splash a `spark` source off its rim that stops at 0.3 s (a pool tells no `form_shown`, so a shown cue would never play). Kept: the 12-particle card-particle loop, the still shaders' contract (`test_card_looks`); turning still shots' card particles into motes is a change to every still shader at once.
Review (same day): a strike only finds still shots drawn in the last frame (a wall that ended no longer parts or sheds); every stream comes in by the card's `look_open`, with no case for one that stops (the splash's rate set for it); the rune's drip height is checked against its shader's crystal (`HOVER`, `DRIP_FROM`, `SCALE_PER_ZOOM`, `GRID`; test_rune).

- **Wall:** thinner, distinct motes like the shield's (fewer a second, the ward kind's twinkle, less glow per mote); the stream parts where a shot hits: still motes listen to the hit through an event Feel already gets (`shot_blocked` / the wall's impact), hold back births within a few pixels of the hit for half a second and knock the motes there outward, as the shield shell does. No hit data in the rows.
- **Rune:** the drips and the armed sparkle become real motes: the card's mote source gains "from above its middle, only once armed" (a height and a start time on the card's mote data, read from the still clock). The crystal's slam-down on going off as part of the `rune_burst` cue, if the owner still wants it.
- **Pool:** the outline back to the mockup's smooth wobble (three sines, no hash in the edge), and the 12-particle and 9-drop loops replaced by real motes where they can be, which also shrinks its fragment stage.
- **Card mote sources as data, not an enum.** If phase 3 needs a third and fourth "from" (above, after arming), make a card's motes a small resource (`StillMoteSource`: kind, rate, from shape, height, start and end on the still clock) and let a card list several (the rune: drips and sparkle). The helper then has no case per carrier.
- Size: medium. Native: no.

## Phase 4: checks and docs

**Done (2026-11-10, `owner/carrier-looks-p4`).** Measured on the owner's GPU (`webstorm`'s steps with the GL probe in the page, one pair of runs: main before phase 1, `917243e4`, and after phase 3, `5a53affb`; a storm of `fire,split,split,split,pool,frost,split,split,split,wall` for 10 s, cap 1000, native on):
- **Compiles** (every program over 100 ms): the rune's 369/358 ms became 292/327 ms (its two mote loops gone); the pool's (~360 ms) and the wall's (~210/335 ms) are as they were; the portal's two new shaders (the card's and the plain fallback, both warmed) take 155 to 253 ms each, 0.8 s more behind the loading screen; the slowest is still the flash shader (1.5 to 1.7 s, unchanged). Nothing near the D3D danger (`webgl-d3d-shaders`).
- **Frames:** 6.36 ms avg, 7.70 p95 before; 7.89 ms avg, 9.90 p95 after: the scripts' share grew 3.67 to 5.05 ms a frame. Headless, the same storm showed it in the drawing (`update_draw` +0.5 ms, run twice a frame by the storm): still motes' `give_off` read every still shot every frame (0.9 ms a call over ~230 wall and pool pieces) though at 7 motes a second a piece only one in eight gives off a frame. **Fixed:** a stream now picks as many shots as the whole batch would give off at full strength this frame and keeps each pick as often as that shot's strength says (the same motes a shot on average; the work follows the motes, not the shots), and `StillShotView` reads its rows lazily, only while it is handed out (`open`, `close`; the manager's `row_*` readers beside `_write_quad`), so a shot that gives off nothing is never decoded; a strike waits for the next drawing to meet the shot it struck (nothing kept between frames), and the parting check is skipped while nothing parts. Headless after (two alternated pairs): process scripts 3.40/3.50 ms before phase 1, 3.62/3.50 ms now; `update_draw` +0.2 to 0.3 ms.
- **Sheet:** `shot_portal_rifts` stages its portals in an empty room (seated wizards casting through Spells, a laid floor, no run).
- **Docs:** card-looks.md's carrier table (the swap's and the portal's own looks).

- **Measure on a real GPU** with the owner's harness (`~/spellmerge-gpu-harness/webstorm.sh`, Windows Chrome): first-room compile time of the rune, pool, swap and wall shaders, and frame time with many pools and walls giving off motes. Fix whatever it shows.
- **A clean portal sheet:** `shot_portal_rifts` stages its portals in an empty room (no run, no waves, no telegraphs), with 1, 2 and 4 infusions, like `shot_carrier_palettes`.
- **Docs:** card-looks.md's swap row, core/README.md and gameplay/feel/README.md for the view, the card's mote data and the portal drawer; content/motes/README.md for `rising`.
- Size: small.

## Order, size, risk

| Phase | Size | Native | Risk |
| --- | --- | --- | --- |
| 1 still shots through a view, numbers in one place | medium | maybe (only if the kernel draws watched still bodies) | the draw loop's cost when a card is watched (fill the view only for watched bodies); the shader uniforms per body |
| 2 portal look in its card, real motes | medium | no | the portal drawer becoming a card look; motes per mouth each frame (budget with the mote cap) |
| 3 looks finished | medium | no | mote counts per wall and pool against the mote cap; the wall's hit event reaching the right piece |
| 4 checks, docs | small | no | what the GPU measurement shows |

## Questions for the owner

1. **The rune's slam-down when it goes off:** still wanted? *Recommended: yes, as part of its burst cue (data).*
2. **Wall density:** match the shield's spacing (a mote every ~3 px along the seam, rising), or keep it thicker so it reads as a solid wall? *Recommended: the shield's spacing, two or three rows deep.*
3. **Portal look in its card folder** (phase 2) even though it means a new drawer for Feel? *Recommended: yes, so every carrier's look lives with its card.*

**Answers (the owner, 2026-11-09):** 1. the rune's slam-down: yes, as part of its burst cue. 2. wall density: the shield's spacing. 3. the portal's look in its card: built so in phase 2.

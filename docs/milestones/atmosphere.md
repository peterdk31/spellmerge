# Atmosphere: more layers in Feel

**Status: the owner's direction of 2026-11-18.** "The atmosphere in the game is just not there yet. I think it needs some more layers in Feel to really make it look good." The owner picked every layer proposed (darker tinted rooms, lit dust, shadows, and shafts, mist, sound and reactions), with **soft mist allowed** as an exception to docs/STYLE.md's no-fades rule (like the shots' glow), and asked for this plan, then phase A built.

Like the spell spectacle, this changes no damage, hit, rule or card behaviour. Everything here is drawn or heard, and all of it is Feel's (view only, outside the simulation).

## What is wrong today

1. **The dark is barely there.** Every crypt room's `ambient` is 0.8 and the hub's 1.0 (crypt rework, rule 6), so spell and torch light have little dark to stand out against: a torch's pool is a small step up from a floor that is nearly as bright.
2. **The dark has no colour.** `ambient` darkens evenly. Warm torches against a cool dark ("Warm against cold", crypt-rework.md) is drawn in the art only, so it is lost where the light is the game's.
3. **Darker would hurt reading.** The apply rect sits above the bodies (spell_light.gd), so a darker room darkens the wizards with it, against rule 6 ("readable first").
4. **The air is empty.** Motes come from spells, props and pit edges. Nothing drifts in the room's air, so the light has nothing to fall on between the floor and the camera.
5. **Light passes through everything.** A torch lights the far side of a pillar, and no body casts a shadow, so the room reads flat.
6. **The room is silent but for the fight and the music,** and its things (torches, cover) take no notice of the spells going past.

## Rules

1. **View only.** No simulation state, no sim clock, nothing a snapshot holds. Feel's clock and real time are fine (it is drawing).
2. **Readable first, still.** The crypt rework's rule 6 stands: wizards, enemies and shots are the brightest, most saturated things on screen. A layer that makes a fight harder to read is turned down until it does not. Each phase checks a fight's screenshot (`shot_rooms.gd`'s `room_<id>_fight`) with spell light on and off.
3. **Data, not code, for what a room looks like.** A room's dark, its dust and its mist are fields on `RoomBase` (or mote kinds and sources), with defaults that leave a room as it is today. Only a new kind of layer is engine work.
4. **Each layer has its setting's off.** A layer that costs GPU time follows the spell light's or the motes' setting (off: not made), so the web build on a slow machine can turn it away.
5. **No per-frame allocations,** and lights through the spell light's batches (one row each), never a node per light.
6. **Smooth** (docs/STYLE.md): nothing pops. A light that comes or goes eases in over frames; a layer turned on by a room comes with the room.
7. **Soft mist is an exception** (the owner, 2026-11-18), written into docs/STYLE.md as the shots' glow is: the mist alone may be soft and see-through. Everything else keeps the pixel rules.

## Phases

Each is one PR with its tests, `tools/check.sh` and the suite passing, and a review.

| # | What | Size |
|---|---|---|
| A | **Darker, tinted rooms, and wizards that carry light.** `RoomBase.shade`, the colour of a room's dark (white by default: as today), multiplied into `ambient` in `light_apply.gdshader`. Every seat's wizard carries a small light at its staff tip in its hat's light shade (`carried_lights.gd`, one spot row a seat each frame), so the players are lit pools in the dark (rule 2). The crypt rooms darker (`ambient` 0.65) and cool (`shade` a blue-violet), rule 6's numbers updated | small |
| B | **Lit dust in the air.** A room-wide mote source (`RoomBase.air`: a mote kind, a rate) of slow drifting specks drawn only where the light falls: dim in the dark, bright in a torch's pool and when a fireball passes. Needs the motes' shader to read the light buffer (the buffer is the spell light's; a mote kind says `lit_only`) | medium |
| C | **Shadows.** (1) Light blocked by walls and props that block (the light buffer drawn with a mask of the room's blocking cells, in bands). (2) A body's hard shadow, a short flat shape away from the brightest light near it, under the body. Each is a part of its own, measured against the shot budget in `tests/benchmark` | large |
| D | **The room's sound.** A loop a room or a biome names (`RoomBase.ambience`: drips and a far rumble in the crypt, wind and the coast at the hub), under the music, faded in and out with the room (Feel's `sounds.gd`) | small |
| E | **A world that notices.** A torch's light ducks and leans when a shot passes close (its spot row's strength), cover sways in a blast's push (the cover's wind, Feel's), the existing shafts' dust stirred by a shot through them | medium |
| F | **Soft mist.** A floor layer of slow soft mist a room names (`RoomBase.mist`: its colour, how thick, how high), drawn under the bodies, pushed aside by shots and bodies (a small field Feel steps, as cover's bend), lit by the light buffer | medium |

**Light shafts are already built** (`content/rooms/decor/beam.tscn`, crypt rework rule 6, its dust falling). The boss hall's was taken out by the owner (2026-11-17: "It is not pretty"), so no phase adds more; E only makes the existing ones react.

## Phase A: as built

- **`RoomBase.shade`** (core/base/room_base.gd): the colour of the room's dark, white by default. Where nothing lights it a pixel is its art times `ambient` times `shade`; light adds as before. Feel's spectacle hands it to the spell light with the ambient (`SpellLight.set_ambient(ambient, shade)`); the apply shader draws nothing where nothing is lit and the dark is white at 1.0, as before.
- **Carried lights** (`gameplay/feel/carried_lights.gd`): each frame, every seat's wizard in the tree gives one light row at its staff tip (`Actor.muzzle_position`), in its ramp's light shade (`ProjectileManager.ramp_light`), reaching CARRIED_REACH px (its radius), CARRIED_STRENGTH bright, drawn in the spell light's batch for them (`SpellLight.light_carried`). While a seat possesses another body the light goes with the body it drives (`Actors.shown_of_seat`), still in the seat's hat colour. **It never pops:** its strength eases over EASE_SECONDS (9 frames) to half while downed, out as the body falls into a hole (`fall_share`), in as a body comes, and out where it last stood when its body is gone. Only while spell light is on, as every light.
- **The crypt:** each crypt room `ambient` 0.65 and `shade` a cool blue `Color(0.82, 0.88, 1)`, checked by `room_scan.gd` (`CRYPT_AMBIENT`, `CRYPT_SHADE`; rule 6, updated in crypt-rework.md). The candles light in Fire's light shade (`light_tint` `#ffa23c` on `content/rooms/crypt/decals/candles.tscn`): their flame art's lightest colour is Bone light, nearly white, so they lit white against the cool dark. The torch decal keeps its art's colour (no room places it).
- **Checked:** `shot_rooms.gd`'s `room_<id>_fight` shots before and after, every crypt room: darker and cooler, the candles' pools warm, each wizard in a pool of its hat's colour, the enemies still clear of the floor.

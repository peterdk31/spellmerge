# Props: things in the world that stand, block, take hits, react and give off motes

**Status (2026-11-10): the plan, written with the owner in an owner session; awaiting the owner's approval; it runs beside the online lobby (the owner, 2026-11-10: "Run beside it").** Asked by the owner after the hub (online lobby L1), on the hub's art: "we need to be able to make a ton of new 'assets' like the stone, with motes coming off almost everything. How could a system like that be made?" Then: "Props can block movement and be hit and props like a barrel will explode if hit by the right element - configurable." On a separate table of props: "This sound like coding 90% of an actor. Why not just use an actor, but maybe make it cheaper by not having a controller attached, which means no movement logic?" On possessing a prop: "Possess would actually be cool. So keep it." On several reactions to one hit: "it should be able to fire several I think. Not really sure though."

The steps are **W1 to W8** (W for the world's things). Each is one PR, in order.

## What the players see

- Rooms full of **things**: barrels, crates, braziers, crystals, urns, the hub's teleporter stone and altar. Almost all of them give off motes: embers off a brazier, glimmers off a crystal's facets, dust off a cracked urn, sparks running down a lit barrel's fuse.
- **Some block** wizards, enemies and shots, as walls do. Some can be walked over (a rune slab, the teleporter stone).
- **Some take hits** and **react**: fire on a barrel lights its fuse, and a second later it explodes and the blast hurts **everyone** nearby, wizards, enemies and other barrels, so barrels set each other off. Shooting a lit barrel makes it explode at once. Frost then fire cracks a stone urn. A crate breaks into rubble that no longer blocks.
- **Possess works on props.** A possessed barrel can't walk, but its buttons are its reactions: press, and it blows (taking the possession with it).

## Owner decisions (2026-11-10)

1. **A prop is an actor with no controller** (the owner, above). Health, the hurt circle, statuses, Combat's reactions, possession and casting are the kit's, with no second kind of body. What makes it cheap is general engine work (W2), not a separate table.
2. **A reaction casts spell cards, and the prop is the caster.** An explosion, a frost burst, a poison pool are cards (`blast` + `fire`), so combos and infusions work and chain reactions follow from the core rule: the payload's caster is the shot that fired it, here the prop (the owner's "one core rule, no special cases", 2026-10-27; docs/DECISIONS.md, "The caster kit is one implementation").
3. **A prop's spells are the world's:** a new team, `TEAM_WORLD`, that every team's shots hit and whose shots hit every team, other props too.
4. **Possess is kept** for props, by the one rule it has today: every hit possesses.
5. **One hit can fire several reactions** (the owner, unsure; the rule below makes it matter little).
6. **Props don't move in this plan.** No knockback on a prop, no rolling barrels. A prop with a Mover can come later.
7. **It runs beside the online lobby** ("Run beside it"), not after L2. W1 to W5 touch the actor kit, Combat and the wall grid, which the netcode stands on, so each of those PRs runs `tools/online_pair.sh` and the determinism tests before it merges, and rebases on whichever lobby PR merged first.
8. **Damage numbers are a node of their own** that any actor can wear: "make this a new node you can attach to an actor (since it is also useful on enemies/allies/bosses)" (W4).
9. **The hub gets a place for every prop** ("This makes it easy for me to test them"): a prop yard that stands every prop there is, found by folder, in place of a gallery room in the sandbox (W7).

## The rule: if it acts it's an actor; if it only stands, it's a prop

A statue that shoots at you is an enemy (an actor with an AI controller and a statue look). A barrel, a crate, a brazier, the teleporter stone are props. A prop is still an actor, so nothing in Combat, Spells or possession needs to know the difference. The training dummy is already close to one: an actor with Health, a Hurtbox and a still AI.

## What a prop is made of

**One content folder each,** like a spell card: `content/props/<id>/` with `<id>.tres` (a `PropBase`), its art, `assets.json` and its own test `test_<id>.gd`. Deleting a prop deletes its folder. Every prop is the same shared scene, `content/props/base/prop.tscn` (an `Actor` with Health, Hurtbox, Caster, `Reactions` and `Footprint`, and no controller), filled in from its `PropBase`, so a new prop is data and art only.

**`PropBase`** (core/base/prop_base.gd):

- `health`, the hurt circle (`radius`, `offset`), `footprint` (cells it blocks, empty for none), `invincible` (the hub's)
- `staffs`: 1 to 4 staffs as an enemy's (`EnemyBase.staffs`), the cards its reactions and a possessor cast. A staff's wind-up is a fuse.
- `states`: a list of `PropState`, the first the one it starts in

**`PropState`:**

- `id` (`idle`, `lit`, `fusing`, `broken`)
- `reactions`: a list of `PropReaction`, in order
- `blocks`, `hittable`: whether its footprint and its hurt circle are on in this state (rubble neither)
- `gone`: a state that frees the actor when entered (a crate that leaves nothing)
- the look: art layers, mote sources and a light spot (W6). View only.

**`PropReaction`:** `when` (a trigger, below), its numbers, and what happens: `cast` (a staff of the prop's, by number, or none) and `then` (a state id, or none).

### Triggers (W5)

| `when` | Fires when | Numbers |
|---|---|---|
| `element_hit` | a hit carrying that element lands on it | the element; at least this much damage (0: any) |
| `status` | a status is on it (a fire pool's burn) | the status |
| `reaction` | one of Combat's reactions between statuses happens on it | the reaction |
| `health_below` | its health falls below a share of its most | the share |
| `death` | its health runs out | |
| `entered` | its state was just entered | |
| `cast` | its staff N cast (by a reaction or by whoever possesses it) | the staff |

**Several reactions, one rule:** on a moment (a hit, a tick's statuses, a cast), **every** reaction of the **current state** that matches fires, in the order listed; the **first** of them that names a `then` sets the next state, once, after they all fired. Reactions belong to states, so "only once" is a state change, never a flag: a fusing barrel has no fire reaction, and a broken one none at all.

**Death doesn't free a prop by itself.** A prop whose health runs out runs its `death` reactions; it is freed only when it enters a `gone` state. Without a death row, its health stays empty and it stands (an invincible stone).

### The barrel, written out

```
staffs   1: blast + fire, wind-up 1.0 s (the fuse)    2: blast + fire, no wind-up
idle     element_hit fire     → then fusing
         death                → cast 2, then broken          (shot apart: blows at once)
         cast 2               → then broken                  (possessed: press 2, it blows)
fusing   entered              → cast 1                       (the fuse burns, then it blows)
         death                → cast 2, then broken          (shot while lit: blows now)
         cast 1               → then broken
broken   (rubble: blocks off, hittable off, its own art and smoke motes)
```

A possessed barrel pressing 1 lights its own fuse the long way; pressing 2 blows at once. It needs no code of its own.

## W1: measure first

Before any change: 300 props-to-be (an actor with Health, Hurtbox and a Caster with two staffs, no controller, standing still) in the stress run, on desktop and the web, as `BENCH` lines: the tick's cost, the state hash's cost (`Tick.state_areas()`, whole and in slices), and a snapshot's size and the time to make it and make the game again from it. Then the same after W2. The numbers go in docs/DECISIONS.md and decide whether W2's third item (snapshots) is needed.

**Done when:** the numbers are in, before and after.

## W2: a body that waits costs little (engine, every actor)

General rules, true of any actor, never "if it is a prop":

- **A dormant body isn't stepped.** The Tick steps a body only when it has something to do: a controller, a Mover, a protection counting down, a staff winding up or winding down, a possession, a phase. `Actor.dormant()` says so; anything that wakes one (a hit, a status, a reaction's cast) wakes it for that tick on. A body with no Mover never moves (`move()` returns before the native call).
- **An untouched body hashes as one value** (`func idle() -> bool`, core/sim/README.md, "Made once, or waiting"): full health, its first state, no possession, its pools full, nothing winding up. Statuses live in Combat's rows and are hashed there.
- **Snapshots** (only if W1 says so): a room-placed body that is still idle is made again from the room, not from the snapshot; only the touched ones are saved.

**Tests:** `test_state_declared`, `test_state_walked`, `test_determinism` pass; a dormant body woken by a hit steps that tick and the next; a replay with props played twice agrees; W1's numbers again.

## W3: a prop in the game (engine)

- **`TEAM_WORLD`** in `core/actors`: every team's shots hit it and its shots hit every team. The AI never aims at the world team (it is nobody's foe); it only hits a prop by accident. A later AI step may teach enemies to shoot barrels near wizards.
- **`Footprint`** (`gameplay/actor/footprint.gd`): stamps the prop's cells into the wall grid (`ProjectileManager`, WALL_CELL 8 px, the way a solid shot does with `set_solid`) while its state `blocks`, and takes them out when it stops. Bodies slide along it as along any wall.
- **A shot that meets a prop hits the prop**, not a wall in front of it. Two ways, to settle in W3's code: the cells a prop stamps know their actor (a small map of prop cells beside the byte grid), so a shot ending in one is a hit on that prop; or the hurt circle covers the footprint and the target test runs before the wall test for those cells. Either keeps the native kernels' bit-for-bit twin (native/README.md).
- **Possess on a prop** works by today's rule; tests check it: the driver can't walk, its presses cast the prop's staffs, the prop's death ends the possession and the driver goes home.
- **A caster number for a prop:** its actor id, as for every actor (`Spells.open_caster`).

## W4: damage numbers on any actor (a look)

Today only the sandbox's training dummy shows damage numbers, inside its own look (`DummyLook`, gameplay/ai/dummy_look.gd). They move into a look of their own, **`DamageNumbers`** (`gameplay/actor/damage_numbers.gd`, an `ActorLook`), that any actor's scene can have as a child: a prop, an enemy, an ally, a boss, a wizard.

- What it does is what the dummy's does now: each hit on its actor (`Actor.damaged`, its own hits only) rises from above the actor for a moment, from a small pool of labels, the oldest reused; new numbers written once a frame, nothing allocated per step (the dummy's performance fix of 2026-11-02 kept).
- Its numbers are data on the node: where a number starts (above the actor's hurt circle by default, so it fits any size), how far it rises, how long it shows, how many at once; and whether it shows heals too.
- The colour says what kind of hit it was: the hit's element (its ramp's light shade), white for a plain one, and the heal colour for a heal. A hit that does nothing (invincible, the hub) shows its number struck through or dim, so a test in the hub still reads what it would have done.
- `DummyLook` keeps its damage per second, statuses and last reaction, and wears a `DamageNumbers` for its numbers.
- View only: it is a look, read only, on Feel's clock, never hashed.
- Which actors wear one is each scene's choice: the props' shared scene and the training dummy in this plan. Enemies, allies and bosses wearing one, and a setting to hide them, are the owner's to decide after trying it.

**Tests:** its numbers for hits, heals and an invincible actor; the dummy's numbers as before; `shot_damage_numbers.gd` draws them on a prop, an enemy and a boss-sized actor.

## W5: reactions and states (gameplay)

- `PropBase`, `PropState`, `PropReaction` in core/base, each with `problems()` (an unknown state, element or status, a staff number it has no staff for, a `cast` it can't afford) checked by a test that loads every prop.
- `Reactions` (`gameplay/actor/reactions.gd`), a component: hears the actor's own `damaged` and Combat's statuses and reactions on it, its Caster's `cast_done`, and its state's `entered`; fires by the rule above; sends `prop_state_changed(actor, state)` on the bus for the view and anyone else. A prop's state is its state, hashed and in snapshots.
- **Tests:** the barrel above in all its paths (lit and blown, shot early, shot apart, possessed and pressed), a chain of three barrels, several reactions on one hit, a `gone` state, an invincible prop.

## W6: the look (Feel, view only)

What the owner asked for first: motes off almost everything, as data.

- **`MoteSource`** (core/base/mote_source.gd): one stream of motes. `kind`, `rate`, `ramps`, `reach`, `spread`, `height`, `spacing`, `start`, `stop`, and `from`: a point, a line, an area, a rim, or **a mask**: the lit pixels of an art layer (a crystal's facets, a rune's carvings), read once when the prop is first shown. The art is the emitter, with nothing more to place. The hub's `MoteRim` becomes a `MoteSource` with `from` a line; the still cards' `StillMoteSource` takes its where-from from the same code.
- **A state's look:** its art layers (sprites, whole pixels), its mote sources, a light spot (`light_spot`, as a torch has), and the cue it plays when entered (the stone's `stone_lit`).
- **A layer drawn as standing motes:** every lit pixel of the layer a standing mote (`placed_motes.gd`, as a barrier's shell), so lit carvings twinkle and cool as magic, not as a flat sprite. Used sparingly.
- **`prop_motes.gd`** in Feel, replacing `rim_motes.gd`: reads each prop's look when the room is entered, gives off each source's owed motes each frame into the shared pool as motes of many a frame (`often`: they give way to hits and moments first), only for props in or near the view. The particle setting thins them as every mote. Its dice are its own; nothing in the game reads it.
- **Art from a grid:** the hub's SVGs came from a small generator that turns a grid of characters into pixel rects; it moves into `tools/` (`tools/pixel_grid.py`, with a test), and a `*` in the grid marks a mote point, so a prop's art and its emit points come from one source.

**Tests:** every prop's look loads and its masks aren't empty; `tests/screenshots/shot_props.gd` draws every prop in every state; motes per second of a room full of props, measured with `webstorm.sh` on the owner's GPU.

## W7: the hub on props

The teleporter stone (states `unlit`, `lit`, no footprint, no hurt circle: walked onto) and the altar move onto props; Flow sets the stone's state from `start_stone_changed`, by `prop_state_requested(actor, state)`, a request the prop's `Reactions` applies at its next step. The hub's rim stays a room's `MoteSource`. The hub looks the same or better, and `shot_hub` shows it.

**The prop yard:** a place on the island (`RoomBase.prop_yard`, a rectangle in the hub's `.tres`) where Flow stands **every prop the registry knows**, in rows by id, each in its first state, with room around them to try spells. A new prop's folder is all it takes for it to appear there; the hub is never edited for it. A yard prop that breaks or goes stands again, fresh, a few seconds later (`RoomBase.prop_yard_return`, 10 s), so testing never runs out of barrels. Wizards are invincible in the hub, so a blast still knocks them back and shows its numbers (W4) but takes no health. Yard props are the game's like any (hashed, in a joining machine's snapshot), so online players see the same barrels go up.

## W8: the first props

They appear in the hub's prop yard as they are made (W7). A batch: **barrel** (fire: fuse and blast), **crate** (breaks to rubble), **brazier** (lit by fire, gives light and embers, frost puts it out), **crystal** (glimmers off its facets; lightning makes it pulse a zap at what is near), **urn** (frost then fire cracks it). Each is a folder and its test, with its art in `assets.json`. The owner picks looks from a page before they're drawn in full, as for the tilesets.

## Not in this plan

- Props that move (knockback, rolling barrels), and a prop with a Mover walking while possessed.
- Loot from props (a reaction may only cast cards and change state; drops are M3's).
- An enemy AI that uses props on purpose.
- Props placed by a room generator (M3); here a room lists its props in its `.tres` with their places, as it does dummies (`RoomBase.prop_ids`, `prop_spawns`), with markers in its scene, and a test checks they match.
- Health bars on props: a hit flashes and shows its damage number (W4); a state may show cracks (`health_below`).
- A gallery room in the sandbox: the hub's prop yard is the place to try props (owner, 2026-11-10).

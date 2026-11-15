# The Old Broom: the first boss

**Status (2026-11-15): planned with the owner in an owner session** (the owner, after the last round: "Write up the plan and merge it"); this document is step OB1. Asked by the owner: "Let's try to design the first boss of the game. A boss the players will face after the first biome. It should be fought in a decently sized arena. The boss should have 2 phases. It should have a movement attack where it dashes slowly towards the players."

The steps are **OB1 to OB17** (OB for the Old Broom). Each is one PR with its tests, in order. **The content comes first** (owner, 2026-11-15): the broom, its card, its props and its arena are made early with today's parts, so they show up in the hub to play with while the plan goes on, and each general step after that upgrades them the day it merges. Most steps are general engine work: "Even if the boss ends up being bad, the changes are general and good, so they can be used to make a different boss" (owner).

## The boss

**The Old Broom** (canon, docs/milestones/M2-living-staffs.md: "the Old Broom, demoted to sweeping"). The wizard's first staff, now on floor duty, with a grudge. It sweeps the crypt and everything in it, players included, into the walls. Its lore line gives the grudge (content/story, docs/STORY.md).

## What the players see

- **The entrance:** the broom stands sweeping, not noticing anyone. A name banner ("The Old Broom") and its lore line show; its first Sweep comes about 2 s later. No cutscene, nobody waits.
- **The Sweep:** it rears back, a line on the floor shows its path and a scrape is heard, then it lurches forward slowly, picks up speed and drags to a stop, wide and heavy. What it meets rides along in front of it; pinned against a wall, it hurts. Slipping off sideways costs only the pass.
- **Wall hits:** when it hits a wall, a pillar or a player's Wall stones, a ring of dust bursts out (a pulse).
- **Dust flicks and a swat:** a scatter of slow dust bolts keeps players moving; anyone hugging it is swatted, and touching it hurts (contact damage), so nobody stands on it and fires.
- **The Big Sweep** (every 20–25 s, and as the transition move): it goes to a wall and sweeps the whole width of the arena. The only safety is behind a pillar, which the broom cracks and stops on. Cover is used up: later in the fight there is less of it, and players' own spells break pillars too.
- **Phase 2, "Spring cleaning"** (below 55% health): it rattles, invulnerable, and its bristles catch fire; mites pour out. Its Sweeps curve a little, come two in a row and leave burning lanes. Burning bristles through a **dust heap** blow it up on the broom; players bait it through heaps or light them themselves.
- **The kill:** the game-wide stop, the broom splinters, its bristles drift down, its mites crumble.

The questions the fight asks:

| | The question |
| --- | --- |
| Phase 1 | Where do I stand relative to walls and the line? |
| The Big Sweep | Who hides behind which pillar, and do we save the last one? |
| Phase 2 | How do we use the heaps and the lanes while the mites crowd us? |

## Owner decisions (2026-11-14 and 2026-11-15)

1. **The boss is the Old Broom.**
2. **The Sweep is straight in phase 1 and curves a little in phase 2** (homing).
3. **Phase 2 has all of it:** fire lanes, mites and a double Sweep.
4. **The boss can be hurt freely,** at any time, not only in a punish window.
5. **Pillars are destructible,** and their rubble is gone (it no longer blocks).
6. **Plow is in:** the Sweep carries what it hits instead of passing through.
7. **Mites are not a card:** they come with the boss's phases (decision 18), not a Summon card.
8. **The line on the floor during a move's wind-up is general:** every long wind-up of a move shows its line, not only the boss's.
9. **Build it in steps**, one PR each.
10. **Power is a number on the actor** (option A), tuned per actor and raised later by relics and difficulty: "It can be tuned (and increased with relics etc.) per actor."
11. **Plow's wall pin hits harder than heavy's slam** (2× the hit).
12. **The broom has contact damage,** "so players can't just walk into it and stand there and fire", and a body Plow carries takes it too.
13. **About 16 for a wall pin is fine for now;** the wizards' starting health will be tuned (probably lowered) later, and then power is turned down, not the card lists.
14. **The dust flick keeps `scatter`; the wall's dust ring is a `pulse`,** looking like dust.
15. **Animating the boss is very important to get right:** a layered body moved by the game, plus a few drawn frames for the extreme poses, and its own face (not a stray's). The look is reviewed by the owner before the fight is put together.
16. **More mites.**
17. **The boss's spells reach far, by `reach` cards** (one or more where needed), not an actor number.
18. **A boss can be placed in any room:** its adds and its music come with the boss (its phases and its data), not the room. Rooms stay layout only.
19. **The pacing is faster** than first proposed (below, "Pacing").
20. **The Big Sweep with pillars as shelter, and dust heaps that explode on fire, are in.** Plow carries everything (mites, rubble, players) but downed bodies; `on wall` fires on any blocking thing, the Wall card's stones included.
21. **No grey-box prototype step;** the content is built early instead (decision 24).
22. **Plow never carries a downed body,** so a revive stays possible mid-fight.
23. **Every actor has `ActorStats`:** power, mass, a spell scale and status resistances, possession among them ("Scaled by a possess status resistance I think fits well"). A wizard may possess the broom, briefly by its resistance. "Now that the boss is bigger than the players, I think a scale on its attacks size should also be present in the ActorStats."
24. **Most of the content is made early,** so it "automatically" shows up in the hub to play with while the plan continues. Animation comes as soon as the poses exist.
25. **Prepare for audio,** though the game has no sound files yet: every moment names its sound, and the sound system can do what the fight needs.
26. **Music, layers or a second track:** not decided. The data allows both (below, "Sound"); whoever makes the music chooses.

## General pieces

Each is built for every actor and card, never for the broom alone.

### ActorStats (OB7)

One resource, `ActorStats` (core/base), on `EnemyBase`, `EnemyPhase` (a phase may replace it; null keeps), `PropBase` and the wizard's data. All defaults leave the game as it is.

```
ActorStats
├─ power: 1.0          × the damage of the body's spell hits, and what follows from it (heavy's slam, Plow's pin, burns from the hit)
├─ mass: 1.0           a shove on the body is divided by it
├─ spell_scale: 1.0    × the radius of the body's spells: a shot's size, a pulse's ring, a swing's arc, a dash's pass, a pool
└─ resist: {status → share}   a status lasts (1 − share) as long; possession is one of them (&"possess")
```

- **State, the body's own:** hashed and in snapshots like any member (core/sim/README.md); relics and difficulty change the same numbers later, nothing else needs to know.
- **Power is read at the hit,** from the caster's body (its actor id), so compiled spells stay shared between bodies and a change counts at once; a shot whose caster is gone hits at 1.0. It does not scale contact damage (its own number) or heals.
- **Spell scale** is the actor's counterpart of `bigger`'s radius, without its damage or speed: a big body's attacks are as big as it is. Body size stays `EnemyBase.size`.
- **Resist** makes a freeze (three chills) harder on the broom, not impossible. A wizard possessing the broom keeps it for the possession's seconds times (1 − resist). A phase whose condition is met during a possession starts when the possession ends.

### Lumber (OB4, OB10)

A new modifier, numbers only: about 0.45× speed, about 3× distance, 3× damage, and a speed curve that starts slow, picks up and drags to a stop. A player's dash with it becomes a real attack: a slow, heavy-hitting charge. **OB10** makes speed curves (`speed_start`, `speed_end`, `speed_ease`) apply to moves (dash, teleport's flight where it has one), not only to flying shots; until then Lumber is its plain numbers.

### Plow (OB11)

A new modifier with a new behaviour (`ModifierBase.RULES` row): what the carrier hits rides along in front of it instead of being passed, and is let go with a shove at its end. A carried body pinned against a wall or a blocking prop takes a pin of 2× the hit (heavy's slam is 1×). It carries every body (players, enemies, mites, a prop's rubble while it lies there) but a downed one. The carrier's contact damage applies to what it carries. On a flying shot it is a battering ram. A carried body can slip off sideways.

### `on wall` for moves (OB12)

`TriggerBase.NEEDS` lets `on wall` fire for a carrier that moves its caster when the moved body meets a wall, a blocking prop or the Wall card's stones. `dash · on wall · pulse` works for players too, a wall bounce that bursts.

### The line of a move's wind-up (with OB8)

While a move's cast winds up (a dash, the Sweep), its path shows on the floor in the telegraph colours (docs/STYLE.md: enemy telegraphs in Fire colours). Every move cast, every actor. Drawn only (Feel), never read back.

### Poses and layered bodies (OB8)

Today `CreatureLook` is built for a 32×32 stray: one frame, a wind-up strip, a hurt frame, a hop, the face, and a texture, glow and size swap per phase. Two general additions:

- **Poses from states:** the look shows a pose for what the body is doing, read from states the game already has: idle, winding up, moving by its own move, met a wall, hurt, in a phase transition, dying. Any enemy can have them (a splinter's dash pose).
- **Layered bodies:** a body drawn in parts (for the broom: the handle, the binding, the bristle head) that the game moves: the handle **leans** into the way it goes and back when it brakes; the head **lags** behind and squashes on the floor; the head **swishes** side to side while it moves; a wall hit **squashes and stretches** the handle and shudders the bristles. A few drawn frames for the extreme poses (wind-up, wall hit, death).

All drawing (VIEW), never state. Motes for dust while it moves and sparks in phase 2 are data (content/motes), as the hub's rim.

### Phase adds (OB13)

A phase brings its adds, so the boss works in any room:

```
EnemyPhase
└─ adds: Array[EnemyAdds]
     EnemyAdds
     ├─ enemy, count, per_player             the burst when the phase starts
     ├─ every, wave_count, wave_per_player   then a wave this often while the phase lasts
     ├─ cap, cap_per_player                  at most this many alive at once
     └─ at: the room's EnemySpawns, else a ring round the body
```

`Phases` starts the phase and sends a request on the bus (`adds_requested`); Flow, which spawns enemies already, stands them up. The phase's area and Flow never call each other. **Adds crumble when the body that called them dies**; the room is cleared when the boss is dead. Any enemy can have adds (an elite calling strays at half health).

### The run-up (OB14)

An AI behaviour, general: for a cast that moves its caster, the AI may first move to where that cast's line is longest (a wall's foot facing the open room). It makes the Big Sweep: the broom goes to a wall, then sweeps the arena. Every dashing enemy gains it.

### Sound (OB15)

The plumbing exists: a cue names a `sound` (core/base/cue_base.gd), silent until an `.ogg` exists. Missing, and general:

- **Held sounds:** a sound that lasts while something lasts (the cue `stream` part's counterpart: until its carrier ends, or a status or a phase ends): the scrape for a wind-up, the swish of a Sweep, the burning loop of phase 2, a held beam's hum.
- **Music with intensity:** `RoomBase.music` names a track; `EnemyBase.music` overrides it while that enemy lives; its phase raises the intensity. A track is a list of layers; the intensity says how many play, or which entry. One plain track is one layer, a phase-2 track a second entry (decision 26).
- **Rules:** sound is drawn-only like Feel, never fed back into the game; a limit of voices per sound (with the cues' `every`); position in the room.

**The sound sheet** (what the audio pass fills in; every id is named in its cue from the step its moment is built):

| Moment | Cue | Sound id | Length, loop | Notes |
| --- | --- | --- | --- | --- |
| Entrance | `boss_intro` | `boss_intro` | 1–2 s | Under the name banner |
| Sweep wind-up | `broom_wind` | `broom_scrape` | held | A telegraph: heard off screen |
| Big Sweep wind-up | `broom_big_wind` | `broom_big_scrape` | held | Louder and longer, known without looking |
| Sweep | `broom_sweep` | `broom_swish` | held | Rhythm of the swish |
| Wall hit | `broom_wall` | `broom_crunch` | short | With the pulse's own sound |
| Swat | `broom_swat` | `broom_swat` | short | |
| Pillar cracks, breaks | the prop's states | `pillar_crack`, `pillar_break` | short | |
| Dust heap scattered, explodes | the prop's states | `dust_scatter`, `dust_explode` | short | |
| Phase change | `broom_ignite` | `broom_ignite` | 2 s | The rattle, then the whoosh |
| Burning bristles | phase 2's look | `broom_burning` | held, loops | For all of phase 2 |
| Death | `boss_death` (exists) | `broom_splinter` | 2 s | |
| Music | the broom's `music` | `boss_broom` | loops | Phase 2 more intense |

### HUD: the boss bar (OB16)

One bar at the top for everyone while a boss lives: its name, its health, a mark at each phase's health. Fed by events (the HUD never names gameplay).

## The broom's data

Starting values, tuned in OB17. Damage below is at power 2 (phase 1) and 2.5 (phase 2); a wizard has 100 health today.

**Stats:** power 2 (phase 2: 2.5), mass about 6, spell scale about 1.5, resist about {chill 0.6, burn 0.3, possess 0.7}. Contact damage 8. Size: a 96×64 body. Health: about 90 s for one player, × (1 + 0.7 per extra player).

**Phase 1, "Tidying up":**

| Staff | Cards (with `reach` where needed) | Damage |
| --- | --- | --- |
| Sweep | `bigger · lumber · plow · dash · on wall · pulse` | pass about 8, pin about 16, ring 8 |
| Big Sweep | `bigger · bigger · lumber · plow · dash · on wall · pulse` | as the Sweep, the whole arena wide |
| Dust flick | `scatter · slow · bolt` | about 10 a bolt (to tune) |
| Swat | `bigger · heavy · swing` | about 5, and a 5 slam |

Caught, carried and pinned costs about 8 + 8 (contact) + 16 = 32; slipping off sideways costs 8.

**Phase 2, "Spring cleaning"** (health below 0.55, transition about 2 s): the Sweep becomes `echo · bigger · lumber · plow · homing · dash · timer · slow · fire · pool` with its `on wall · pulse` (lanes of fire that last about 12 s), the burning look, power 2.5. Adds: crypt mites, 4 + 2 per player at once, then 2 + 1 per player every 10 s, at most 6 + 2 per player alive.

**Pacing:**

| | Phase 1 | Phase 2 |
| --- | --- | --- |
| Wind-up (the line) | 0.8 s | 0.6 s |
| Sweep | about 1.0 s, about 220 px/s, about 240 px | the same, twice |
| Recovery | 0.4 s | 0.3 s |
| Next Sweep | about every 3.5 s | about every 3 s |

**Profile:** it turns its Sweeps to the player it hit least recently (OB3 checks whether the spreading of L3 already does; else a profile number).

**Look:** its own face (not a stray's: an old staff's), the layered body, and the poses:

| State | Pose |
| --- | --- |
| Idle | Hovers upright, bristles swaying, taps the floor impatiently |
| Wind-up | Rears back, bristles lift and spread, brows furious; the line shows |
| Sweep | Leans hard forward, swish swish, dust off the bristles |
| Wall hit | Crunch: squash, the shudder, a puff of dust all round with the ring |
| Swat | A sharp half turn, bristles fanning out |
| Transition | Shakes hard, embers catch, then the bristles burst into flame |
| Phase 2 | Burning head, sparks off every swish, an angrier face |
| Death | Splinters, the bristles scatter, the bound head flies off |

## The arena and its props

`content/rooms/crypt/boss_broom/`: about 1.7× a crypt room, an open middle, walls all round, four **cracked pillars** in a loose diamond and a few **dust heaps**, doors that open when the boss dies. It is the broom's best room, not its only one: the fight works in any room with whatever cover it has (decision 18).

- **Cracked pillar** (`content/props/cracked_pillar`): intact, cracked (shown at half health), then gone. Two pins break it; spells chip it.
- **Dust heap** (`content/props/dust_heap`): a body through it scatters it into a cloud that drifts a moment; fire on the heap or the cloud makes it explode, hurting everything near, the broom included.

Both are data and art only (docs/milestones/props.md), and show up in the hub's prop yard by themselves.

## Playing it early

What exists shows up by itself: new cards in the hub's bag, new props in the hub's prop yard. OB2 adds the rest:

- **The enemy arena in the hub too** (today only in the Sandbox), listing bosses as well as enemies.
- **A room picker** on the same pause menu page: every room in the registry, read by folder like the enemies, to walk into with the build one holds. Every new room can be tried at once. (The page, the cheapest; moving it into the hub's world is a later choice.)

## Steps

| Step | What | Areas |
| --- | --- | --- |
| OB1 | This document | docs |
| OB2 | The enemy arena in the hub, listing bosses; the room picker | hud/menus, gameplay/flow |
| OB3 | **The broom v0** (`content/bosses/old_broom/`): two phases with today's parts. Sweep `slow · heavy · bigger · dash` (homing in phase 2), flick `scatter · slow · bolt`, swat `bigger · heavy · swing`, fire lanes `dash · timer · slow · fire · pool`; contact 8; a placeholder 96×64 sprite and a burning phase look; its lore line; the bosses README's example | content/bosses |
| OB4 | **Lumber**, its numbers (its curve arrives in OB10) | content/spells |
| OB5 | The cracked pillar and the dust heap | content/props |
| OB6 | The arena | content/rooms |
| OB7 | `ActorStats`; the broom gets power, mass, spell scale and resists | core/base, gameplay/actor, gameplay/combat, core/spells |
| OB8 | Poses from states, layered bodies, the line of a move's wind-up | gameplay/ai (look), gameplay/feel |
| OB9 | **The broom's look: an animation sheet and a recorded preview of every pose, for the owner's review** before the fight is put together | content/bosses |
| OB10 | Speed curves on moves; Lumber gets its lurch and drag | core/spells |
| OB11 | **Plow**; the broom's Sweep carries and pins | core/spells, gameplay/combat, content/spells |
| OB12 | `on wall` for moves; the broom's dust ring | core/spells |
| OB13 | Phase adds; the broom's mites | core/base, gameplay/actor, gameplay/flow |
| OB14 | The run-up; the Big Sweep | gameplay/ai, content/bosses |
| OB15 | Held sounds; music with intensity; every sound id of the sheet in its cue | gameplay/feel, core/base, content/cues |
| OB16 | The boss bar | hud |
| OB17 | Tuning with bot playtests and the owner's; the entrance; a GIF of the whole fight | content/bosses |

Each step's tests come with it: a card's test in its folder and the card-rules test (`tests/core/test_card_rules.gd`) for Lumber, Plow and `on wall`; the content determinism tests pick up the broom, the props and the room by themselves (`test_content_determinism.gd`, `test_snapshot_game.gd`); ActorStats in the state and snapshot tests.

## Fit with the design

- **Deep spell building:** the boss is cards a player can hold (Lumber and Plow are new cards for everyone); the fight rewards fire (heaps), the Wall card (`on wall`), decoys, `on kill` (mites) and possession.
- **Nobody waits:** no cutscene; the entrance plays while everyone moves; a revive stays possible (Plow leaves the downed).
- **Readable chaos:** every attack has a wind-up, a line on the floor and (later) a sound; the Sweep stays one line at every player count.
- **Everything hurts everything:** the broom's own fire blows up heaps on it, its pins kill its own mites, players' spells break the pillars that shelter them.
- **One game, the same everywhere:** every new number is the body's state; poses, lines and sound are drawn only.
- **Fair from 1 to 4 players:** health and adds scale with players; the attacks do not multiply.

## Not in this plan

The boss in a run's room order (M3, Run structure), its rewards (enemy cards as rewards, M3–M4: Lumber and Plow are candidates), the sound files and the music themselves (decision 25), the other bosses.

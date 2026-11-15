# The Old Broom: the first boss

**Status (2026-11-15): planned with the owner in an owner session** (the owner, after the last round: "Write up the plan and merge it"); this document is step OB1. Asked by the owner: "Let's try to design the first boss of the game. A boss the players will face after the first biome. It should be fought in a decently sized arena. The boss should have 2 phases. It should have a movement attack where it dashes slowly towards the players." The two questions left open at its merge were answered the same day ("Answered after the merge").

**Done:** OB1 (this document). **OB2 replanned (owner, 2026-11-15, decisions 30-33):** the trial gate first built on the branch (a mode, a start and picks of its own) is replaced by the run's own rooms: no waves, a run is a path of rooms from the teleporter to the boss, and the lectern only sets where on the paths the teleporter's run starts. Steps OB2a-OB2c below. **OB2a done (2026-11-15):** no waves; rooms list their enemies (`RoomBase.enemies`, `RoomEnemies`); a room won with no room after it ends the run (from the stone, back to the hub); the HUD's wave and build-break lines are gone; the Sandbox's enemy arena lists and spawns bosses. **OB2b and OB2c are replaced** by the run generation plan ([run-generation.md](run-generation.md), approved 2026-11-15, steps RG1-RG8): a run defined as data, its branching map generated, the boss joining the crypt run by its own data. **OB3 done (2026-11-15):** the broom v0, `content/bosses/old_broom/`: its Sweep `reach · bigger · dash` (0.8 s wind-up), dust flick `scatter · slow · bolt` and swat `bigger · heavy · swing`; phase 2 under 55% health (2 s transition, its own profile, a burning placeholder look) with the double Sweep `timer · reach · bigger · dash · slow · fire · pool` twice (0.6 s wind-ups) and the flick and swat; contact 8, 900 health (OB17 tunes it), a placeholder 96×64 sprite with a stray's face until OB8 and OB9; `biomes: [crypt]`, so it fills the crypt run's boss room once OB6 makes one. Every staff's id is the folder's (the spell validator's rule for a staff in an enemy's `.tres`). `EnemyBase.lore`, its one line, checked by the story check (`StoryValidator.check_lore`, a boss with none warns); its canon in docs/STORY.md; the bosses README rewritten as the guide (decision 29). **OB4 done (2026-11-15):** Lumber, `content/spells/modifiers/lumber/`, numbers only (0.85× speed, 3× distance by `reach_mult`, 3× damage; priced at 2.75× mana and 1.3× wind-down; its speed curve comes in OB10); the broom's Sweeps take it in place of Reach, their stand-in: `bigger · lumber · dash` and phase 2's `timer · bigger · lumber · dash · slow · fire · pool` twice (its staff now 200 mana). **OB5 done (2026-11-15):** the cracked pillar, `content/props/cracked_pillar/` (32 health, cracked below half, then rubble that neither blocks nor is hit; data and art only), and the dust heap, `content/props/dust_heap/` (invincible; walked into, it scatters to dust on the floor that blocks no more; fire or a burn on the heap or the dust blows it up, `fire · blast · pulse`, and leaves a scorch mark), with the new prop trigger `touched` (`PropTrigger.When.TOUCHED`): a body that walks overlapping the prop's `area`, its circle against the walls where its move left it, asked of the actor table (`Actors.set_touch_area`, `touching`) by the walking body at the end of its move and told to the prop as its own `Actor.touched`; a prop lays its area only while its state has a `touched` row. Both stand in the hub's prop yard. **OB6 done (2026-11-15):** the arena, `content/rooms/crypt/boss_broom/` ("The broom's crypt"): 26×16 tiles (832×512 px, about 1.7× arena_01), an open middle, walls all round, four cracked pillars in a loose diamond and four dust heaps near the corners (props, so the cover breaks), an entry door and no exit. It hosts the run kind `boss` in the crypt (`kinds: [boss]`, `biome: crypt`), so by the run generation plan (which replaced `RoomBase.enemies` and `follows`, decisions 31 and 32) the crypt run's last row is now this room and the broom stands in it from the boss pool, at its first enemy spawn; the room names no boss. A general check, for any template that hosts a boss: every boss of its biome fits at that spawn, clear of the walls and the props; and every template's spawns are clear of its props. **OB7 done (2026-11-15):** actor stats. `ActorStats` (core/base: `power`, `mass`, `spell_scale`, `resist_burn`/`chill`/`gust`/`hex`/`static`/`possess`; read-only shared data, its defaults changing nothing) on `EnemyBase.stats`, `EnemyPhase.stats` (null keeps the last) and `PropBase.stats`; the wizard's scene names its own (`content/wizard/base/wizard_stats.tres`, the defaults). The actor kit's `Stats` (gameplay/actor; every actor has one, its scene's or one it adds itself) copies them as the body's own state as it is set up and as a phase names some; resist is a fixed array in Combat's status order, a freeze as a chill, then possess. Power is read at the hit from the caster's body by the tag's actor id, only while that build is the caster open now under the id (`Spells.cast_by_open`, the "seq": the ring's position when the caster opened and its builds since), so a gone caster's shot or a reused id hits at 1: the hit, the slam it arms and the burn it puts on (not contact, plain hits, reactions or heals). Mass divides a shove (a hit's push, a pull). Spell scale is built into the body's spells at compile time (`StaffCompiler`, `Carrier.scale_size`: the radius and its drawn size, a blast, a pulse's ring (its growth), a swing's arc; a flight's or a beam's reach stays its cards', decision 16; `Caster` keyed by it, `Caster.rebuild` after a phase changes it), not a hot loop, so the native kernels are untouched. Resist shortens statuses, what a reaction adds to one, and possession ((1 - share) as long, 1 never). A phase met during a possession starts when it ends; its transition's protection with it, so a possessed boss can be hurt past a phase meanwhile (short on the broom, possess 0.7; for OB17's playtests to judge). A phase's stats replace the body's copy whole, so when relics and difficulty change the copy they must be applied again after a phase. A static discharge is a share of the hit, so it follows the caster's power; reactions do not. The broom's numbers in its own data: power 2 (phase 2: 2.5), mass 6, spell scale 1.5, resist chill 0.6, burn 0.3, possess 0.7. The room's scale (`Actor.stat_scale`, RG5) still scales health only; power and spell size may later join it through the body's `Stats` copy. **OB8 done (2026-11-15):** poses from states, layered bodies, the death remnant and motes that follow. `BodyPose` (gameplay/actor; any look keeps one, `CreatureLook` for a layered body): the pose is the first that holds of TRANSITION (its AI's), WALL (its own move went less than half its way: once each time it is held up, held 0.4 s), HURT, WINDUP, MOVE (its own move, `Mover.is_dashing`, not a pull), CAST (the staff animation), IDLE, all read from state, and a hit's pose shows through its hit-stop; its motion is a spring after the way the body goes (so it swings back past upright as it brakes; rears back from its aim winding up). `BodyPart` (gameplay/actor): a layered body's parts, the `BodyPart`s under its `Sprite`, frames of any size in a tree, each moved by its own numbers (`lean`, `lag`, `swish`, `squash`, `sway`, `wall_squash`, `shudder`, `pose_frames` a frame a pose, `fling`, `carries_face`). `PhaseLook` gains `parts` (art by part name) and `motes`/`motes_on` (motes from a part that follow the body: `MoteSource.put(..., follow)`, Feel's source motes move them with their node). A dead layered body's parts fly apart as a remnant Feel draws (gameplay/feel/remnants.gd: along the floor and up, bouncing, lying 1.6 s, fading), each breaking into half its share of motes. All drawn only; a test holds a layered body to a plain one's path to the bit. The broom is layered (its placeholder art cut into a bristle `Head` on the floor, its `Handle` behind it and its `Binding` with the face, as grids for OB9), hovers (`hops` false), and in phase 2 its head burns and gives off embers. Its own face and the drawn extreme frames are OB9's. **OB9 done (2026-11-15), for the owner's review:** the broom's look. Its own face (decision 14): a `Face` may wear a face of its own, `FaceArt` (core/base: its own eye and brow sheets in the shared layout at any frame size, with their origins; its `style` still sets its habits), and a phase picks its row (`PhaseLook.face_row`); the broom's are an old staff's heavy-lidded eyes and big bushy brows, and in phase 2 slanted, angrier eyes and singed brows. Drawn frames for the extreme poses: its head is five frames (rest, wind-up with the bristles lifted and splayed, wall hit crushed, swat fanned, and on the burning head the straw catching fire, shown through the phase change: "embers catch, then the bristles burst into flame"). A part may tap (`BodyPart.tap`, `taps`, `tap_every`: lifted and dropped quickly while the body stands idle), so the broom taps the floor impatiently. The art redrawn on the grids (a straight handle with the empty socket where its gem was, a corded binding); its numbers tuned against the recording (the handle leans 18°, the head 4° and swishes 5° 3.5 times a second). After a snapshot the look puts the face's style, glow and row back too (`Face.unstyle`, `CreatureLook.sync`). **The preview:** `tests/screenshots/shot_boss_looks.gd` plays every boss of the registry in a room of its biome that hosts bosses against a protected wizard and records each pose of the Look table as a filmstrip and a sheet (each frame sized from the body's art; a sheet and a filmstrip a pose, named by pose, in the build's screenshots); `FaceArt.problems()` is checked for every enemy and boss, and a face whose art cannot be drawn wears the shared sheets; nothing general names the broom. OB10 to OB16 do not wait for the owner's review; OB17 does. **OB10 done (2026-11-15):** moves. A move's speed curve is its cards' `move_start`, `move_end` and `move_ease` (`MoveCurve`, core/spells: from start × its speed to full speed and down to end ×, still its whole way in its whole time, worked out exactly per step), on a dash's body (the Mover) and on a shot a dash moves (`Projectiles.move_shot`); Lumber lurches off and drags to a stop (0.1, 0, 3). A dash's pass is as wide as its mover (a body's hurt shape × the cards' `radius_mult` × its spell scale, a shot's radius; never under `PASS_REACH`). A dash held up head on (a step keeping under half the way it asked along its own way: under about 45° from straight in) by a wall, a blocking prop's ground or the Wall card's stones ends there, and its pass with it; a glancing one slides on. The broom's dust flick is aimed (decision 34): `triple · slow · bolt · slow · bolt · slow · bolt`, 7 slots, a 10° spread. No native kernel changed: the move and its pass are GDScript only (native/README.md, "What stays GDScript"), and the wall slide is the same. See "Built (OB10)" for the choices the plan left open. OB11 (Plow) is next.

The steps are **OB1 to OB17** (OB for the Old Broom), OB2 in three (OB2a-OB2c). Each is one PR with its tests, in order. **The content comes first** (owner, 2026-11-15): the broom, its staffs, its card, its props and its arena are made early with today's parts, so they can be played while the plan goes on, and each general step after that upgrades them the day it merges. Most steps are general engine work: "Even if the boss ends up being bad, the changes are general and good, so they can be used to make a different boss" (owner).

Card lists are written in slot order (docs/milestones/M2-staffs.md, "Reading a staff"): modifiers, infusions and triggers **before** their carrier, each trigger's payload **after** it, several triggers taking their payloads in slot order.

## The boss

**The Old Broom** (canon, docs/milestones/M2-living-staffs.md: "the Old Broom, demoted to sweeping"). The wizard's first staff, now on floor duty, with a grudge. It sweeps the crypt and everything in it, players included, into the walls. Its lore line gives the grudge; OB3 records it in docs/STORY.md's canon.

## What the players see

- **The entrance:** the broom stands sweeping, not noticing anyone. A name banner ("The Old Broom") and its lore line show; its first Sweep comes about 2 s later. No cutscene, nobody waits.
- **The Sweep:** it rears back, the lane on the floor shows its path (the enemy telegraph every enemy cast has, cast-timing T6b) and a scrape is heard, then it lurches forward, picks up speed and drags to a stop, wide and heavy. What it meets rides along in front of it; pinned against a wall, it hurts. Slipping off sideways costs only the pass.
- **Wall hits:** when it meets a wall, a pillar or a player's Wall stones head on, it stops and a ring of dust bursts out (a pulse).
- **Dust flicks and a swat:** a scatter of slow dust bolts keeps players moving; anyone hugging it is swatted, and touching it hurts (contact damage), so nobody stands on it and fires.
- **The Big Sweep** (about every 20–25 s, and first when phase 2 starts): it goes to a wall's foot and sweeps most of the arena's length with a front about a third of the arena wide. A pillar is the surest shelter: the broom meets it, cracks it and stops. Cover is used up; players' own spells break pillars too.
- **Phase 2, "Spring cleaning"** (below 55% health): it rattles, invulnerable, and its bristles catch fire; mites pour out. Its Sweeps come two in a row, each with its own wind-up and lane, and leave a trail of burning patches. Burning bristles through a **dust heap** blow it up on the broom; players bait it through heaps or light them themselves.
- **The kill:** the game-wide stop, the broom splinters, its bristles drift down, its mites crumble.

| | The question the fight asks |
| --- | --- |
| Phase 1 | Where do I stand relative to walls and the lane? |
| The Big Sweep | Who hides behind which pillar, and do we save the last one? |
| Phase 2 | How do we use the heaps and the burning trail while the mites crowd us? |

## Owner decisions (2026-11-14 and 2026-11-15)

1. **The boss is the Old Broom.**
2. **The Sweep is straight in phase 1 and curves a little in phase 2.** In phase 2 it follows its target through most of its wind-up and locks late; in phase 1 it locks early (decision 26).
3. **Phase 2 has all of it:** fire, mites and a double Sweep.
4. **The boss can be hurt freely,** at any time, not only in a punish window.
5. **Pillars are destructible,** and their rubble is gone (it no longer blocks).
6. **Plow is in:** the Sweep carries what it hits instead of passing through.
7. **Mites are not a card:** they come with the boss's phases (decision 17), not a Summon card.
8. **Build it in steps**, one PR each.
9. **Power is a number on the actor**, tuned per actor and raised later by relics and difficulty: "It can be tuned (and increased with relics etc.) per actor."
10. **Plow's wall pin hits harder than heavy's slam** (2× the hit).
11. **The broom has contact damage,** "so players can't just walk into it and stand there and fire", and a player Plow carries takes it too.
12. **About 16 for a wall pin is fine for now;** the wizards' starting health will be tuned (probably lowered) later, and then power is turned down, not the card lists.
13. **The dust flick keeps `scatter`; the wall's dust ring is a `pulse`,** looking like dust. *Changed by the owner on 2026-11-15, after OB9 (decision 34): the flick is aimed.*
14. **Animating the boss is very important to get right:** a layered body moved by the game, plus a few drawn frames for the extreme poses, and its own face (not a stray's). The owner reviews the look before the fight is put together.
15. **More mites.**
16. **The boss's spells reach far, by `reach` cards** (one or more where needed), not an actor number.
17. **A boss can be placed in any room:** its adds and its music come with the boss (its phases and its data), not the room. Rooms stay layout only.
18. **The pacing is faster** than first proposed ("Pacing").
19. **The Big Sweep with pillars as shelter, and dust heaps that explode on fire, are in.** Plow carries every body but downed ones; `on wall` for moves fires on walls, blocking props and the Wall card's stones.
20. **No grey-box prototype step;** the content is built early instead (decision 23).
21. **Plow never carries a downed body,** so a revive stays possible mid-fight.
22. **Every actor has stats:** power, mass, a spell scale and status resistances, possession among them ("Scaled by a possess status resistance I think fits well"). A wizard may possess the broom, briefly by its resistance. "Now that the boss is bigger than the players, I think a scale on its attacks size should also be present in the ActorStats."
23. **Most of the content is made early,** to play with while the plan continues. The animation comes as soon as the poses exist.
24. **Prepare for audio,** though the game has no sound files yet: every moment names its sound, and the sound system can do what the fight needs.
25. **Music, layers or a second track:** not decided. The data allows both ("Sound"); whoever makes the music chooses.

**Corrections after the plan's review (2026-11-15),** where the session's proposals met the code:

- The line on the floor during a wind-up **already exists** for every enemy cast (the carrier's `wind_cue` lane, cast-timing T6b; Feel shows it only for casts that are not a wizard's, owner 2026-11-01). Nothing new is built for it, and players' casts still show none.
- Echo does not make a second Sweep (it re-fires 0.3 s into the first, with no wind-up of its own). The double Sweep is **two Sweeps in the phase-2 staff**, each cast with its staff's wind-up and lane.
- A dash strikes only 8 px round its mover's middle (`SpellLimits.PASS_REACH`), so a wide Sweep needs a move's pass to be as wide as its body (OB10).
- Props don't move (docs/milestones/props.md), so Plow carries bodies only, never rubble.

## Answered after the merge (owner, 2026-11-15)

26. **When the Sweep stops following its target** (owner: "Agreed", on locking the aim late). Today every enemy re-aims at its target through its whole wind-up, and the lane follows that aim live (gameplay/ai/brain.gd, WINDUP; gameplay/feel/lanes.gd), so a Sweep already follows the player until it leaves. The phases differ by **when the aim locks**: a profile number, `aim_lock`, the seconds before release that the aim stops following (0, the default, keeps today's behaviour for every enemy). **Phase 1 locks at the start of its wind-up** (its Sweep goes where the lane first showed, straight and easy to read). **Phase 2 locks for the last 0.25 s** (it follows you, then commits; a dodge timed to the lock still works). The Homing card is not used: it bends the run after release, away from the lane. The lock is measured against the wind-up its cast has left in Spells, not the brain's own clock, so a chill or a freeze that stretches the wind-up moves the lock with it and the lane never shows a lock that is not there. The lane shows the lock with a beat (a flash on it). Each phase has its own profile (`EnemyPhase.profile`), so this needs nothing more. Built in OB14.
27. **(Replaced by decisions 30-33, owner 2026-11-15: "the room selector should only use game logic/mechanics used in the real game".)** **A trial gate in the hub** (owner: "So a Prop that a player can interact with, that opens a menu of which room the players want to visit?"). A pause-menu room picker would let one player choose for everyone, and the hub is the lobby, with no enemies but the dummies (online-lobby.md). So, within the co-op rules (docs/DESIGN.md: no one controls another's choices; shared decisions by walking):
    - **The gate is a prop with a role** (`trial_gate`, as the teleporter stone's `run_start` and the altar's `party_altar`; it is not in the prop yard). Beside it stands a **lectern**, its own area: a wizard there presses A and **a menu of every room** opens (read from the registry by folder, as the enemy arena reads enemies, so a new room shows by itself; the hub and the sandbox are left out). The menu is that player's alone and pauses nothing. The lectern is beside the gate, not in it, because A (`accept`) on the lit gate sends the party: a player changing their pick while everyone stands in the gate must not send them instead.
    - **Each wizard's pick is their own,** shown over the gate in their colour (Feel's view only). A pick is a command (`trial_picked`, its room id; `InputFrame.COMMAND_NAMES`), an unknown id ignored; the picks are simulation state, kept by `HubRules`, hashed and in snapshots.
    - **The gate lights only while every wizard stands in it and every pick is the same room;** a wizard stepping off, a new join or a changed pick puts it out. **A press of A by any seat on the lit gate** sends the party, as on the lit stone (`run_requested`). Nobody goes anywhere they did not pick and walk to.
    - **The trial is a start of its own,** `trial_requested(room_id)`, recorded in the replay's header as the hub's and a run's starts are, so replays, snapshots and online guests know the room.
    - **The room stands its own enemies** (the boss arena stands the broom by its `EnemyStandIn`), so the hub never holds one. Cleared, or everyone down, the party is back in the hub as it left it: its staffs carry over as through the stone, and nothing found in the trial comes back.
    - The Sandbox's enemy arena lists bosses too.
28. **The boss can be deleted by deleting its folder and files** (owner, 2026-11-15: "Yes!"), as a spell card is:
    - `content/bosses/old_broom/`: its data, scene, art and `assets.json`, and inside its `.tres` as sub-resources (as every enemy's staffs are, content/enemies/README.md) its staffs, its phases' profiles (never in the shared `content/enemies/profiles/`) and looks, its lore line and its music's layer data;
    - its arena, `content/rooms/crypt/boss_broom/`;
    - its cues, `content/cues/broom_*.tres` (cues must stay in `content/cues`: the registry files a resource under the top content folder it sits in, so Feel finds cues only there);
    - once they exist, its sounds and its track in `audio/` and their lines in `audio/manifest.json`;
    - its lines in docs/STORY.md;
    - the bosses README's mentions of it as the guide's example (decision 29), which move to the next boss's folder when it is deleted.

    Everything general stays ("General pieces"), the cracked pillar and the dust heap too, as ordinary props. So no general code, test or default may name the broom or be tuned to it: its numbers live in its own data. A test of boss behaviour builds its own small boss in the test; only the tests that walk all content (`test_content_determinism.gd`, `test_snapshot_game.gd`) find bosses through the registry, and they pass with none. **Checked for good from OB17:** a test that no file outside the paths above names `old_broom` or `broom_`; and once in OB17, with those paths deleted, the full suite (`tools/ptest.sh`) and `tools/check.sh` pass.
29. **The bosses README is a guide to making a boss** (owner, 2026-11-15: "Yes, add it"), written in OB3 with the broom as its example and brought up to date by each step that adds a general piece. It says what a boss is (enemy data, its own staffs, actor stats, an AI profile, phases with their adds, a layered look, its cues, and optionally its best room; no script of its own), its assets listed in its folder's `assets.json`, how to start one from the broom's folder, and how to delete one (decision 28). What is not built yet at OB3 (actor stats, the layered look, phase adds) is marked "coming in OBn" and filled in by that step. It also holds **the table of what is still engine work**, so whoever designs the next boss sees at once whether it is data and art only or needs a general piece first. Each piece, once built, leaves the table and becomes data:

    | Kind of boss | The general piece it needs first |
    | --- | --- |
    | Several bodies (twin staffs, a broom and its dustpan) | Bodies that share health or a phase, and a fight that ends when all are down |
    | Parts and weak spots (a crystal to break on a giant staff) | Bodies attached to a body, each with its own health and hit shape |
    | Changes the arena (floods it, raises walls, drops the floor) | Rooms whose layout changes in play, and floors that hurt |
    | Too big for the screen, or attacking from its edge | A body the camera and the room frame differently |
    | Hurt only after an action (a puzzle) | Invulnerability by a condition |
    | Fights with the players' own builds (copies a staff) | Reading another body's cards (the inventory comes close) |

    The rule stays the enemy AI's (docs/milestones/M2-enemy-ai.md): a new mechanic goes into the shared engine, so every enemy gains it, never into one boss.

## After OB9 (owner, 2026-11-15)

34. **The dust flick is aimed** (owner: "Option 1, in OB10"). `scatter · slow · bolt` fired one bolt in a random direction (Scatter turns each carrier to a random way round the whole circle and ignores the aim, and the staff had no second carrier for it), while its lane showed the aim at the player. The flick becomes a Triple of slow bolts aimed at the player (`triple` in place of `scatter`, a slow bolt for each of its three carriers, the staff's slots to fit, a small `spread` between them if the staff needs it), so the shot goes where the lane shows. Built in OB10.
35. **The broom's casts start low** (owner: "Keep them low"): its shots, its wind-up lane and its swat's arc start from its `hand_offset` near the binding, not the top of the handle; the game has no height, so a point drawn high is a point far north on the floor.
36. **The AI walks round blocking props** (owner: "Just in OB14 is fine"). The OB8 broom got stuck on pillars: the AI's line and detour checks (`AISight`, `Projectiles.line_clear`) ask about room walls and the Wall card's stones only, never about the footprints of blocking props, so it walks into a pillar and grinds there. In OB14 those checks also treat blocking props' ground as walls, for every enemy, with a test of an enemy going round a pillar.

## The run's rooms (owner, 2026-11-15, after OB2's first build)

The owner, on the trial gate: "the room selector should only use game logic/mechanics used in the real game. It is for testing, but should not add custom code ... So if I delete it later on, it will not require changes to the code." And: "Waves should no longer exist. So the flow is this today: Go through the teleporter -> crypt biome -> lvl1 -> lvlN -> Boss. The only thing that changes is where in that chain the player starts. It's a 'dev' feature that sets the teleporter's starting room from crypt lvl1 to crypt boss." This brings M3's room sequence forward in its simplest form (no door voting, rewards or difficulty yet).

30. **No waves.** A run is a path of rooms. A room starts with its enemies standing; cleared, its exits open; the next room starts when every wizard stands in one open exit (a shared decision by walking, as the teleporter stone). A cleared room with no room after it (the boss's arena) wins the run: the party is back in the hub, as after a lost run (everyone down), with nothing of the run (owner, 2026-11-10). The wave, its growth, the build break and their HUD lines go; `play_requested` (tests, bots, the online spike) starts a run at the paths' first room.
31. **A room lists its enemies** (owner's pick: "Room lists its enemies"): `RoomBase.enemies`, entries of an enemy id (`EnemyBase.FOLDERS`: an enemy or a boss) and a count, stood at the room's `EnemySpawns` as it starts (today's spacing round a spawn kept). Ids, so a deleted enemy or boss leaves no broken file (a room naming an id the registry lacks stands nothing for it, with a warning; a test holds every room's ids to the registry). The boss's arena lists the broom (it no longer stands it by an `EnemyStandIn`); the arena's dummies and props stay placements.
32. **The paths are data** (owner: "Multiple paths exist ... a data setting the available paths"): a room names the rooms it can follow (`RoomBase.follows`, ids; `hub` for a room the teleporter leads to). A room's next rooms are the rooms that follow it, by id, so a new room joins the paths by its own data and deleting one (the boss's arena, decision 28) changes no other file. Its exits are props of the role `room_exit` (self-contained, lit as the stone is: a slab stood on, dark until the room is cleared), the first exit in the scene's order leading to the first next room, and so on; an exit with no room behind it stays dark, and a test holds each room's exits to its next rooms. The teleporter's run starts at the first room (by id) that follows `hub`.
33. **The lectern sets the teleporter's starting room, one for the party** (owner's pick): a seat's A at the lectern opens its room menu (every room on the paths, read from the registry, so a new room shows by itself); its pick is the command `start_room_picked(room_id)` (`&""`: the paths' own start), the party's one setting (hub state, hashed), told to the stone line ("Starts in: ..."); the stone's run starts there. No gate, no per-seat picks, no start of its own: the run from the stone is the one run. **What is the selector's alone** (the lectern prop, its command and setting, the menu): deleting the lectern's folder leaves the rest unused and working.

## General pieces

Each is built for every actor and card, never for the broom alone.

### Actor stats (OB7)

The data, `ActorStats` (core/base), is read-only and shared like a card: `EnemyBase.stats`, `EnemyPhase.stats` (null keeps the last) and `PropBase.stats`; a wizard's scene sets its own. All defaults leave the game as it is.

```
ActorStats
├─ power: 1.0          × the damage of the body's spell hits and what follows from them (heavy's slam, Plow's pin, burns from the hit)
├─ mass: 1.0           a shove on the body is divided by it
├─ spell_scale: 1.0    × the radius of the body's spells: a shot's size, a pulse's ring, a swing's arc, a move's pass (OB10), a pool
└─ resist: per status (burn, chill, gust, hex, static, possess), a share: the status lasts (1 − share) as long
```

- **The body's numbers are its own state:** a component of the actor kit (gameplay/actor, `Stats`) copies them from the data when the body enters play and when a phase changes them; relics and difficulty later change the copy, never the shared resource. Hashed and in snapshots like any member (core/sim/README.md). `resist` is a fixed array in Combat's status order, not a dictionary.
- **Power is read at the hit,** from the caster's body by its actor id and seq (as the dash kit keeps its caster), so compiled spells stay shared between bodies, a change counts at once, and a reused id is never read; a shot whose caster is gone hits at 1.0. It does not scale contact damage (its own number) or heals.
- **Spell scale** is the actor's counterpart of `bigger`'s radius, without its damage or speed: a big body's attacks are as big as it is. Body size stays `EnemyBase.size`.
- **Resist** makes a freeze (three chills) harder on the broom, not impossible. A wizard possessing the broom keeps it for the possession's seconds times (1 − resist).
- **A rule changed: phases during a possession.** Today a possessed boss changes phase as its health says (gameplay/actor/phases.gd). From OB7 a phase whose condition is met during a possession starts when the possession ends, so the possessor never loses its staffs mid-Sweep.

### Lumber (OB4)

A new modifier, numbers only: 0.85× speed, 3× distance (`reach_mult`), 3× damage, and (from OB10) a speed curve that starts slow, picks up and drags to a stop (a move's curve, `move_start` 0.1, `move_end` 0, `move_ease` 3). A player's dash with it becomes a real attack: a long, heavy-hitting charge.

### Moves: speed curves and a pass as wide as the body (OB10)

- Speed curves apply to a dash's move, not only to flying shots; Lumber gets its lurch and drag. (Built with a move's own numbers, `move_start`, `move_end`, `move_ease`: see "Built (OB10)".)
- **A move's pass is as wide as its body:** a dash strikes what is within its mover's hurt radius × the cards' `radius_mult` × the body's spell scale, not a fixed 8 px (`SpellLimits.PASS_REACH` stays the least). A wizard's dash hardly changes; a 96×64 broom's Sweep hits what its body meets. The native kernels mirror any change to the move (native/README.md).
- **A move meeting a wall head on ends there** (under about 45° to the wall); a glancing one slides on as now. Walls, blocking props' footprints and the Wall card's stones alike.

**Built (OB10), and the choices the plan left open (made by the session, for the owner to overrule):**

- **A move's curve has numbers of its own,** `move_start`, `move_end`, `move_ease` on `ModifierBase`, not the flight's `speed_start`, `speed_end`, `speed_ease`. Those multiply every shot's burst-and-ease and change how far it flies, so Lumber's lurch and drag on them would have made a Lumber bolt fly about a twentieth as far (against its "3x farther"), and a flight's one-way curve cannot start slow, pick up and drag to a stop. A move's are worth nothing elsewhere (wasted where the carrier does not move its caster along a way, `Carrier.moves_along`: a dash, not a teleport) and leave a flight alone.
- **The curve's shape,** `f(u) = 1 − (1 − start)(1 − u)^ease − (1 − end)·u^ease` over the share of its time gone: start × its full speed at first, end × at the end, about full speed between (full speed is the even speed over the curve's area, so it is above the even speed when the factors are below 1), the ease (at least 1) how soon it gets there. **It keeps the move's distance and time** (each step goes the share of the curve's area over its part of the time, exactly), so the AI's reach, the lane and the pacing table are unchanged; the curve only shapes the move. A move has no curve of its own (a wizard's dash is as before, to the bit).
- **Lumber's numbers:** start 0.1, end 0, ease 3: the Sweep starts at about a fifth of its even speed, peaks near 1.5× in the middle and stops dead (its 240 px still in its 1.1 s).
- **The pass's width** is the mover's hurt shape: the radius it is rounded by plus the larger half of its box (a circle: its radius), × `radius_scale` (the cards' `radius_mult` and the body's spell scale, which OB7 already built into it); for a shot a dash moves, the shot's own radius (already its cards'). At least `PASS_REACH`. The broom's Sweep (radius 26, `bigger` 1.6, spell scale 1.5) strikes about 62 px round its middle: as the plan's formula asks, which reaches past its body (a wizard's 8 px circle about 36 px clear of the broom's hurt circle is struck), since `bigger` and its spell scale grow the pass as they grow its other spells; a box is taken as a circle of its longer half. For OB17's playtests to judge (the Big Sweep's "front about 3× its body wide" follows from the same formula).
- **Head on** is measured on the slide itself: a step the walls changed that kept less than half (`Mover.HEAD_ON_SHARE`) of the way the dash asked along its own way ends the dash; a straight-in step keeps nothing, one at 45° from straight in keeps half (the slide keeps the part along the wall). It is told by `Actor.move` (`Mover.held_up`), so it covers whatever the body slides on: walls, the ground of bodies that cannot move (blocking props) and solid shots (the Wall card). Only a dash ends so: a pull, a swap or a recoil is done to the body and runs its time.
- **The pass ends with its move** (`CarrierDash.on_move_end`: it strikes at most `PASS_GRACE` more), so a Sweep stopped at a wall does not go on striking there for the rest of its time. The move's end point, its blast and its `on expire`, are where it stopped, ready for OB12's `on wall`.
- **No native change:** neither kernel runs a move or a dash's pass (the Mover, `_pass_move` and `CarrierDash` are GDScript only, native/README.md), and the wall slide (`BodyKernel`) is untouched; the head-on check reads its result.
- **The flick's spread** is 10° (the staff's: each bolt turned at random up to 10° either side of the aim, so the three may come out close together; a fixed fan would need a Triple of its own), round the lane.

### Plow (OB11)

A new modifier with a new behaviour (`ModifierBase.RULES` row): what the carrier hits rides along in front of it instead of being passed, and is let go with a shove at its end. A carried body pinned against a wall or a blocking footprint takes a pin of 2× the hit (heavy's slam is 1×). It carries every body but downed ones (players, enemies, mites); props never move. The carrier's contact damage applies to what it carries (contact hurts other teams only, so a carried mite takes none, but its pin kills it). On a flying shot it is a battering ram. A carried body can slip off sideways.

**Plow against a wall:** when the carrier would push a carried body into a wall, the move ends there as if it met the wall itself: the carried body takes the pin, and `on wall` fires (OB12) where the carried body meets the wall.

### `on wall` for moves (OB12)

`TriggerBase.NEEDS` lets `on wall` fire for a carrier that moves its caster along a path (a dash, not a teleport) when the move ends on a wall head on (OB10), carried bodies included (Plow). Flying shots are unchanged. `on wall · dash · pulse` works for players too: a wall bounce that bursts.

### Poses and layered bodies (OB8)

Today `CreatureLook` is built for a 32×32 stray: one square frame, a wind-up strip, a hurt frame, a hop, the face, and a texture, glow and size swap per phase. General additions:

- **Poses from states:** the look shows a pose for what the body is doing, read from states the game already has: idle, winding up, moving by its own move, met a wall, hurt, in a phase transition. Any enemy can have them (a splinter's dash pose).
- **Layered bodies:** a body drawn in parts (for the broom: the handle, the binding, the bristle head), each a frame of any size (not only square), that the game moves: the handle **leans** into the way it goes and back when it brakes; the head **lags** behind and squashes on the floor; the head **swishes** side to side while it moves; a wall hit **squashes and stretches** the handle and shudders the bristles. A few drawn frames for the extreme poses (wind-up, wall hit).
- **A death remnant:** a body at no health is freed at once (gameplay/combat), so the death pose is a remnant Feel leaves where it died (its parts flying apart), drawn only.
- **Motes that follow:** dust while it moves is its move's `stream` cue part, which exists. Sparks off the burning head all through phase 2 need a mote source that follows its body (a `MoteSource` stays where it was read, props.md); the look gets one.

All of it is drawn only (VIEW), never state.

**Built (OB8):** `BodyPose` and `BodyPart` in the actor kit (gameplay/actor), so any look can use them and Feel can read a dead body's parts; `CreatureLook` steps the pose and draws the parts; the remnant is Feel's (`remnants.gd`); a following source is `MoteSource.put`'s `follow`, and a phase's motes `PhaseLook.motes`. The poses are the table's states: idle, wind-up, its own move, a wall met (a dash that went less than half its way, once each time it is held up; OB10's "a head-on wall ends the move" and OB12's `on wall` will make it end there), hurt, a cast (the swat), the transition; "Phase 2" is its phase look. How each part moves is its own numbers in the boss's scene; the broom's are a first guess for OB9 to tune with its sheet. Not yet: a decoy of a layered body copies only its `Sprite` (`DecoyLook`), so it would show nothing; no card gives a boss a decoy today.

**Built (OB9), for the owner's review:** the broom's own face is a `FaceArt` (core/base) on its `Face`: its own eye and brow sheets in the shared layout at a frame size of its own (24×8), a second row for phase 2 (`PhaseLook.face_row`); its habits are still its `style`'s (the slow blink of an old staff). Its head is five drawn frames picked by `pose_frames` (IDLE 0, WINDUP 1, MOVE 0, WALL 2, HURT 0, CAST 3, TRANSITION 4), and the burning head the same five, its fifth the straw catching (only the burning head's fifth shows: the phase swaps the head as the transition starts). The idle tap is `BodyPart.tap`. The recorded preview is `tests/screenshots/shot_boss_looks.gd` (any boss, through the registry), so its frames are the game's own and will follow OB10-OB14's changes to the moves.

### Phase adds and player-count scaling (OB13)

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

- `Phases` starts the phase and sends a request on the bus (`adds_requested`); Flow, which spawns enemies already, stands them up. The phase's area and Flow never call each other. **Adds crumble when the body that called them dies;** the room is cleared when the boss is dead. Any enemy can have adds (an elite calling strays at half health).
- **Health by player count** (the enemy base's M3 promise, content/bosses/README.md): `EnemyBase.health_per_player`, the share of its health each player after the first adds. It is counted from the seats in play when the body enters; a seat joining or leaving later changes its most and its current health by the same share, so its health bar's share stays.

### The AI: run-up, turns and the aim lock (OB14)

General behaviours in gameplay/ai:

- **The run-up:** for a cast that moves its caster, the AI may first move to where that cast's line is longest (a wall's foot facing the open room). It makes the Big Sweep. Every dashing enemy gains it.
- **Turns:** a profile number that makes an enemy turn its casts to the player it last aimed at longest ago, so the Sweep goes round the party (the enemy AI's spreading, L3, spreads bodies round one target; this is new).
- **The aim lock** (decision 26): `aim_lock` on the profile, 0 by default; phase 1's profile locks at the wind-up's start, phase 2's for its last 0.25 s; measured against the cast's own wind-up left; a beat on the lane when it locks.
- **Round blocking props** (decision 36): the AI's line and detour checks treat the ground of blocking props (a pillar's footprint) as walls, so an enemy walks round a pillar instead of grinding into it.
- **A phase's new staffs start ready,** so the Big Sweep is the first move of phase 2; its staff's long cooldown (about 20 s) gives its pace after that.

### Sound (OB15)

The plumbing exists: a cue names a `sound` (core/base/cue_base.gd), silent until an `.ogg` exists. Missing, and general:

- **Held sounds:** a sound that lasts while something lasts (the cue `stream` part's counterpart: until its carrier ends, or a status or a phase ends): the scrape of a wind-up, the swish of a Sweep, the burning loop of phase 2, a held beam's hum.
- **Music with intensity:** `RoomBase.music` names a track; `EnemyBase.music` overrides it while that enemy lives; its phase raises the intensity. A track is a list of layers; the intensity says how many play, or which entry. One plain track is one layer, a phase-2 track a second entry (decision 25).
- **Rules:** sound is drawn-only like Feel, never fed back into the game; a limit of voices per sound (with the cues' `every`); position in the room.

**The sound sheet** (what the audio pass fills in; every id is named in its cue from the step its moment is built):

| Moment | Cue | Sound id | Length, loop | Notes |
| --- | --- | --- | --- | --- |
| Entrance | `boss_intro` | `boss_intro` | 1–2 s | Under the name banner |
| Sweep wind-up | the Sweep's `wind_cue` | `broom_scrape` | held | A telegraph: heard off screen |
| Big Sweep wind-up | the Big Sweep's `wind_cue` | `broom_big_scrape` | held | Louder and longer, known without looking |
| Sweep | the Sweep's move | `broom_swish` | held | The swish's rhythm |
| Wall hit | `broom_wall` | `broom_crunch` | short | With the pulse's own sound |
| Swat | `broom_swat` | `broom_swat` | short | |
| Pillar cracks, breaks | the prop's states | `pillar_crack`, `pillar_break` | short | |
| Dust heap scattered, explodes | the prop's states | `dust_scatter`, `dust_explode` | short | |
| Phase change | `broom_ignite` | `broom_ignite` | 2 s | The rattle, then the whoosh |
| Burning bristles | phase 2's look | `broom_burning` | held, loops | For all of phase 2 |
| Death | `boss_death` (exists) | `broom_splinter` | 2 s | |
| Music | the broom's `music` | `boss_broom` | loops | Phase 2 more intense |

### HUD: the boss bar and the entrance (OB16)

- When a boss body enters play, the actor sends `boss_shown(actor, name, lore, marks)` on the bus (marks: each phase's health share); its health comes through the health events the HUD already hears, and `enemy_died` ends it.
- One bar at the top for everyone while a boss lives: its name, its health, a mark at each phase. The entrance banner shows its name and lore line for a few seconds, over play, stopping nothing.

## The broom's data

Starting values, tuned in OB17. Damage is at power 2 (phase 1) and 2.5 (phase 2); a wizard has 100 health today.

**The data:** `content/bosses/old_broom/` (an `EnemyBase` with `boss = true`, its scene, art, `assets.json` and its test). The bosses README is rewritten in OB3 for what a boss is now: enemy data, staffs and phases, no script of its own (docs/milestones/M2-enemy-ai.md).

**Its staffs** are its own, sub-resources of its `.tres` (decision 28; not in `content/wizard/staffs/`, which is the players' item pool): enough slots for their lists, and the staff's `wind_up` is the telegraph (0.8 s in phase 1, 0.6 s in phase 2), so no card slows a player's wind-up for it.

**Stats:** power 2 (phase 2: 2.5), mass about 6, spell scale about 1.5, resist about chill 0.6, burn 0.3, possess 0.7. Contact damage 8. A 96×64 body. Health: about 90 s for one player; `health_per_player` about 0.7.

**Phase 1, "Tidying up":**

| Staff | Cards | Damage |
| --- | --- | --- |
| Sweep | `on wall · bigger · lumber · plow · dash · pulse` | pass about 8, pin about 16, ring 8 |
| Big Sweep (from OB14) | `on wall · reach · reach · bigger · bigger · lumber · plow · dash · pulse` | as the Sweep; about 610 px long, a front about 3× its body wide |
| Dust flick | `triple · slow · bolt · slow · bolt · slow · bolt`, a 10° spread (OB10, decision 34; was `scatter · slow · bolt`) | about 10 a bolt (to tune) |
| Swat | `bigger · heavy · swing` | about 5, and a 5 slam |

Caught, carried and pinned costs about 8 + 8 (contact) + 16 = 32; slipping off sideways costs 8.

**Phase 2, "Spring cleaning"** (health below 0.55, transition about 2 s, the burning look, power 2.5): the Sweep staff holds two Sweeps, each `timer · on wall · bigger · lumber · plow · dash · slow · fire · pool · pulse` (the timer's payload, a slow fire pool, every half second or so while it moves: two or three burning patches a Sweep, each lasting about 12 s; then the ring), cast one after the other with their own wind-ups. The Big Sweep, the flick and the swat stay. Adds: crypt mites, 4 + 2 per player at once, then 2 + 1 per player every 10 s, at most 6 + 2 per player alive.

**Pacing:**

| | Phase 1 | Phase 2 |
| --- | --- | --- |
| Wind-up (the lane) | 0.8 s | 0.6 s |
| Aim locks | at the wind-up's start | 0.25 s before release |
| Sweep | about 1.1 s: 300 × 0.85 × 0.85 ≈ 217 px/s over 80 × 3 = 240 px | the same, twice |
| Recovery | 0.4 s | 0.3 s |
| Next Sweep | about every 3.5 s | about every 3 s |
| Big Sweep | about 3.3 s over about 610 px, every 20–25 s | first at the phase's start |

**Look:** its own face (an old staff's, not a stray's), the layered body, and the poses:

| State | Pose |
| --- | --- |
| Idle | Hovers upright, bristles swaying, taps the floor impatiently |
| Wind-up | Rears back, bristles lift and spread, brows furious; the lane shows |
| Sweep | Leans hard forward, swish swish, dust off the bristles |
| Wall hit | Crunch: squash, the shudder, a puff of dust all round with the ring |
| Swat | A sharp half turn, bristles fanning out |
| Transition | Shakes hard, embers catch, then the bristles burst into flame |
| Phase 2 | Burning head, sparks off every swish, an angrier face |
| Death (remnant) | Splinters, the bristles scatter, the bound head flies off |

**Readability:** enemy telegraphs are drawn in Fire colours (docs/STYLE.md), and so is phase 2's burning floor. OB17 checks the two apart in play (the lane bright and moving, the patches low and still) and changes the patches' look if they blur.

## The arena and its props

`content/rooms/crypt/boss_broom/`: about 1.7× a crypt room, an open middle, walls all round, four **cracked pillars** in a loose diamond, a few **dust heaps**, the broom listed in its `enemies` (decision 31), following the crypt's rooms (`follows`, decision 32), and no exit: cleared, the run is won. It is the broom's best room, not its only one: the fight works in any room with whatever cover it has (decision 17).

- **Cracked pillar** (`content/props/cracked_pillar`, built in OB5): intact, cracked (shown at half health), then gone (rubble that no longer blocks and is not hit). Its health is two of the Sweep's wall hits (the pass and the ring, it is a body like any other); spells chip it. Data and art only.
- **Dust heap** (`content/props/dust_heap`): a body passing through it scatters it (a state that no longer blocks and stays where it is); fire on the heap or the scattered dust makes it explode (a blast cast), hurting everything near, the broom included. **It needs one new prop trigger, `touched`** (a body overlaps its area; `PropTrigger` has none today), built with it in OB5 (done: the heap's area reaches past its ground, so a body stopped at its edge touches it).

New props show up in the hub's prop yard by themselves.

## Steps

| Step | What | Areas |
| --- | --- | --- |
| OB1 | This document | docs |
| OB2a | **No waves** (decisions 30, 31): the trial gate's first build taken out; rooms list their enemies (`RoomBase.enemies`), arena_01 lists its imps; a room cleared with nowhere after it wins the run, back to the hub; the wave and build-break code, events and HUD lines go, and the tests, bots and runners that used them start a run of rooms; the Sandbox's enemy arena lists bosses (`EnemyBase.FOLDERS`) | core/base, content/rooms, gameplay/flow, core/events, hud, tests |
| OB2b | **Paths and exits** (decision 32): `RoomBase.follows`, the `room_exit` prop (lit when the room is cleared and every wizard stands on it), the next room started in the same run, each room's exits held to its next rooms by a test | core/base, content/props, content/rooms, gameplay/flow |
| OB2c | **The lectern** (decision 33): the prop, `start_room_picked`, the party's start room on the stone line, and the lectern's room menu | content/props, content/rooms/hub, gameplay/flow, hud |
| OB3 | **The broom v0**: two phases with today's parts, on its own staffs (sub-resources of its `.tres`). Sweep `bigger · dash` with `reach` (Lumber joins in OB4, Plow in OB11, the dust ring `on wall · … · pulse` in OB12), flick `scatter · slow · bolt`, swat `bigger · heavy · swing`, phase 2's trail `timer · dash · slow · fire · pool`; contact 8; a placeholder 96×64 sprite and a burning phase look; its lore line (a one-line `lore` on `EnemyBase`, checked by the story validator's line rules) and its canon in docs/STORY.md; the bosses README rewritten as a guide (decision 29) | content/bosses, core/base, docs |
| OB4 | **Lumber**, its numbers; the broom's Sweep takes it | content/spells |
| OB5 | The cracked pillar; the dust heap and the `touched` prop trigger | content/props, core/base, gameplay/actor |
| OB6 | The arena | content/rooms |
| OB7 | Actor stats; the broom gets power, mass, spell scale and resists | core/base, gameplay/actor, gameplay/combat, core/spells |
| OB8 | Poses from states, layered bodies, the death remnant, following motes | gameplay/ai (look), gameplay/feel |
| OB9 | **The broom's look: an animation sheet and a recorded preview of every pose, for the owner's review.** OB10 to OB16 do not wait for it; OB17 does | content/bosses |
| OB10 | Moves: speed curves, a pass as wide as the body, a head-on wall ends the move; the broom's dust flick aimed (decision 34) | core/spells, native, content/bosses |
| OB11 | **Plow**; the broom's Sweep carries and pins | core/spells, gameplay/combat, content/spells |
| OB12 | `on wall` for moves; the broom's dust ring | core/spells |
| OB13 | Phase adds and health by player count; the broom's mites | core/base, gameplay/actor, gameplay/flow |
| OB14 | The AI's run-up, turns and aim lock (decision 26); walking round blocking props (decision 36); the Big Sweep; the phases' locks | gameplay/ai, gameplay/feel (the lock's beat), content/bosses |
| OB15 | Held sounds; music with intensity; every sound id of the sheet in its cue | gameplay/feel, core/base, content/cues |
| OB16 | The boss bar and the entrance banner | gameplay/actor, hud |
| OB17 | Tuning with bot playtests and the owner's; readability of fire on fire; a GIF of the whole fight; **the deletion check** (decision 28) | content/bosses |

Each step's tests come with it: a card's test in its folder and the card-rules test (`tests/core/test_card_rules.gd`) for Lumber, Plow and `on wall`; the content determinism tests pick up the broom, the props and the room by themselves (`test_content_determinism.gd` already reads `bosses`; `test_snapshot_game.gd`); the stats in the state and snapshot tests; the native kernels' byte-for-byte tests for OB10.

## Fit with the design

- **Deep spell building:** the boss is cards a player can hold (Lumber and Plow are new cards for everyone); the fight rewards fire (heaps), the Wall card (`on wall`), decoys, `on kill` (mites) and possession.
- **Nobody waits:** no cutscene; the entrance plays while everyone moves; a revive stays possible (Plow leaves the downed); trying rooms goes by everyone picking the same room and walking into the trial gate together (decision 27).
- **Readable chaos:** every attack has a wind-up and a lane (and later a sound); the Sweep stays one lane at every player count; the lane follows the aim and shows its lock (decision 26).
- **Everything hurts everything:** the broom's own fire blows up heaps on it, its pins kill its own mites, players' spells break the pillars that shelter them.
- **One game, the same everywhere:** every new number is the body's state; poses, remnants, motes and sound are drawn only.
- **Fair from 1 to 4 players:** health and adds scale with players; the attacks do not multiply.

## Not in this plan

The boss in a run's room order (M3, Run structure), its rewards (enemy cards as rewards, M3–M4: Lumber and Plow are candidates), the sound files and the music themselves (decision 24), the other bosses.

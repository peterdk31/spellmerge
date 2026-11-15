# Run generation: a run defined as data, its map generated

**Status (2026-11-15): approved by the owner** (after answering the plan's three questions: "Merge it"); this document is the plan. **RG1 done (2026-11-15):** the data (`RunDefinition`, `MapRules`, `KindRule`, `RoomKind`, `RunContent`), rooms' `biome` and `kinds`, enemies' `biomes`, `cost` and `min_depth`, `content/runs/crypt.tres` and the validators (`Registry.validate_runs`). The room kinds have a registry folder of their own, `content/room_kinds/`, rather than `content/rooms/kinds/`, so the list of rooms never holds one. **RG2 done (2026-11-15):** `RunMap`, `RunNode` and `RunGenerator` (gameplay/run), and `MapRules.room_budget` (16, the enemy budget of a fight room before RG5's scaling); no kind is placed where it would leave a later row no line (a row is narrower than `width_min` only where the limits allow no more); a room led to by kinds no one line may follow (`not_after`) is tried again with other rolls, then named. **RG3 done (2026-11-15):** the run's area (`Run`, gameplay/run/run.gd) makes the map when Flow begins a run of rooms (`run_begun`, on the run's fresh state) and names the first room and its enemies (`run_room_chosen`), which Flow builds; `RoomBase.enemies` and `RoomEnemies` went; Play and the hub's stone start the generated `crypt` run (`Flow.run_id_to_play`), and a test that plays a room of its choosing pins it as a run of that one room (`tests/support/pinned_run.gd`). A run whose map cannot be made is found after the hub went, so the stone's party goes back to the hub. **RG4 done (2026-11-15), before RG3b:** the `room_exit` prop (content/props/room_exit: `dark`, `lit`, a 48×48 area), two in the crypt arena; a template stands only for a room with no more links than its exits (`RoomBase.exit_count`, `RunContent.templates_for`), and a kind that leads on needs a template with exits for the most ways (`MapRules.exit_problems`); Flow's `ExitRules` lights one exit a way, left to right, once the room is cleared, and tells the view the kind behind each (`room_exits_shown`: Feel shows its name); every standing wizard in one lit exit sends `run_way_taken`, the run moves on through its map and Flow enters the next room in the same world and run, the party as it is (a downed wizard up with the revive's health); the last room cleared wins the run; a snapshot's later room is laid out again (`Flow.rebuild_derived`). **RG3b done (2026-11-15):** three more crypt fight rooms (`arena_02` the nave, `arena_03` the ossuary court, `arena_04` the crossing; content/rooms/README.md), each with two exits as the arena, and arena_01's layout, art, pillar and torch tests now check every template found by folder (`tests/content/rooms/test_template_*.gd`), with a screenshot of each (`shot_rooms`). **RG5 done (2026-11-15):** the run definition's `scaling` (`RunScaling`: `per_depth` and `per_player`, each a `ScaleCurve` of `start`, `end` and `easing`; core/base); each room's scale (`RunNode.scale`) is worked out by the generator from its depth and the run's players, the seats joined at its start (`run_begun(run_id, players)`, `RunMap.players`), and grows its enemy budget (`RunScaling.scaled_budget`); the new difficulty area (`Difficulty`, gameplay/difficulty) hears it as the party enters the room (`run_room_scaled`), keeps it as the level and scales every enemy and boss as Flow stands it (`enemy_standing`, `Actor.stat_scale` on its data's health). The crypt: 1.5 times by its deepest row, 1.3 times with four players (the budget and every health both grow by it, so a room of four holds about 1.7 times the health of one player's). The 4-bot smoke test plays the run unscaled: three of its four seats fight. A wizard joining later plays the run as it was made. The room's scale is not `difficulty_changed`, which stays the difficulty setting's level for the enemies' skill (enemy AI AI10), so depth and players never make enemies aim better. **RG6 done (2026-11-15):** meta progression's hook: a rule change (`RunRuleChange`, core/base; `RunDefinition.changes`) names a save flag and one number it changes (a kind rule's weight or limit, the depth, the width, a scaling curve's start or end; set, add or times); the run's unlocks (`RunUnlocks`, core/sim: the save flags it plays by) are taken at the run's start (`Sim.unlocks`, `Frames.next_run_unlocks`) from the replay's header while one records or plays, else from this machine's save (the Run area's `unlocks_now`: only the flags some rule change names, `SaveFile.flags_among`), and a replay carries them (format 9), so a guest playing the host's run, and every replay, plays by the host's save; the Run area makes the map of `RunDefinition.changed_by(unlocks)`, a copy with the held changes applied, so the generator stays pure and the registry's definition never changes; the validator names a change that names nothing and rules a flag leaves that make no map (each flag alone and all at once). No change exists yet and no flag sets one. **The boss joined (2026-11-15, boss plan OB6):** its arena hosts `boss` in the crypt, so the crypt run now ends in the boss's room, its boss from the boss pool. **RG7 done (2026-11-15):** the lectern, `content/props/start_lectern/` (a stone stand with an open book, role `start_lectern`), stood in the hub's zone of that name by its role (`RoomContents.stand_in_role_zones`: a zone named for a prop role stands the registry's prop of it), so the hub's scene never names it; the hub's rules tell who stands at it (`lectern_changed`); a seat's A there opens its menu of the stone's run's depths ("Room 1", ..., "The boss": the run definition's `start_depths()`, its first biome's `depth_max`), whose pick is the command `start_depth_picked(depth)`, the party's one setting (`HubRules.start_depth`, hashed), told with the depths (`start_depth_changed`) and named on the stone line's second line ("Starts in: Room 3"); the stone's run is made as always and entered at the first room by number of that depth's row (`run_begun`'s `start_depth`, `RunMap.start_at`: the last depth always the map's last row, a pick past a shallower map its deepest row before the last). A hub started anew forgets the pick (a joining machine starts the hub from the replay's header, which has no word of it). Deleting the lectern's folder leaves the zone empty, the setting unset and the run unchanged. **Known gap:** the menu lists the deepest map's depths (the crypt's 6), since the map is made only as the run starts; on a shallower map (4 or 5 rows, by the seed, or fewer through a rule change) a pick past its rows starts in its deepest row before the last while the menu and the stone line still name the pick ("Room 5"). "The boss" is always the last row. Showing the real depth needs the map before the run (the seed dealt in the hub); for a testing aid it is left so (RG8's map, made only in the run too, does not change it). **RG8 done (2026-11-15):** the map on screen: the run area tells the map as the party sees it (`run_map_changed(rows, kinds, links, at)`: every room's row, kind and links, and the party's room) as the party enters each room, empty at every run's start, again after a snapshot's restore; the pause menu has a **Map** page (its row only in a run of rooms) that draws it (`hud/widgets/run_map_view.gd`: the rows top to bottom, a line a link, each kind's first letter named under the map, "Room 3 of 6", the party's room in gold, the rooms out of its reach dim), view only. No button opens it on its own: the gamepad has none free (Select is the inventory's, Start the pause menu's), so the pause menu is the way in. Opening the pause menu stops the game for everyone, as it always does; a look at the map that stops nobody (a corner map, or one held open) is left for later. The run generation plan is done. It replaces OB2b and OB2c of [boss-old-broom.md](boss-old-broom.md) (decisions 30-33: OB2a, no waves, stays done) and builds the core of M3's run structure early ([docs/PLAN.md](../PLAN.md): the `run`, `flow` and `difficulty` areas).

The steps are **RG1 to RG8** (RG for run generation). Each is one PR with its tests, in order.

## What the owner asked (2026-11-15)

"What I actually want is a way to define a run. Biome, number of rooms, settings per room (maybe scaled by difficulty), spawn types, bosses, reward rooms / healing rooms etc. Then I think the rooms and the path should be auto generated and filled with enemies and rewards. So a way to define which features a run should include and then generate a complete run (out of the available levels)."

The answers, the same day:

1. **A branching map,** "randomized but following rules. These rules can then change based on meta progression on a savegame (using the host's world)."
2. **Fights, and a boss fight at the end.** "The other room types will come later and automatically work!"
3. **No reward rooms yet.**
4. **"Scale everything.** But no need to pick a difficulty for now."

## What the players see

- **Through the teleporter,** the party stands in the first room of a run nobody has seen before: the same crypt rooms, met in another order, with other enemies in them, every run.
- **A room is a fight.** Its enemies stand as it starts; when the last is down, its **exits** light up: one exit per room the map lets it lead to, each showing what lies behind it (a fight, the boss).
- **The party picks the way by walking** (the door rule, docs/DESIGN.md): an exit takes the party on once every wizard stands in it, with no button (owner, 2026-11-15). Nobody picks for anyone; a wizard who walks elsewhere simply holds that exit dark.
- **Deeper is harder:** more enemies, tougher ones, and every number on them scaled up with depth and with the number of players.
- **The last room is the boss's.** Won, the party is back in the hub; everyone down, the same, with nothing of the run.
- **For testing,** the hub's lectern can make the teleporter start the generated run at any depth of its map, the boss's room included; the run is otherwise the same run.

## Owner decisions (2026-11-15)

1. **A run is defined as data:** a run definition says which features the run has; the game generates the complete run from it and the content there is. No hand-made chain of rooms.
2. **The map branches,** generated at random within rules the definition gives.
3. **The rules can be changed by meta progression** on the host's save; online, the guests play the host's run.
4. **Room kinds now: fights and the boss's.** A new kind of room later (rewards, healing, shops, events, elites) is a new kind in the data and its own room behaviour, and the generator places it by the same rules, with no change to the generator.
5. **No reward rooms yet.**
6. **Everything scales** with depth and the number of players; no difficulty setting is chosen for now (the scaling has a place for one later).

## The model

Everything a run is made of is found by folder, and each piece says where it belongs, so new content joins runs by being added and deleting it touches no other file (the boss plan's decision 28: the Old Broom deletable by its folders):

- **A run definition** (`RunDefinition`, core/base; one per kind of run, `content/runs/<id>.tres`; the first is `crypt`): its **biomes** in order (one for now: `crypt`), and for each biome its **map rules** (`MapRules`):
  - the **depth**: how many rooms deep the map is (a range: `depth_min`, `depth_max`), the last row being the boss's;
  - the **width**: how many rooms a row may hold (`width_min`, `width_max`) and how many ways a room may lead on (`branches_min`, `branches_max`), with the rule that every room can be reached from the first and leads to the boss (no dead ends, no orphans);
  - the **room kinds** by row: a table of which kinds may stand in which rows and how often (`KindRule`: a kind, the rows it may take, its weight, how many at most in a row and in the run, which kinds may not follow it). Today the table says: every row a fight, the last row the boss. A reward or healing room later is one more line ("one healing room in the row before the boss"), and the generator follows it;
  - the **scaling**: how the run grows harder with depth (`scaling`, below).
- **A room template** (the room's `.tres`, `RoomBase`, as today, in its biome's folder): its **biome** (`biome`, `&"crypt"`), the **kinds it can host** (`kinds`: `fight`, `boss`), and its layout as now (spawns, props, its exits, below). **Rooms hold layout only again** (content/rooms/README.md): what fights in a room comes from the run, so OB2a's `RoomBase.enemies` goes in RG3 (the generator fills every room). A room offered for no run (the hub, the sandbox) hosts no kind.
- **An enemy says where it fights** (its `EnemyBase`, as data): the **biomes** it appears in, its **cost** in a room's budget, and from which depth it may appear (`biomes`, `cost`, `min_depth`). The enemy pool of a biome is every enemy that names it, found by folder; a boss names its biome the same way under `content/bosses/` (the Old Broom: `crypt`), so the boss pool is found too.
- **A room kind** (`RoomKind`, content/room_kinds/<id>.tres: `fight`, `boss`): what a room of that kind is for the game: how it is filled (`fill`: an enemy budget from the pool; the boss pool) and what ends it (its enemies down). A new kind (a reward room) is a new file and the behaviour its `fill` names, built with it.

## The generator (RG2)

**One generation at the run's start, from the run's seed** (`sim.chance`, core/sim/README.md, "Chance"): the same definition, rules, content and seed give the same map on every machine, in every replay and after every snapshot. The map (`RunMap`: rows of nodes, each node its kind, its room template, its links to the next row, and what fills it) is the run's state, hashed and saved in snapshots; a joining machine never generates its own.

1. **The shape:** the depth and each row's width within the rules; links from each room to the next row within the branch limits, never crossing over one another (so the map reads cleanly when it is drawn), every room reachable and leading to the boss.
2. **The kinds:** row by row, the kind rules' table, by weight, within their limits (today: fights, then the boss).
3. **The templates:** for each node, a template of its biome that hosts its kind, by chance, a template not used twice in a row on one path while others are left.
4. **The fill:** for each fight, enemies from the biome's pool whose `min_depth` it has reached, by chance, until the room's budget (its scaling at that depth) is spent; for the boss, a boss from the pool. Ids, never files.

The generator is one pure function from (definition, rules, content, seed) to a map. It reads no node and plays nothing, so its tests run thousands of seeds: every rule holds, the same seed gives the same map, and deleting any room, enemy or boss still gives a valid map (or a clear message when the content left cannot make one: no boss for the biome, no template for a kind).

## Exits and the way on (RG4)

- **An exit is a prop** of the role `room_exit` (content/props, self-contained, as the hub's stone: it says what it is and where it is stood on), placed in a room's scene, as many as the room may lead to (a room template with fewer exits than a node's links is not picked for that node). Dark until the room is cleared; then each exit with a link lights and shows the kind of room behind it (view only), the rest stay dark.
- **Every wizard in one lit exit** takes the party on, with no button (owner, 2026-11-15: "Just everyone stepping into it"); stepping in is position only, so it is the simulation's own and needs no command. The next room starts in the same run and the same recording, the party as it is (health, staffs, everything; the start staffs are not dealt again), the map and the depth moving on.
- **The boss's room has no exit:** won, the run is won (back in the hub, as OB2a does now).

## Scaling (RG5)

"Scale everything": one scale for each room from its **depth** and the **number of players** in the run, applied to:

- the room's **enemy budget** (how many and how costly),
- every enemy's and boss's **health**, **damage** (its power) and **spell size** (its spell scale), through the actor stats of the boss plan's OB7 (`ActorStats`), so nothing is tuned per enemy in code;
- what the boss brings with it (its phase adds, OB13).

The curves are numbers in the run definition (`scaling`: per depth and per extra player, each a start, an end and an ease, as the cards' speed curves are), so the owner tunes them in data. A difficulty setting later is one more factor in the same place. Until OB7 lands, RG5 scales the budget and health; the rest joins the day actor stats exist.

## Meta progression (RG6)

- **The rules a run uses are the definition's, changed by what the save has unlocked:** a **rule change** (`RunRuleChange`, data) names a save flag and what it changes (a kind rule's weight or limit, the depth, the width, a scaling factor). Today no change exists and no flag sets one: RG6 builds the hook and its test, and the first unlock arrives with meta progression (M4).
- **The host's world decides:** the rules in effect are worked out on the machine that starts the run, from its save, and travel with the run's start (in the replay's header, as the party and the run's rules do today, core/sim/README.md), so every machine and every replay generates the same map from the same rules. A guest's own save changes nothing.

## The lectern: where the teleporter's run starts (RG7)

The boss plan's decision 33, on the generated run: a seat's A at the lectern opens its menu of the map's **depths** ("Room 1", ..., "The boss"); its pick is the command `start_depth_picked(depth)`, the party's one setting (hub state, hashed), shown on the stone line. The stone's run is generated as always and begins at a room of that depth (the first by id among that row's nodes) instead of the first; everything else is the same run. Deleting the lectern's folder leaves the setting unset and the run unchanged.

## Data first: the first crypt run

- `content/runs/crypt.tres`: the crypt, 4 to 6 rows deep, 1 to 3 rooms a row, each room leading on to 1 or 2, fights then the boss.
- The crypt's room templates: arena_01 (fight) and two or three more fight rooms (RG3b, layout only, made like arena_01), and the boss's arena when OB6 brings it (`kinds: boss`). Until then a test run's boss row stands a crypt fight room tagged `boss` for tests only (a test template, never in content) and the real run has no boss row: **the crypt run with no boss in the registry ends at its deepest fight** (a won last room wins the run), so the game plays before the broom exists. (Done in OB6: the crypt run now ends in the broom's arena.)
- The crypt's enemies name `crypt` with a cost; the broom names `crypt` from OB3.

## Steps

| Step | What | Areas |
| --- | --- | --- |
| RG1 | **The data:** `RunDefinition`, `MapRules`, `KindRule`, `RoomKind` (`fight`, `boss`), room templates' `biome` and `kinds`, enemies' `biomes`, `cost`, `min_depth`; `content/runs/crypt.tres`; validators and their tests (every definition's rules can make a map from the content there is) | core/base, content/runs, content/rooms, content/enemies |
| RG2 | **The generator:** `RunMap` and the pure generator (shape, kinds, templates, fill) from the run's seed; thousands of seeds through every rule; the map as state (hash, snapshot) | gameplay/run (new area, docs/PLAN.md) |
| RG3 | **Rooms filled by the run:** a run starts at the map's first room, filled as the map says; OB2a's `RoomBase.enemies` goes; the bots and tests start generated runs | gameplay/run, gameplay/flow, core/base, content/rooms, tests |
| RG3b | **More crypt fight rooms** (two or three, layout only), so a map has templates to choose from | content/rooms |
| RG4 | **Exits:** the `room_exit` prop, its lighting, what each exit shows, every wizard on a lit exit takes the party to the linked room, the depth moving on; the boss's room won ends the run | content/props, gameplay/flow, gameplay/run, gameplay/feel |
| RG5 | **Scaling:** the definition's curves, the room's scale from depth and players, applied to the budget and health (power, spell size and adds as OB7 and OB13 land) | gameplay/difficulty (new area), gameplay/run |
| RG6 | **Meta progression's hook:** rule changes keyed by save flags, worked out from the host's save, in the run's start and the replay's header | core/base, core/save, core/sim, gameplay/run |
| RG7 | **The lectern:** the prop, `start_depth_picked`, the stone line, the lectern's depth menu | content/props, content/rooms/hub, gameplay/flow, hud |
| RG8 | **The map on screen:** a small map of the run (rows, links, kinds, where the party is), opened from the pause menu or a button, view only | hud |

Each step's tests come with it. The boss plan's OB6 (the arena) then tags its room `boss`, and OB3 gives the broom `biomes: [crypt]`: the boss joins the crypt run by its own data.

## Fit with the design

- **Nobody waits; shared decisions by walking:** the way on is chosen by every wizard standing on one exit; the lectern is a dev setting for the party, not a choice made for others.
- **One game, the same everywhere:** the map is generated once from the run's seed and the host's rules, and is the run's state.
- **New content = new files:** a room, an enemy, a boss, a run or a room kind joins by being added, and goes by being deleted.
- **Fair from 1 to 4 players:** the budget and every number scale with players, never the number of rooms.
- **Short loops:** 4 to 6 rooms and a boss is a short first run (docs/DESIGN.md: 20 to 30 minutes for a whole run of several biomes, later).

## Answered by the owner (2026-11-15)

7. **Taking an exit: everyone stepping into it,** no button.
8. **The first run's size:** 4 to 6 rows deep, 1 to 3 rooms a row, each leading to 1 or 2, until the owner tunes it ("Ok").
9. **Between rooms:** the party carries everything into the next room as it is (health, mana, staffs); downed wizards stand up at the next room's start with the revive's health ("Ok").

## Not in this plan

Reward, healing, shop and event rooms (their kinds plug into RG1's data and RG2's rules later); unlocks themselves and what sets them (M4, meta progression); several biomes in one run (the definition holds a list from RG1, the generator plays one until a second biome exists); door voting beyond the walking rule; a difficulty setting.

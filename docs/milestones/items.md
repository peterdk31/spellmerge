# Items: things a body picks up, holds in bags and drops

**Status (2026-11-13): planned with the owner in an owner session** (the owner, after the last round: "Go ahead"); this document is step I1. I2 to I5 are built (below, "I2 done" to "I5 done"); I6 is next. Asked by the owner: "Let's design a plan for having item pickups in the game. The first thing we need is staff pickups."

The steps are **I1 to I9** (I for items). Each is one PR with its tests, in order.

## What the players see

- **Things lie on the ground:** staffs first, then cards, later relics and potions. Near one, a button hint shows with a small tooltip: its name, and for a staff its numbers and its row of cards.
- **A takes it.** A staff goes onto a free hand if there is one, else into the staff bag. If the bag for that kind of item is full, the hint shakes red and nothing is taken; the player opens the inventory and makes room.
- **Select (Tab) opens the inventory:** a ring of four bags, Staffs, Cards, Relics and Potions, each with how full it is (`2/4`, or `2/∞` for a bag with no limit). Enter a bag to see what is in it and drop things. Cards drop one at a time.
- **A staff is put on a hand in the inventory:** point at a staff, press the hand's own button (RB, RT, LB, LT). A column beside the ring lists the four hands with their staffs, each number with a green or red arrow against the staff pointed at.
- **B is still the builder,** and it builds every staff the player owns: the four hands first, then the staffs in the bag.
- **Cards are counted.** A card put in a staff is out of the bag; taken out, it is back. A card with none left is not in the bag.
- **The hub has a rack:** one staff with a crazy build, lying there as any item does. Players start with two staffs (RB and RT).
- **Possessing a body shows that body's things:** the panel, the builder and the inventory are the driven body's, and what is picked up goes to it and stays with it. The player's own wizard shows a health bar over its head meanwhile.

## Owner decisions (2026-11-13)

1. **Cards are counted;** the dev bag holds 20 of each. A card with none left is gone from the bag, not greyed out.
2. **A card is an item.** The cards move to the new system; a staff item holds an ordered row of cards, not a type of its own beside them.
3. **Every bag has one capacity, counted in copies, shown as x/y** (`x/∞` with no limit), raised later by meta progression. Staffs, Cards, Relics and Potions for now; no "coming later" entries, an empty bag is just empty.
4. **The staff bag is a regular bag** (no limit for now); a staff is put on one of the hands, each a button (RB, RT, LB, LT for now). A player may hold fewer than four, down to none, and starts with two.
5. **A staff off a hand keeps its cards and its mana and regains none** (on the ground or in the bag), so a swap is no refill.
6. **Picking up is one rule for every item:** if there is room, A takes it; if not, the hint shakes red (it names no bag: the player sees what the item is). No swap menu, no piles on the ground, and no taking cards out of a staff on the ground: take the staff, then use the builder.
7. **The hub's rack is ordinary items,** not endless and with no rules of its own. One premade staff for now.
8. **The inventory opens on Select (Tab); B stays the builder.** Leaving the game is a row in the pause menu and has no key of its own.
9. **The builder builds every staff in the bag,** not only those on hands.
10. **During a possession every menu and the panel show the possessed body** (the first one hit, when several are possessed), and its cards and staffs can be rearranged and dropped. This replaces "the seat's panel and builder are always its own wizard" (2026-10-28). The wizard's health shows as a bar above the wizard.
11. **What a run's start takes along is the whole player:** every bag, with room for more later (a name, colours).
12. **Enemies may take items and use them** (a plan entry, I9). Picking up is keyed by actor from the start.
13. **Low coupling throughout,** "so systems and behaviour can be changed later if we need to. Eg. the way to pickup items could be tweaked."

## The model

**A stack** is anything held or lying on the ground: a kind, an id, a count, and for a staff its slots and its mana. The id is the content's own (`bolt` under the spells, `dev` under the wizard's staffs), so no item wraps another file.

**A card's `.tres` is the item.** It already has an id, a name, a description and an icon.

**A staff item** (`StaffItem`, core/base) is a premade staff as data: an id, a name, its `StaffBase` and its card ids by slot. One folder each under `content/items/staffs/<id>/`, with its own test. A staff a player has built is the same thing as state: its `StaffBase`'s id and its slots.

**Kinds are rules.** One table (`ItemKinds.RULES`, core/items; the shape of `ModifierBase.RULES`) answers the same questions for each kind, so the bags, the ground and the menus never name a kind:

| Question | staff | card | relic (later) | potion (later) |
| --- | --- | --- | --- | --- |
| Which bag? | staffs | cards | relics | potions |
| Does it stack? | no | yes | no | yes |
| Where is its content? | `wizard`, `items` | the spells | `relics` | later |
| What can be done with one held? | drop, put on a hand | drop one | drop | drop, use |

A new kind is one row and its own code.

**An inventory** (`Inventory`, a component of the actor kit) is on every actor that can hold things:

- **Bags:** each a kind, a capacity (-1: none) and its stacks. A bag's capacity is one of the run's rules (`SessionRules`), never read from the machine.
- **Staffs** each have a number that is stable in their inventory. The builder's requests and the hands name that number.
- **Hands:** a small table, one entry a button, each a staff's number or none. How many hands there are is data.
- **The caster knows only the staffs on hands.** The inventory owns the staffs; it hands the caster what is on each hand, and a staff in the bag is compiled only for the builder's preview.
- An enemy's staff bag is the staffs it holds today; its other bags are empty.

**The player loadout** (`PlayerLoadout`, core/sim; replaces `RunCarry`) is what a run's start takes along for a seat: its bags, its staffs by number and its hands. It is written in tagged sections, so a later section (a name, colours) is added beside the bags without changing theirs, and read as strictly as today: every count, length and id is checked, a section it does not know rejects the header. From the hub into a run, and nothing back (owner, 2026-11-10), as before.

## The ground

**An item on the ground** is a row of the Items area (`gameplay/items/`, a new area that joins the Tick): its number, where it lies and its stack. It is not a body: nothing hits, pushes or is blocked by it. It is state, the same on every machine, saved and restored with everything else. It belongs to the room it lies in.

- **Placing one in a room:** an `ItemStandIn` (tools/, a `RoomPlacement` as a prop's stand-in is) in the room's scene, with the item picked in the Inspector. The hub's rack is one of these.
- **A drop** lands a step from the body, at a free spot found the same way on every machine, on the side away from the item the body would take next (so a drop is not picked straight back up).
- **Drawing** is a look in Feel, view only.

## Picking up

How a body picks up is one small policy (`PickupRule`), apart from the bags and from the ground, so it can change alone (decision 13): its reach, which item is the one in reach (the nearest), and what a take does.

- Each tick the Items area finds, for each seat's driven body, the item in reach, and says so when it changes (`item_near_changed`): the HUD draws the hint and the tooltip from it.
- **A** (`accept`; F on the keyboard as well) with no menu open asks for it (`item_take_requested`, a command). In order, A is: the hub's lit stone, an item in reach, the altar.
- The simulation checks the request (the item is still there and in reach, the bag has room), applies it and says what happened (`inventory_changed`, `ground_item_changed`), or refuses (`item_refused`: the hint's red shake). Two bodies asking for one item in one tick: the first in seat order takes it.
- Asked by actor id: a seat's request is one caller, an AI's another.

## The menus

All three are per player, never pause, and send requests as commands; they hold no rules.

**One shared widget** (`RadialMenu`, hud/widgets): the ring, pointing with the stick or the mouse, the layers (enter a sector, go back), the hint row and its glyphs. It is pulled out of `radial_builder.gd` first, with no change in behaviour, and the builder and the inventory are both built on it.

**The inventory** (Select; Tab):

- **The first ring:** the four bags, each with `x/y`.
- **Staffs:** every staff owned, those on hands marked with their button. Pointing at one shows its numbers and cards, and the hands column with its arrows. A hand's button puts it there (the staff that was there goes back to the bag); the button of the hand it is on takes it off. Drop puts it on the ground.
- **Cards:** the kinds, then the cards with their counts. Drop puts one on the ground.
- **Relics, Potions:** empty.
- **The arrows:** which way is better for each of a staff's numbers (more slots, a shorter cooldown) is a small table beside `StaffBase.ranges()`.

**The builder** (B; E): as today, with a strip of staffs in place of four tabs (the hands first, each with its glyph, then the bag's, scrolling), counts on the ring's cards, and a card with none left not on the ring. Taking a card out with the card bag full drops it at the body's feet, so a staff can always be emptied.

**During a possession** every one of these, and the corner panel, is about the driven body. The wizard's health bar over its head is Feel's, view only.

## The seams

What can change without the rest changing:

- **How a body picks up:** the pickup rule. Walking over an item, holding a button or another button changes only it.
- **Who picks up:** an actor id.
- **What an item is:** the kinds table and the content folders.
- **How it is shown:** the menus, on the shared widget, hearing events and sending requests.
- **The numbers:** capacities, the staffs a player starts with, the dev bag's 20 of each are data or the run's rules.
- **Areas talk through events.** The Items area knows nothing of the HUD, the AI or `net/`.

## I1: this plan

This document, the roadmap's exception and the decisions.

## I2: hands that can be empty

(`gameplay/actor/` Caster, `gameplay/player/`, `gameplay/flow/`, `hud/panels/`, `hud/menus/pause/`, `core/input/`)

- A body's staffs are no longer the first N buttons: each button holds a staff or none. The corner panel's rows and the player's look show an empty hand.
- Players start with two staffs, on RB and RT, in Play and the hub (the hub's dev staff on RT goes: the rack replaces it).
- The pause menu gets "Leave game" for the seat that opened it; the `leave` action goes, on the pad and the keyboard.
- Tests: a wizard with a gap between its staffs casts, shows and snapshots; the leave row lets the seat go at its tick on every machine.

**I2 done (2026-11-13).** A hand is empty by `Caster.empty_hands` (a bit a button, state), set by `PlayerController.seat_wizard` for a null staff (`Caster.replace_staffs`, a boss's phase, fills every hand it is given, a null staff falling back as before); an empty hand has no cards, slots or pool, casts nothing, refuses the builder (`PlayerController.EMPTY_HAND`), is never put on show while a staff is held, and is announced with an empty plan, so the corner panel shows no row for it and the radial builder's LB and RB pass it (its tab a dim dash). Play and the hub hold curl on RB and star on RT (`Flow.START_HANDS`); `HUB_DEV_BUTTON` is gone. A carried empty hand stays empty: the carry's `&""` is the mode's, which is empty there, so the replay's header is unchanged until I4. The pause menu's "Leave game" sends `seat_leave_requested`, which the input layer hears (`device_left`, the seat's LEAVE in its next frame); the `leave` action and its glyph are gone. The stress bench hands its wizards three staffs with `replace_staffs` (Play's two and moon on LB), as they held before; the bots build into RB, so RT keeps its bolt. Tests: `tests/gameplay/player/test_player_hands.gd`, and the Flow, hub, input, pause menu and builder tests.

## I3: stacks, kinds, the inventory and counted cards

(`core/base/`, `core/items/`, `gameplay/actor/`, `gameplay/player/`, `hud/builder/`, the bots that build staffs)

- `ItemKinds.RULES`, the stack, `Inventory` on every actor with its bags, staff numbers and hands; the caster handed its staffs by the inventory. `PlayerController.bag` goes.
- Cards are counted: putting one in a staff takes it from the bag, taking it out gives it back; the request is refused with none left. The sandbox's and the hub's bags hold 20 of each card; Play's as today, counted.
- The builder's requests name a staff by its number; its strip of staffs; counts on the ring.
- Tests: the kinds table against every content folder it names; counts through every builder request; a bag's capacity; a staff edited in the bag is not installed in the caster.

**I3 done (2026-11-14).** `ItemKinds.RULES` and `ItemStack` (core/items, now a simulation folder); `Inventory` (gameplay/actor), on the wizard, takes the staffs the body was made with at `setup`, numbered by their button (later staffs count on from 4), owns the card bag (`give_cards`) and the hands, and does the counting (`set_cards`, `set_card`: refused as `Inventory.Refusal` NO_STAFF, NO_SLOT, NO_CARD, BAG_FULL). `PlayerController.bag` and `set_bag` are gone: the builder's requests name a staff's number and go to the inventory, and the seat's events are `bag_changed(player, bag, ids, counts, capacity)` (every bag), `owned_staff_changed(player, staff, plan)` (every staff owned) and `hands_changed`; `staff_changed` stays the hands', for the corner panel. Flow's bags are counted (`bag_for_mode`, card id to copies: 20 of every card in the sandbox and the hub, Play's one each), and the start cards come with their staffs, beside the bag; a wizard made again with the staffs it carried gets the mode's bag less their cards, so nothing is counted twice (until I4 carries the bags). The builder works by number: a strip of staffs (the hands' button glyphs in framed tabs, then the bag's staffs by their heads, scrolling, a gold notch where more lie past an end), counts on the ring, a card with none left off it. The bots build only from the copies they hold. **Moved:** an enemy's inventory to I8 (the first step that reads one); a bag's capacity as a run's rule to I4 (a `SessionRules` field is the header's change); cards given back to a full bag are refused until I6 drops them (DECISIONS, 2026-11-14). Tests: `tests/core/test_item_kinds.gd`, `tests/gameplay/actor/test_inventory.gd`, `tests/gameplay/player/test_player_card_bag.gd`, and the builder's, Flow's and the player's.

## I4: the player loadout

(`core/sim/`, `gameplay/flow/`, `net/` only where it passes the header on)

- `PlayerLoadout` in place of `RunCarry`, in the replay's header: the bags, the staffs and the hands of each seat. Older recordings no longer decode.
- Each bag's capacity is one of the run's rules (`SessionRules`, moved from I3).
- Tests: the decoder against every cut, count and id out of range; a run from the hub starts with the same bags on a machine that only has the recording.

**I4 done (2026-11-14).** Named `PlayerLoadout` (the owner's suggestion, over "player record"), with `PartyLoadout` for every seat's (core/sim): plain data that knows no item, its bags (by name, each stack an id and its copies), its staffs (number, id, cards by slot) and its hands, written in three tagged sections, each its tag and length, and read as strictly as a frame (every cut, count, number and id; a section out of place or unknown rejects it; the writers refuse what the decoder would, sharing `MAX_*`). The replay's header holds a `PartyLoadout` in place of `RunCarry` (format 7; older recordings no longer decode); `Frames.set_party_source` and `next_run_party` in place of the carry's. `Inventory.loadout()` writes one and `take_loadout` holds exactly one (`hand_staffs`, `hand_cards` for its Caster); `PlayerController.loadout_of` and `seat_loadout`; Flow hands `start_run` a `PartyLoadout` (`_party_of`), a seat with none getting its mode's. `staff_cards`, `staff_ids`, `staffs_for_seat` and `_less_carried` are gone: a wizard made again holds its own bag, so nothing is counted twice by construction. A staff's mana is not carried (a run starts with every pool full). Each bag's capacity is a `SessionRules` field (`bag_staffs`, `bag_cards`, `bag_relics`, `bag_potions`; 0 no limit, `bag_capacity`), taken by the inventory at its start. Tests: `tests/core/test_player_loadout.gd` (the decoder, the writers' limits, random bytes, the party and the frames service), `test_replay.gd`, `test_session_rules.gd`, `tests/net/test_net_message.gd` (the fullest header crosses), the inventory's, the player's hands' and Flow's (the hub begun anew keeps every wizard's bags on a machine that only has the recording).

## I5: the shared radial widget

(`hud/widgets/`, `hud/builder/`)

- `RadialMenu` pulled out of `radial_builder.gd`. No behaviour changes; the builder's tests pass as they are.

**I5 done (2026-11-14).** `hud/widgets/radial_menu.gd`: a helper the host Control owns, which draws into the host's canvas from the host's `_draw` (so what lies over the ring, the builder's flying cards, stays the host's) and knows nothing of what its places hold. The ring's places from entry numbers and widths (`lay_out`, the first entry at the top), pointing with the stick or P1's mouse (`aim`, `pick_on_ring`, `pick_among` with the hysteresis, `point_at`, the pointer line), the layers (`enter`, `back`, `depth`; the builder has none, the inventory's bags will), the hint row (`make_hints`, `set_hints`: the glyphs, as the host's children, and the verbs, dimmed when a button does nothing) and the ring's, hub's and arcs' drawing. The builder lays its cards out on it (`_build_ring`) and keeps the cards, the slots, the hub's words and the strip; its ring styles pick and draw through `radial.menu()`. The builder's tests pass unchanged, and the builder alone draws the same pixels before and after (`tests/screenshots/shot_radial_alone.gd`: no room, no wizards, made-up cards, so nothing else can change a pixel; the other builder shots differ only in the wizards' blinks, seeded by their instance ids). Tests: `tests/hud/test_radial_menu.gd`.

## I6: items on the ground

(`gameplay/items/`, `core/events/`, `core/sim/`, `tools/`, `gameplay/feel/`, `hud/widgets/`, `content/items/`, the hub's scene)

- The Items area, its step in `Tick.STEPS`, the pickup rule, the commands (`item_take_requested`) and events.
- `ItemStandIn`, the look on the ground, the hint with its tooltip and its red shake.
- The hub's rack: one `StaffItem` with a crazy build.
- Tests: take with room and without; two seats and one item; a snapshot with items lying; `test_content_determinism` finds every item by itself.

## I7: the inventory

(`hud/`, `gameplay/items/`, `core/input/`)

- The inventory on Select and Tab (Tab leaves the builder's keys; E stays), on `RadialMenu`: the four bags with x/y, the staffs with the hands column and its arrows, putting a staff on a hand, dropping (`item_drop_requested`, `staff_hand_requested`, commands).
- Tests: every request refused when it should be; a drop lands apart from the item in reach; the arrows' table covers every number `StaffBase.ranges()` names.

## I8: the HUD follows the driven body

(`gameplay/player/`, `hud/`, `gameplay/feel/`)

- An enemy gets its inventory (moved from I3): its staff bag the staffs it holds, a boss's phases swapping them through it.
- The panel's events, the builder's and the inventory's requests are the driven body's, the first one hit when several are possessed. What is taken during a possession stays with that body.
- The wizard's health bar over its head while its seat is away.
- Tests: a possessed enemy's staff rebuilt, dropped and taken by the wizard afterwards; the panel back on the wizard when the possession ends.

## I9: the AI picks things up

(`gameplay/ai/`, `core/base/ai_profile.gd`)

- **Sensing:** a behaviour asks the Items area for the items near its body.
- **Wanting:** the profile says whether this enemy takes items, and which kinds.
- **A staff** goes to a free hand; the AI already plays whatever staffs it holds. With every hand full it takes the place of the weakest only when its next cast is stronger.
- **A card** is tried in each free slot of its staffs, the staff compiled, and kept where the card does something and the staff's next cast is strongest; a card that helps nowhere is left.
- Tests: an enemy beside a staff takes and casts it; an enemy beside a card that fits nowhere leaves it.

## What needs care

- **I3** changes the builder, the bots that build staffs and the commands' arguments.
- **I4** changes the replay's header (and so what a joining machine catches up on).
- **I8** changes the panel, the builder and possession together.

Each of these PRs runs `tools/online_pair.sh` and the determinism tests before it merges.

## Not in this plan

- What relics and potions do; their bags stay empty.
- Items as a run's rewards, and cards placed in rooms (M3). A dropped card is taken again by the same path.
- A limit on disarming enemies by possessing them.
- A quicker way to swap a staff on the ground for one held, should playtests ask for it: it would be the pickup rule's.

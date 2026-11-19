extends Node
## The Rewards area (autoload `Rewards`; connected biomes CB10 and CB11, docs/milestones/connected-
## biomes.md, decisions 16 to 20 and 26): each player's rewards, the coins on the floor, the shops'
## shelves and the fountains' pools. State like any area's, the same on every machine,
## saved and restored with everything else.
##
## - **A roll per player** (DESIGN rule 3): as a room whose kind rewards a clear is cleared
##   (`room_rewards_due`, Flow's, with the kind's table: a fight's `clear`, the boss's `boss`, a
##   reward room's `reward`, ...; rolled at the area's next step), however its foes left it (the
##   owner, 2026-11-19: a possessed foe killed elsewhere too), every seat with a wizard gets an offer
##   of its own (`RewardOffer`), its choices rolled from that table (content/rewards, `RewardRoll`),
##   as many as that player's `reward_choices` (`RunStats`: "pick 1 of 2", decision 17), said by
##   `reward_rolled`. A seat whose wizard was in the room (`here`) has its menu opened by the HUD;
##   one who was not there finds it waiting, an unspent icon on its corner panel (rule 4). Nobody
##   waits: each player picks when they like, oldest first, and an offer stays until it is picked
##   (`rewards_waiting_changed`), all run long.
## - **A pick** (`reward_pick_requested`, a command at the tick's start): the offer it names, if it
##   is the seat's, puts the choice into the seat's own wizard's inventory and goes
##   (`reward_taken`). With no room in its bag it stays unspent.
## - **A reward is an item** (the owner, 2026-11-19: "Every reward is something that can be placed
##   in a player's inventory"): a choice is an item kind, its id and a count (`RewardEntry`, a row
##   of `ItemKinds.RULES`): a card's copies, potions (a heal, more most health: drunk from the
##   inventory when the player likes, gameplay/player), coins. Its look is the item's own
##   (`ItemLooks`). A card upgrade waits for card levels.
## - **A shop** (CB11, decision 19): as a shop room opens (`special_room_opened`, its shelf table and
##   its spots), its shelf is rolled once (purpose SHOP_PURPOSE, keyed by its room): one item a spot,
##   each a different line's, at its line's `price`. The item nearest a standing wizard's own feet,
##   within SHELF_REACH, is in their reach (`shelf_near_changed`), and A buys it (the owner,
##   2026-11-19: `shelf_buy_requested`, a command at the tick's start, so the first seat to ask
##   takes it; nobody waits): the standing body the seat drives (its wizard, or a foe it possesses:
##   the buyer, the owner's of 2026-11-19), with the price (times that player's `price_scale`) in
##   its own coins bag and room for it, takes it into its inventory, the coins come out of its
##   stack, and it is gone from the shelf for everyone; else `shelf_refused`. Walking
##   over an item buys nothing. The shelf keeps what is left all run (`shelf_changed`).
## - **A fountain** (CB11, decision 20): as a fountain room opens, its pool fills with POOL_HEALTH
##   times the highest `fountain_pool` of the players then, shared: every hurt standing wizard whose
##   own feet are in it draws DRAW_RATE health a second from it until they are whole or it runs dry
##   (`fountain_changed`). The pool counts what was asked of Combat (`health_gift_requested`), which
##   heals it as asked.
## - **Run stats** (`RunStats`): the run's own changes come with `run_stats_ruled` (the Run area's,
##   as a run of rooms begins); a player's are those, then their relics' (the relics bag of its
##   wizard, `RelicBase`). Read by name: `stat_of`. Each seat's are told to the view
##   (`run_stats_told`) as they may change and after a restore (a relic taken will tell them
##   when relics come, M3).
## - **Coins** (decision 18: shared income, own coins; the owner, 2026-11-19: "Coins are stacked
##   inventory items"): a player's coins are one stack in its wizard's coins bag (`CoinBase`,
##   content/coins). A foe carries its coins in its own coins bag (its data's, `Actor._carry_coins`);
##   as it dies (`enemy_died`, possessed or not), by its `EnemyBase.coin_drop_chance` (DROP_PURPOSE),
##   what it still carries drops where it fell (an add another body called, `Actor.is_add`, drops
##   none; a boss's go to every player at once, decision 25), each one coin anyone may take: the
##   first wizard (seat order) whose feet come within `COIN_REACH` takes it, and every player's coin
##   stack gains one. As a seat's wizard first comes in a run its stack gains its player's
##   `start_coins` (nothing comes back from a run, and the hub has no coins to take along); a seat
##   that left and comes back gets the coins its wizard left with (`_kept`; the owner, 2026-11-19).
##   Spending is one's own (a shop's buy, `spend`).
##   The coins, shelves and pools are the world's: a new world (`room_entered` FIRST_ROOM) and a
##   run's start clear them; a cleared room's coins stay where they lie.
## - **Said:** `coin_changed` as a coin is laid and goes (a player's coin stack is said by its
##   Inventory, `bag_changed`, as any bag), `shelf_changed` and `fountain_changed` as a shelf and a pool change. After a snapshot is
##   restored it says everything again (`rebuild_derived`).
##
## It knows nothing of the HUD, Flow or `net/`, and calls no other area: it hears events, reads the
## actor table and the bodies' public kit (gameplay/actor: an Inventory, its Health), and asks the
## projectile manager's wall grid where a coin may lie. A gift of health it asks of Combat.

const EventsScript := preload("res://core/events/events.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

const SEATS: int = 4
## The registry folders of the reward tables (content/rewards) and of the relics (content/relics).
const TABLES: StringName = &"rewards"
const RELICS: StringName = &"relics"
## The table a fight's clear rolls from (each kind names its own, `RoomKind.rewards`; CB11).
const CLEAR_TABLE: StringName = &"clear"
## A shop's shelf (CB11): the chance's purposes it is rolled under (keyed by its room), and how near a
## wizard's feet must come to an item to buy it, in pixels.
const SHOP_PURPOSE: StringName = &"shop"
const SHOP_CARD_PURPOSE: StringName = &"shop_card"
const SHELF_REACH: float = 12.0
## A fountain (CB11): the healing its pool holds (times the highest `fountain_pool`), and how fast a
## wizard in it draws on it, health a second.
const POOL_HEALTH: float = 120.0
const DRAW_RATE: float = 40.0
## The relics bag and the coins bag of an Inventory (`ItemKinds.BAGS`).
const RELIC_BAG: StringName = &"relics"
const COIN_BAG: StringName = &"coins"
## How near a wizard's feet must come to a coin to take it, in pixels.
const COIN_REACH: float = 10.0
## Where an enemy's coins land round where it fell, in order (more than these: on its spot again).
const COIN_SPREAD: Array[Vector2] = [
	Vector2(0.0, 0.0), Vector2(6.0, 0.0), Vector2(-6.0, 0.0), Vector2(0.0, 6.0), Vector2(0.0, -6.0),
	Vector2(5.0, 5.0), Vector2(-5.0, 5.0), Vector2(5.0, -5.0), Vector2(-5.0, -5.0),
	Vector2(12.0, 0.0), Vector2(-12.0, 0.0), Vector2(0.0, 12.0), Vector2(0.0, -12.0),
]
## The room a coin takes: it lies clear of walls this far round.
const COIN_RADIUS: float = 2.0
## The run's chance's purpose for whether a dying foe's coins drop (`EnemyBase.coin_drop_chance`),
## keyed by its actor key, counted by `_drops`.
const DROP_PURPOSE: StringName = &"coin_drop"

## Not state: services, set up again, and what this machine's looks were told (core/sim/README.md).
const DERIVED: Array[StringName] = [&"events", &"actors", &"projectiles", &"spells", &"registry", &"sim", &"_said_coins", &"_said_items"]

## The services. Only tests set these, before adding the node; otherwise the autoloads.
var events: EventsScript = null
var actors: ActorsScript = null
var projectiles: ProjectilesScript = null
var spells: SpellsScript = null
var registry: RegistryScript = null
## The run's chance (core/sim/README.md, "Chance"): only tests set it; otherwise the Tick's,
## found at each roll (a run's start may deal another).
var sim: Sim = null

## The run's own changes of the run stats (`run_stats_ruled`), in order.
var _run_changes: Array[StatChange] = []
## The offers not yet picked, in the order rolled (numbers rising), every seat's.
var _offers: Array[RewardOffer] = []
## The number the next offer gets.
var _next_offer: int = 0
## The rooms due a roll since the last step (`room_rewards_due`), and the table each rolls from.
var _due_rooms: PackedInt32Array = PackedInt32Array()
var _due_tables: Array[StringName] = []
## The shops' shelves: each item's number, room, place, what it is (an item: kind, id, count) and
## price (before a buyer's `price_scale`), by the same index, in the order stocked.
var _item_numbers: PackedInt32Array = PackedInt32Array()
var _item_rooms: PackedInt32Array = PackedInt32Array()
var _item_at: PackedVector2Array = PackedVector2Array()
var _item_kinds: Array[StringName] = []
var _item_ids: Array[StringName] = []
var _item_counts: PackedInt32Array = PackedInt32Array()
var _item_prices: PackedInt32Array = PackedInt32Array()
## The number the next shelf item gets.
var _next_item: int = 0
## The fountains: each one's room, pool, healing left and most, by the same index.
var _pool_rooms: PackedInt32Array = PackedInt32Array()
var _pool_areas: Array[Rect2] = []
var _pool_left: PackedFloat32Array = PackedFloat32Array()
var _pool_most: PackedFloat32Array = PackedFloat32Array()
## By seat: the rolls it has had this run (its counter of the run's chance, `RewardRoll`).
var _rolls: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
## By seat: the shelf item (its number) in reach of its standing wizard, last said
## (`shelf_near_changed`), -1 for none.
var _shelf_near: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1])
## The seats whose starting coins came this run, a bit each.
var _funded: int = 0
## The drop rolls made this run (`DROP_PURPOSE`'s counter).
var _drops: int = 0
## By seat: the coins its wizard held when last seen (kept for a rejoin: the owner, 2026-11-19).
var _kept: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
## The seats that left (`player_left`) and are owed their kept coins as their wizard comes again,
## a bit each.
var _away: int = 0
## The coins on the floor: each one's number and where it lies, by the same index, in the order laid.
var _coin_numbers: PackedInt32Array = PackedInt32Array()
var _coin_at: PackedVector2Array = PackedVector2Array()
## The number the next coin laid gets.
var _next_coin: int = 0
## The coin numbers this machine's looks were last told lie there (`coin_changed`): a restore tells
## them gone for those it no longer holds. Not state: what was said here.
var _said_coins: Dictionary = {}
## The shelf items this machine's looks were last told lie there (`shelf_changed`), as `_said_coins`.
var _said_items: Dictionary = {}


func _ready() -> void:
	# The tick steps it (core/sim/tick.gd, core/sim/sim_area.gd).
	SimArea.join(self, &"Rewards").steps(&"Rewards", step).renewed_by(begin_run)
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if actors == null:
		actors = get_node_or_null("/root/Actors") as ActorsScript
	if projectiles == null:
		projectiles = get_node_or_null("/root/Projectiles") as ProjectilesScript
	if spells == null:
		spells = get_node_or_null("/root/Spells") as SpellsScript
	if registry == null:
		registry = get_node_or_null("/root/Registry") as RegistryScript
	if events == null:
		push_warning("Rewards: the Events autoload is missing, so nobody is rewarded.")
		return
	events.room_rewards_due.connect(_on_room_rewards_due)
	events.special_room_opened.connect(_on_special_room_opened)
	events.room_entered.connect(_on_room_entered)
	events.enemy_died.connect(_on_enemy_died)
	events.run_stats_ruled.connect(_on_run_stats_ruled)
	events.player_left.connect(_on_player_left)
	# A command, heard at the tick's start (core/events, online-ready N2).
	events.listen(&"reward_pick_requested", _on_reward_pick_requested)
	events.listen(&"shelf_buy_requested", _on_shelf_buy_requested)


## A run's start: every offer, coin, shelf and pool goes (each said), and the area is a fresh one's.
func begin_run() -> void:
	_clear_coins()
	_clear_rooms()
	SimFresh.renew(self)
	for seat in SEATS:
		_say_waiting(seat)
		_say_shelf_near(seat)
		_say_stats(seat)


## The tick's step: the clears since the last step are rolled for; a seat whose wizard came gets
## its starting coins into its coin stack (once a run), or, coming back after it left, the coins it
## left with; each coin a wizard's feet reach is taken (seats in order, the first takes it); each
## seat's shelf item in reach is found; each fountain is drawn on; each wizard's coins are kept.
func step(delta: float) -> void:
	if actors == null:
		return
	if not _due_rooms.is_empty():
		var rooms: PackedInt32Array = _due_rooms.duplicate()
		var tables: Array[StringName] = _due_tables.duplicate()
		_due_rooms.clear()
		_due_tables.clear()
		for at in rooms.size():
			_roll_clear(rooms[at], tables[at])
	for seat in SEATS:
		if actors.home_of_seat(seat) == ActorsScript.NONE:
			continue
		if _funded & (1 << seat) == 0:
			_funded |= 1 << seat
			_away &= ~(1 << seat)
			_add_coins(seat, int(stat_of(seat, &"start_coins")))
			_say_stats(seat)
			_say_shelf_near(seat)
		elif _away & (1 << seat) != 0:
			# Back after leaving mid-run (the owner, 2026-11-19): the coins it left with, not a second
			# `start_coins`. Its cards and potions went with its old body.
			_away &= ~(1 << seat)
			_add_coins(seat, _kept[seat])
	var at: int = 0
	while at < _coin_numbers.size():
		if _taker_of(_coin_at[at]) != ActorsScript.NONE:
			var number: int = _coin_numbers[at]
			var where: Vector2 = _coin_at[at]
			_coin_numbers.remove_at(at)
			_coin_at.remove_at(at)
			_say_coin(number, where, false)
			for seat in SEATS:
				if actors.home_of_seat(seat) != ActorsScript.NONE:
					_add_coins(seat, 1)
		else:
			at += 1
	_look_at_shelves()
	_draw_on_pools(delta)
	for seat in SEATS:
		_keep_coins(seat)


# --- Asked ------------------------------------------------------------------------------

## Seat `seat`'s run stat `stat` (`RunStats.value_of`): its base, the run's changes, then the
## relics its wizard holds. For this area's own rules and tests: another area that reads a run stat
## (CB9's map, CB11's fountain) hears `run_stats_ruled` itself and works it out with `RunStats`, as
## areas never call each other.
func stat_of(seat: int, stat: StringName) -> float:
	return RunStats.value_of(stat, _run_changes, _relics_of(seat))


## The coins seat `seat`'s own wizard holds: the coin stack in its coins bag (0 with no wizard).
## A foe the seat possesses holds its own (a shop's buy spends the driven body's).
func coins_of(seat: int) -> int:
	return _coins_in(_wizard_of(seat)) if seat >= 0 and seat < SEATS else 0


## Spend `amount` of seat `seat`'s own coins (a shop's buy: the shop is this area's, CB11): false,
## and nothing changes, when it holds fewer. Not for other areas (they never call this one).
func spend(seat: int, amount: int) -> bool:
	if seat < 0 or seat >= SEATS or amount < 0 or coins_of(seat) < amount:
		return false
	_add_coins(seat, -amount)
	return true


## The shelf items lying in shops: each one's view (`number`, `room`, `at`, `price` as the run's own
## `price_scale` makes it, and `choice`, a choice's view), in the order stocked.
func shelf() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for at in _item_numbers.size():
		out.append({"number": _item_numbers[at], "room": _item_rooms[at], "at": _item_at[at], "price": _shown_price(at), "choice": _item_view(at)})
	return out


## What seat `seat` pays for shelf item `item` (by number): its price times the player's
## `price_scale`, 1 at least; -1 for no such item.
func price_for(seat: int, item: int) -> int:
	var at: int = _item_numbers.find(item)
	return _price_of(at, stat_of(seat, &"price_scale")) if at >= 0 else -1


## The healing left in room `room`'s fountain (-1: no fountain there).
func pool_left(room: int) -> float:
	var at: int = _pool_rooms.find(room)
	return _pool_left[at] if at >= 0 else -1.0


## Seat `seat`'s offers not yet picked, oldest first (copies of their views).
func waiting_of(seat: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for offer: RewardOffer in _offers:
		if offer.seat == seat:
			out.append(_offer_view(offer))
	return out


## The coins on the floor: where each lies, in the order laid.
func coins_lying() -> PackedVector2Array:
	return _coin_at.duplicate()


## Lay one coin at `at` (over a hole: at the nearest ground). Returns its number.
func lay_coin(at: Vector2) -> int:
	if projectiles != null and projectiles.grid().touches_hole(at, COIN_RADIUS):
		at = projectiles.grid().nearest_ground(at, COIN_RADIUS)
	var number: int = _next_coin
	_next_coin += 1
	_coin_numbers.append(number)
	_coin_at.append(at)
	_say_coin(number, at, true)
	return number


## Say everything again (a snapshot restored: this machine's looks and HUD showed what was here
## before): gone for each coin it told of that no longer lies there, then every coin, shelf item and
## pool, and every seat's waiting offers (a coin stack is its Inventory's to say again).
func rebuild_derived() -> void:
	if events == null:
		return
	for number: int in _said_coins.keys():
		if not _coin_numbers.has(number):
			_said_coins.erase(number)
			events.coin_changed.emit(number, Vector2.ZERO, false)
	for at in _coin_numbers.size():
		_say_coin(_coin_numbers[at], _coin_at[at], true)
	for number: int in _said_items.keys():
		if not _item_numbers.has(number):
			_said_items.erase(number)
			events.shelf_changed.emit(number, Vector2.ZERO, {}, 0, false)
	for at in _item_numbers.size():
		_say_item(at, true)
	events.fountain_changed.emit(-1, Rect2(), 0.0, 0.0)
	for at in _pool_rooms.size():
		_say_pool(at)
	for seat in SEATS:
		_say_waiting(seat)
		_say_shelf_near(seat)
		_say_stats(seat)


# --- Heard ------------------------------------------------------------------------------

## The room `room` was cleared and its kind rewards it from `table`: rolled for at the next step.
func _on_room_rewards_due(room: int, table: StringName) -> void:
	if not _due_rooms.has(room):
		_due_rooms.append(room)
		_due_tables.append(table)


## Room `room`'s clear: every seat with a wizard rolls its own offer from the table `table_id`.
func _roll_clear(room: int, table_id: StringName) -> void:
	if actors == null:
		return
	var table: RewardTable = registry.get_resource(TABLES, table_id) as RewardTable if registry != null else null
	if table == null:
		push_warning("Rewards: no reward table '%s' (content/rewards), so a clear rewards nobody." % table_id)
		return
	var cards: Array[StringName] = []
	var complexities := PackedInt32Array()
	_cards_of(cards, complexities)
	for seat in SEATS:
		var body: Actor = _wizard_of(seat)
		if body == null:
			continue
		var offer := RewardOffer.new()
		offer.number = _next_offer
		offer.seat = seat
		offer.room = room
		offer.here = body.room == room or body.room == RoomGrid.NO_PLACE
		RewardRoll.fill(offer, table, int(stat_of(seat, &"reward_choices")), _sim(), seat, _rolls[seat], cards, complexities)
		_rolls[seat] += 1
		if offer.size() == 0:
			continue
		_next_offer += 1
		_offers.append(offer)
		if events != null:
			var view: Dictionary = _offer_view(offer)
			var choices: Array[Dictionary] = []
			choices.assign(view["choices"])
			events.reward_rolled.emit(seat, offer.number, choices, offer.here)
		_say_waiting(seat)


## Seat `player` picked choice `choice` of its offer `offer` (a command): into its wizard's
## inventory and gone, or kept (not its offer, no such choice; `reward_refused` for no wizard or no
## room in the bag).
func _on_reward_pick_requested(player: int, offer: int, choice: int) -> void:
	var at: int = -1
	for i in _offers.size():
		if _offers[i].number == offer and _offers[i].seat == player:
			at = i
			break
	if at < 0:
		return
	var row: RewardOffer = _offers[at]
	if choice < 0 or choice >= row.size():
		return
	if not _give(player, row.kinds[choice], row.ids[choice], row.counts[choice]):
		if events != null:
			events.reward_refused.emit(player, offer)
		return
	_offers.remove_at(at)
	_keep_coins(player)
	if events != null:
		events.reward_taken.emit(player, offer, choice, _choice_view(row, choice))
	_say_waiting(player)


## A new world (FIRST_ROOM entered): the coins, shelves and pools of the one before are gone with it.
func _on_room_entered(_room_id: StringName, room: int) -> void:
	if room == EventsScript.FIRST_ROOM:
		_clear_coins()
		_clear_rooms()


## Seat `player` asked to buy shelf item `item` (a command): sold if it still lies on its shelf, in
## reach of the standing body the seat drives (its wizard, or a foe it possesses: the actor doing the
## buying, the owner's of 2026-11-19), which pays from its own coins and has room for it; else
## `shelf_refused` (an item gone or out of reach says nothing).
func _on_shelf_buy_requested(player: int, item: int) -> void:
	if player < 0 or player >= SEATS:
		return
	var at: int = _item_numbers.find(item)
	var body: Actor = _driven_of(player)
	if at < 0 or body == null or body.is_down() or body.position.distance_squared_to(_item_at[at]) > SHELF_REACH * SHELF_REACH:
		return
	var price: int = _price_of(at, stat_of(player, &"price_scale"))
	if _coins_in(body) < price or not _give_to(body, _item_kinds[at], _item_ids[at], _item_counts[at]):
		if events != null:
			events.shelf_refused.emit(player, item)
		return
	body.inventory.take(COIN_BAG, CoinBase.ID, price)
	_keep_coins(player)
	_say_item(at, false)
	_item_numbers.remove_at(at)
	_item_rooms.remove_at(at)
	_item_at.remove_at(at)
	_item_kinds.remove_at(at)
	_item_ids.remove_at(at)
	_item_counts.remove_at(at)
	_item_prices.remove_at(at)
	_look_at_shelves()


## A special room opened (Flow's, CB11): a shop's shelf is stocked from `table` at `spots`, a
## fountain's pool filled at `area`. Once a room.
func _on_special_room_opened(room: int, fill: StringName, table: StringName, area: Rect2, spots: PackedVector2Array) -> void:
	if fill == RoomKind.FILL_SHOP and not _item_rooms.has(room):
		_stock_shelf(room, table, spots)
	elif fill == RoomKind.FILL_FOUNTAIN and not _pool_rooms.has(room):
		var most: float = 0.0
		for seat in SEATS:
			if _wizard_of(seat) != null:
				most = maxf(most, stat_of(seat, &"fountain_pool"))
		_pool_rooms.append(room)
		_pool_areas.append(area)
		_pool_left.append(POOL_HEALTH * most)
		_pool_most.append(POOL_HEALTH * most)
		_say_pool(_pool_rooms.size() - 1)


## A foe died at `position` (possessed or not): by its `EnemyBase.coin_drop_chance` (the run's
## chance, `DROP_PURPOSE`, keyed by its actor key and counted), the coins in its own coins bag land
## there, spread round it (the owner, 2026-11-19: what it carries, less what a seat possessing it
## spent).
func _on_enemy_died(_killer: int, enemy: Node, position: Vector2, _shot: int) -> void:
	var body := enemy as Actor
	if body == null:
		return
	if body.data == null or body.is_add:
		# An add (a boss's waves, boss plan OB13) drops no coins: waves without end would fill coin stacks.
		return
	var carried: int = _coins_in(body)
	if carried <= 0:
		return
	var key: int = actors.key_of(body.id) if actors != null and body.id != ActorsScript.NONE else 0
	var roll: float = _sim().chance(DROP_PURPOSE, key, _drops)
	_drops += 1
	if roll >= body.data.coin_drop_chance:
		return
	if body.data.boss:
		# A boss's coins go to every player at once (decision 25): its room's portal home opens as it
		# is cleared, and nobody should lose them to it.
		for seat in SEATS:
			if actors != null and actors.home_of_seat(seat) != ActorsScript.NONE:
				_add_coins(seat, carried)
		return
	for i in carried:
		var spot: Vector2 = position + COIN_SPREAD[i % COIN_SPREAD.size()]
		if projectiles != null and (projectiles.grid().circle_blocked(spot, COIN_RADIUS) or not projectiles.grid().line_clear(position, spot)):
			spot = position
		lay_coin(spot)


## Seat `player` left (Coop's): its wizard went with what it held, and its coins (kept, `_kept`)
## come back as it joins again in this run.
func _on_player_left(player: int) -> void:
	if player >= 0 and player < SEATS and _funded & (1 << player) != 0:
		_away |= 1 << player


## The run's own changes of the run stats (the Run area's, as a run of rooms begins).
func _on_run_stats_ruled(changes: Array[StatChange]) -> void:
	_run_changes = changes.duplicate()
	for seat in SEATS:
		_say_stats(seat)
		# A price in reach follows the player's `price_scale`.
		_say_shelf_near(seat)


# --- Inside -----------------------------------------------------------------------------

## Put `count` of the item `kind` `id` into seat `seat`'s wizard's inventory (a staff with no
## cards, as its content is). False, and nothing changes, when it has no wizard, the item no content
## of its kind, or its bag no room.
func _give(seat: int, kind: StringName, id: StringName, count: int) -> bool:
	return _give_to(_wizard_of(seat), kind, id, count)


## Put `count` of the item `kind` `id` into `body`'s inventory, as `_give` says.
func _give_to(body: Actor, kind: StringName, id: StringName, count: int) -> bool:
	if body == null or body.inventory == null:
		return false
	var stack: ItemStack = _stack_of(kind, id, count)
	if stack == null or not body.inventory.has_room(stack):
		return false
	return body.inventory.add(stack)


## `count` of the item `kind` `id` as a stack: a staff its content empty (copies, one a stack), any
## other kind just its kind, id and count; null for a staff the registry has none of.
func _stack_of(kind: StringName, id: StringName, count: int) -> ItemStack:
	if kind == ItemKinds.STAFF:
		var base := ItemLooks.content_of(kind, id, registry) as StaffBase
		if base == null:
			return null
		var staff: ItemStack = ItemStack.of_staff(base)
		staff.count = count
		return staff
	return ItemStack.of(kind, id, count)


## The wizard of seat `seat` (its own body, also while it drives another), or null.
func _wizard_of(seat: int) -> Actor:
	if actors == null:
		return null
	var id: int = actors.home_of_seat(seat)
	return actors.node_of(id) as Actor if id != ActorsScript.NONE else null


## The body seat `seat` drives now (its wizard, or a foe it possesses), or null.
func _driven_of(seat: int) -> Actor:
	if actors == null:
		return null
	var id: int = actors.actor_of_seat(seat)
	return actors.node_of(id) as Actor if id != ActorsScript.NONE else null


## The coins in `body`'s coins bag (0 for none, or no inventory).
static func _coins_in(body: Actor) -> int:
	return body.inventory.count_of(COIN_BAG, CoinBase.ID) if body != null and body.inventory != null else 0


## The relics seat `seat`'s wizard holds, one entry a copy, in the bag's order (each a `RelicBase`
## the registry has; an id it has none of is left out).
func _relics_of(seat: int) -> Array[Resource]:
	var out: Array[Resource] = []
	var body: Actor = _wizard_of(seat)
	if body == null or body.inventory == null or registry == null:
		return out
	for stack: ItemStack in body.inventory.stacks_in(RELIC_BAG):
		var relic: RelicBase = registry.get_resource(RELICS, stack.id) as RelicBase
		if relic != null:
			for copy in maxi(stack.count, 1):
				out.append(relic)
	return out


## The card ids a reward may give (every card the registry has, in id order), with each one's
## complexity by the same index.
func _cards_of(cards: Array[StringName], complexities: PackedInt32Array) -> void:
	if registry == null:
		return
	for found: Resource in registry.get_all(ItemKinds.content_of(ItemKinds.CARD)[0]):
		if ItemKinds.is_content(ItemKinds.CARD, found):
			cards.append(StringName(str(found.get(&"id"))))
			complexities.append(int(found.get(&"complexity")))


## The first seat (in order) whose driven wizard, standing, reaches `at` with its feet; NONE for none.
func _taker_of(at: Vector2) -> int:
	for seat in SEATS:
		var id: int = actors.actor_of_seat(seat)
		if id == ActorsScript.NONE:
			continue
		var body := actors.node_of(id) as Actor
		if body != null and not body.is_down() and body.global_position.distance_squared_to(at) <= COIN_REACH * COIN_REACH:
			return seat
	return ActorsScript.NONE


## Seat `seat`'s coin stack changed by `amount` (a fall takes no more than it holds): its wizard's
## coins bag, said by its Inventory (`bag_changed`). Nothing for a seat with no wizard.
func _add_coins(seat: int, amount: int) -> void:
	var body: Actor = _wizard_of(seat)
	if amount == 0 or body == null or body.inventory == null:
		return
	if amount > 0:
		body.inventory.add(ItemStack.of(ItemKinds.COIN, CoinBase.ID, amount))
	else:
		body.inventory.take(COIN_BAG, CoinBase.ID, mini(-amount, coins_of(seat)))
	_keep_coins(seat)


## Seat `seat`'s wizard's coins, kept for a rejoin (nothing for a seat with no wizard: it keeps what
## its last one held).
func _keep_coins(seat: int) -> void:
	var body: Actor = _wizard_of(seat)
	if body != null:
		_kept[seat] = _coins_in(body)


func _clear_coins() -> void:
	var numbers: PackedInt32Array = _coin_numbers.duplicate()
	var at: PackedVector2Array = _coin_at.duplicate()
	_coin_numbers.clear()
	_coin_at.clear()
	for i in numbers.size():
		_say_coin(numbers[i], at[i], false)


## Room `room`'s shelf stocked from the table `table_id`: one item a spot of `spots`, rolled once.
func _stock_shelf(room: int, table_id: StringName, spots: PackedVector2Array) -> void:
	var table: RewardTable = registry.get_resource(TABLES, table_id) as RewardTable if registry != null else null
	if table == null:
		push_warning("Rewards: no shelf table '%s' (content/rewards), so the shop stands empty." % table_id)
		return
	var cards: Array[StringName] = []
	var complexities := PackedInt32Array()
	_cards_of(cards, complexities)
	var stock := RewardOffer.new()
	var lines: Array[RewardEntry] = []
	RewardRoll.fill(stock, table, spots.size(), _sim(), room, 0, cards, complexities, SHOP_PURPOSE, SHOP_CARD_PURPOSE, lines)
	for at in stock.size():
		_item_numbers.append(_next_item)
		_next_item += 1
		_item_rooms.append(room)
		_item_at.append(spots[at])
		_item_kinds.append(stock.kinds[at])
		_item_ids.append(stock.ids[at])
		_item_counts.append(stock.counts[at])
		_item_prices.append(lines[at].price)
		_say_item(_item_numbers.size() - 1, true)


## Each seat's shelf item in reach: the one nearest the own feet of the standing body it drives
## within SHELF_REACH (the first stocked of two as near), said as it changes.
func _look_at_shelves() -> void:
	for seat in SEATS:
		var near: int = -1
		var body: Actor = _driven_of(seat)
		if body != null and not body.is_down():
			var best: float = SHELF_REACH * SHELF_REACH
			for at in _item_numbers.size():
				var gap: float = body.position.distance_squared_to(_item_at[at])
				if gap <= best and (near < 0 or gap < best):
					best = gap
					near = _item_numbers[at]
		if near != _shelf_near[seat]:
			_shelf_near[seat] = near
			_say_shelf_near(seat)


## Each fountain `delta` seconds on: every hurt standing wizard whose own feet are in its pool draws
## on it (seats in order), until whole or the pool is dry.
func _draw_on_pools(delta: float) -> void:
	for at in _pool_rooms.size():
		if _pool_left[at] <= 0.0:
			continue
		var drawn: bool = false
		for seat in SEATS:
			var body: Actor = _wizard_of(seat)
			if body == null or body.is_down() or body.health == null or not _pool_areas[at].has_point(body.position):
				continue
			var missing: float = body.health.max_health - body.health.health
			var amount: float = minf(minf(DRAW_RATE * delta, missing), _pool_left[at])
			if amount <= 0.0:
				continue
			_pool_left[at] -= amount
			drawn = true
			events.health_gift_requested.emit(actors.home_of_seat(seat), amount, 0.0)
			if _pool_left[at] <= 0.0:
				_pool_left[at] = 0.0
				break
		if drawn:
			_say_pool(at)


## Shelf item `at`'s price for a player whose `price_scale` is `scale`: 1 at least.
func _price_of(at: int, scale: float) -> int:
	return maxi(roundi(float(_item_prices[at]) * scale), 1)


## Shelf item `at`'s price as shown: the run's own `price_scale` (a buyer's relics may change theirs).
func _shown_price(at: int) -> int:
	return _price_of(at, RunStats.value_of(&"price_scale", _run_changes))


## Every shelf and pool gone (each said gone).
func _clear_rooms() -> void:
	for at in _item_numbers.size():
		_say_item(at, false)
	for seat in SEATS:
		if _shelf_near[seat] >= 0:
			_shelf_near[seat] = -1
			_say_shelf_near(seat)
	_item_numbers.clear()
	_item_rooms.clear()
	_item_at.clear()
	_item_kinds.clear()
	_item_ids.clear()
	_item_counts.clear()
	_item_prices.clear()
	if not _pool_rooms.is_empty() and events != null:
		events.fountain_changed.emit(-1, Rect2(), 0.0, 0.0)
	_pool_rooms.clear()
	_pool_areas.clear()
	_pool_left.clear()
	_pool_most.clear()


func _sim() -> Sim:
	return sim if sim != null else Sim.found(self)


## The plain view of offer `offer`: its number, whether its player was there and its choices' views.
func _offer_view(offer: RewardOffer) -> Dictionary:
	var choices: Array[Dictionary] = []
	for choice in offer.size():
		choices.append(_choice_view(offer, choice))
	return {"offer": offer.number, "here": offer.here, "choices": choices}


## The plain view of choice `choice` of `offer`: its kind, id, count, name and icon.
func _choice_view(offer: RewardOffer, choice: int) -> Dictionary:
	return _view_of(offer.kinds[choice], offer.ids[choice], offer.counts[choice])


## The plain view of shelf item `at` (as a choice's).
func _item_view(at: int) -> Dictionary:
	return _view_of(_item_kinds[at], _item_ids[at], _item_counts[at])


## The plain view of a choice of `kind` `id`, `count` of it: its kind, id and count, and the item's
## own name, icon and description (`ItemLooks`; the reward menu's card shows only these), its name
## with the count when there are more than one.
func _view_of(kind: StringName, id: StringName, count: int) -> Dictionary:
	var look: Dictionary = ItemLooks.of(kind, id, registry, spells)
	var view: Dictionary = {"kind": kind, "id": id, "count": count, "name": look["name"], "icon": look["icon"], "description": look["description"]}
	if count > 1:
		view["name"] = "%s x%d" % [view["name"], count]
	return view


func _say_waiting(seat: int) -> void:
	if events != null:
		events.rewards_waiting_changed.emit(seat, waiting_of(seat))


func _say_item(at: int, lying: bool) -> void:
	var number: int = _item_numbers[at]
	if lying:
		_said_items[number] = true
	else:
		_said_items.erase(number)
	if events != null:
		events.shelf_changed.emit(number, _item_at[at], _item_view(at) if lying else {}, _shown_price(at), lying)


func _say_stats(seat: int) -> void:
	if events != null:
		events.run_stats_told.emit(seat, RunStats.all_of(_run_changes, _relics_of(seat)))


func _say_shelf_near(seat: int) -> void:
	if events == null:
		return
	var at: int = _item_numbers.find(_shelf_near[seat])
	if at < 0:
		events.shelf_near_changed.emit(seat, -1, Vector2.ZERO, {})
		return
	var view: Dictionary = _item_view(at)
	view["price"] = _price_of(at, stat_of(seat, &"price_scale"))
	events.shelf_near_changed.emit(seat, _shelf_near[seat], _item_at[at], view)


func _say_pool(at: int) -> void:
	if events != null:
		events.fountain_changed.emit(_pool_rooms[at], _pool_areas[at], _pool_left[at], _pool_most[at])


func _say_coin(number: int, at: Vector2, lying: bool) -> void:
	if lying:
		_said_coins[number] = true
	else:
		_said_coins.erase(number)
	if events != null:
		events.coin_changed.emit(number, at, lying)

extends Node
## The Rewards area (autoload `Rewards`; connected biomes CB10, docs/milestones/connected-biomes.md,
## decisions 16 to 18 and 26): each player's rewards, their wallets and the coins on the floor.
## State like any area's, the same on every machine, saved and restored with everything else.
##
## - **A roll per player** (DESIGN rule 3): as a room whose fight was fought is cleared
##   (`room_cleared`, rolled at the area's next step, so the death that cleared it has been heard; a
##   room cleared with no foe dying in it, the start room, rolls nothing), every seat with a
##   wizard gets an offer of its own (`RewardOffer`), its choices rolled from the reward table
##   `CLEAR_TABLE` (content/rewards, `RewardRoll`), as many as that player's `reward_choices`
##   (`RunStats`: "pick 1 of 2", decision 17), said by `reward_rolled`. A seat whose wizard was in
##   the room (`here`) has its menu opened by the HUD; one who was not there finds it waiting, an
##   unspent icon on its corner panel (rule 4). Nobody waits: each player picks when they like,
##   oldest first, and an offer stays until it is picked (`rewards_waiting_changed`), all run long.
## - **A pick** (`reward_pick_requested`, a command at the tick's start): the offer it names, if it
##   is the seat's, gives the choice to the seat's own wizard (a card's copies into its card bag;
##   coins into its wallet) and goes (`reward_taken`). With no room in the bag it stays unspent.
## - **What a reward may be** before relics exist (`RewardEntry.KINDS`; the owner, 2026-11-19): a
##   card, coins, a heal (not while down: it stays unspent) or a little more most health, the last
##   two through Combat, which keeps an actor's health (`health_gift_requested`). A card upgrade
##   waits for card levels.
## - **Run stats** (`RunStats`): the run's own changes come with `run_stats_ruled` (the Run area's,
##   as a run of rooms begins); a player's are those, then their relics' (the relics bag of its
##   wizard, `RelicBase`). Read by name: `stat_of`.
## - **Coins** (decision 18: shared income, own wallet): a foe that dies (`enemy_died`) drops its
##   `EnemyBase.coins` where it fell (an add another body called, `Actor.is_add`, drops none), each one coin anyone may take: the first wizard (seat order)
##   whose feet come within `COIN_REACH` takes it, and every player's wallet gains one. Each wallet
##   starts a run with its player's `start_coins`, and spending is one's own (`spend`, for CB11's
##   shop). The coins on the floor are the world's: a new world (`room_entered` FIRST_ROOM) and a
##   run's start clear them; a cleared room's coins stay where they lie.
## - **Said:** `coin_changed` as a coin is laid and goes, `wallet_changed` as a wallet changes.
##   After a snapshot is restored it says everything again (`rebuild_derived`).
##
## It knows nothing of the HUD, Flow or `net/`, and calls no other area: it hears events, reads the
## actor table and the bodies' public kit (gameplay/actor: an Inventory), and asks the projectile
## manager's wall grid where a coin may lie. A gift of health it asks of Combat.

const EventsScript := preload("res://core/events/events.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

const SEATS: int = 4
## The registry folders of the reward tables (content/rewards) and of the relics (content/relics).
const TABLES: StringName = &"rewards"
const RELICS: StringName = &"relics"
## The table a room's clear rolls from (CB11 gives each kind of room its own).
const CLEAR_TABLE: StringName = &"clear"
## The card bag and the relics bag of an Inventory (`ItemKinds.BAGS`).
const CARD_BAG: StringName = &"cards"
const RELIC_BAG: StringName = &"relics"
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

## Not state: services, set up again, and what this machine's looks were told (core/sim/README.md).
const DERIVED: Array[StringName] = [&"events", &"actors", &"projectiles", &"spells", &"registry", &"sim", &"_said_coins"]

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
## The rooms cleared since the last step, to roll for at the next (`room_cleared`'s numbers).
var _cleared: PackedInt32Array = PackedInt32Array()
## The places a foe died in since their clear was rolled for (`Actor.room`; NO_PLACE in a world
## with none, a row run's room).
var _fought: PackedInt32Array = PackedInt32Array()
## By seat: the rolls it has had this run (its counter of the run's chance, `RewardRoll`).
var _rolls: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
## By seat: the coins in its wallet.
var _wallets: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
## The seats whose starting coins came this run, a bit each.
var _funded: int = 0
## The coins on the floor: each one's number and where it lies, by the same index, in the order laid.
var _coin_numbers: PackedInt32Array = PackedInt32Array()
var _coin_at: PackedVector2Array = PackedVector2Array()
## The number the next coin laid gets.
var _next_coin: int = 0
## The coin numbers this machine's looks were last told lie there (`coin_changed`): a restore tells
## them gone for those it no longer holds. Not state: what was said here.
var _said_coins: Dictionary = {}


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
	events.room_cleared.connect(_on_room_cleared)
	events.room_entered.connect(_on_room_entered)
	events.enemy_died.connect(_on_enemy_died)
	events.run_stats_ruled.connect(_on_run_stats_ruled)
	# A command, heard at the tick's start (core/events, online-ready N2).
	events.listen(&"reward_pick_requested", _on_reward_pick_requested)


## A run's start: every offer, coin and wallet goes (each said), and the area is a fresh one's.
func begin_run() -> void:
	_clear_coins()
	SimFresh.renew(self)
	for seat in SEATS:
		_say_waiting(seat)
		_say_wallet(seat)


## The tick's step: the clears since the last step are rolled for; a seat whose wizard came gets
## its starting coins (once a run); each coin a wizard's feet reach is taken (seats in order, the
## first takes it).
func step(_delta: float) -> void:
	if actors == null:
		return
	if not _cleared.is_empty():
		var rooms: PackedInt32Array = _cleared.duplicate()
		_cleared.clear()
		for room: int in rooms:
			_roll_clear(room)
	for seat in SEATS:
		if _funded & (1 << seat) == 0 and actors.home_of_seat(seat) != ActorsScript.NONE:
			_funded |= 1 << seat
			_add_coins(seat, int(stat_of(seat, &"start_coins")))
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


# --- Asked ------------------------------------------------------------------------------

## Seat `seat`'s run stat `stat` (`RunStats.value_of`): its base, the run's changes, then the
## relics its wizard holds. For this area's own rules and tests: another area that reads a run stat
## (CB9's map, CB11's fountain) hears `run_stats_ruled` itself and works it out with `RunStats`, as
## areas never call each other.
func stat_of(seat: int, stat: StringName) -> float:
	return RunStats.value_of(stat, _run_changes, _relics_of(seat))


## The coins in seat `seat`'s wallet.
func wallet_of(seat: int) -> int:
	return _wallets[seat] if seat >= 0 and seat < SEATS else 0


## Spend `amount` coins of seat `seat`'s own wallet (a shop's buy: the shop is this area's, CB11):
## false, and nothing changes, when it holds fewer. Not for other areas (they never call this one).
func spend(seat: int, amount: int) -> bool:
	if seat < 0 or seat >= SEATS or amount < 0 or _wallets[seat] < amount:
		return false
	_add_coins(seat, -amount)
	return true


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
## before): gone for each coin it told of that no longer lies there, then every coin, every
## wallet and every seat's waiting offers.
func rebuild_derived() -> void:
	if events == null:
		return
	for number: int in _said_coins.keys():
		if not _coin_numbers.has(number):
			_said_coins.erase(number)
			events.coin_changed.emit(number, Vector2.ZERO, false)
	for at in _coin_numbers.size():
		_say_coin(_coin_numbers[at], _coin_at[at], true)
	for seat in SEATS:
		_say_wallet(seat)
		_say_waiting(seat)


# --- Heard ------------------------------------------------------------------------------

## The room `room` was cleared: rolled for at the next step.
func _on_room_cleared(_room_id: StringName, room: int) -> void:
	if not _cleared.has(room):
		_cleared.append(room)


## Room `room`'s clear: when a foe died in it (or in a world with no places), every seat with a
## wizard rolls its own offer.
func _roll_clear(room: int) -> void:
	var fought: bool = _fought.has(room) or _fought.has(RoomGrid.NO_PLACE)
	_erase(_fought, room)
	_erase(_fought, RoomGrid.NO_PLACE)
	if not fought or actors == null:
		return
	var table: RewardTable = registry.get_resource(TABLES, CLEAR_TABLE) as RewardTable if registry != null else null
	if table == null:
		push_warning("Rewards: no reward table '%s' (content/rewards), so a clear rewards nobody." % CLEAR_TABLE)
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


## Seat `player` picked choice `choice` of its offer `offer` (a command): given to its wizard and
## gone, or kept (not its offer, no such choice; `reward_refused` for no wizard, no room in the bag,
## a heal while down).
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
	if events != null:
		events.reward_taken.emit(player, offer, choice, _choice_view(row, choice))
	_say_waiting(player)


## A new world (FIRST_ROOM entered): the coins of the one before are gone with it, and its fights.
func _on_room_entered(_room_id: StringName, room: int) -> void:
	if room == EventsScript.FIRST_ROOM:
		_clear_coins()
		_fought.clear()


## A foe died at `position`: its room was fought in, and its coins land there (`EnemyBase.coins`,
## spread round it).
func _on_enemy_died(_killer: int, enemy: Node, position: Vector2, _shot: int) -> void:
	var body := enemy as Actor
	if body == null:
		return
	if not _fought.has(body.room):
		_fought.append(body.room)
	if body.data == null or body.is_add:
		# An add (a boss's waves, boss plan OB13) drops no coins: waves without end would fill wallets.
		return
	for i in body.data.coins:
		var spot: Vector2 = position + COIN_SPREAD[i % COIN_SPREAD.size()]
		if projectiles != null and (projectiles.grid().circle_blocked(spot, COIN_RADIUS) or not projectiles.grid().line_clear(position, spot)):
			spot = position
		lay_coin(spot)


## The run's own changes of the run stats (the Run area's, as a run of rooms begins).
func _on_run_stats_ruled(changes: Array[StatChange]) -> void:
	_run_changes = changes.duplicate()


# --- Inside -----------------------------------------------------------------------------

## Give seat `seat`'s wizard `count` of `kind` `id`. False, and nothing changes, when it cannot.
func _give(seat: int, kind: StringName, id: StringName, count: int) -> bool:
	match kind:
		RewardEntry.COINS:
			_add_coins(seat, count)
			return true
		RewardEntry.HEAL, RewardEntry.MAX_HEALTH:
			# Combat keeps an actor's health: the gift goes through it. A heal waits while down.
			var wizard: Actor = _wizard_of(seat)
			if wizard == null or events == null or (kind == RewardEntry.HEAL and wizard.is_down()):
				return false
			var heal: float = float(count) if kind == RewardEntry.HEAL else 0.0
			var more: float = float(count) if kind == RewardEntry.MAX_HEALTH else 0.0
			events.health_gift_requested.emit(actors.home_of_seat(seat), heal, more)
			return true
		RewardEntry.CARD:
			var body: Actor = _wizard_of(seat)
			if body == null or body.inventory == null:
				return false
			var stack: ItemStack = ItemStack.card(id, count)
			if not body.inventory.has_room(stack):
				return false
			return body.inventory.add(stack)
	return false


## The wizard of seat `seat` (its own body, also while it drives another), or null.
func _wizard_of(seat: int) -> Actor:
	if actors == null:
		return null
	var id: int = actors.home_of_seat(seat)
	return actors.node_of(id) as Actor if id != ActorsScript.NONE else null


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


func _add_coins(seat: int, amount: int) -> void:
	if amount == 0:
		return
	_wallets[seat] = maxi(_wallets[seat] + amount, 0)
	_say_wallet(seat)


func _clear_coins() -> void:
	var numbers: PackedInt32Array = _coin_numbers.duplicate()
	var at: PackedVector2Array = _coin_at.duplicate()
	_coin_numbers.clear()
	_coin_at.clear()
	for i in numbers.size():
		_say_coin(numbers[i], at[i], false)


## `list` without `value` (once: it holds each once).
static func _erase(list: PackedInt32Array, value: int) -> void:
	var at: int = list.find(value)
	if at >= 0:
		list.remove_at(at)


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
	var kind: StringName = offer.kinds[choice]
	var id: StringName = offer.ids[choice]
	var count: int = offer.counts[choice]
	var view: Dictionary = {"kind": kind, "id": id, "count": count, "name": "", "icon": null}
	if kind == RewardEntry.COINS:
		view["name"] = "%d coin%s" % [count, "" if count == 1 else "s"]
	elif kind == RewardEntry.HEAL:
		view["name"] = "Heal %d" % count
	elif kind == RewardEntry.MAX_HEALTH:
		view["name"] = "+%d max health" % count
	elif spells != null:
		# A card's name and icon are Spells' to say (no script outside core/spells reads a card).
		view["name"] = spells.component_name(id)
		view["icon"] = spells.component_icon(id)
	if String(view["name"]) == "":
		view["name"] = String(id)
	if kind == RewardEntry.CARD and count > 1:
		view["name"] = "%s x%d" % [view["name"], count]
	return view


func _say_waiting(seat: int) -> void:
	if events != null:
		events.rewards_waiting_changed.emit(seat, waiting_of(seat))


func _say_wallet(seat: int) -> void:
	if events != null:
		events.wallet_changed.emit(seat, _wallets[seat])


func _say_coin(number: int, at: Vector2, lying: bool) -> void:
	if lying:
		_said_coins[number] = true
	else:
		_said_coins.erase(number)
	if events != null:
		events.coin_changed.emit(number, at, lying)

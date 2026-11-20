extends RefCounted
## Each seat's quick-use slots as its corner panel shows them (the owner, 2026-11-20; the panel's
## `quick_cross.gd`): what each d-pad arm of the body the seat shows is bound to (`quick_bound`) and
## how many of it that body holds (`bag_changed`), told to the seat's panel (`set_quick`: the item's
## icon by `ItemLooks`, null for a slot bound to nothing). A body announced anew (`inventory_announced`:
## another body shown, a wizard made again) is drawn as it stands. Display only: the HUD's, made and
## bound by `panels.gd`; it keeps no rules and sends nothing. An item recharging after a use
## (`item_recharging`: an active relic's cooldown) is told to the slots bound to it
## (`set_quick_recharge`), again as a slot is bound to it, as last told (the HUD keeps no clock).

const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const SpellsScript := preload("res://core/spells/spells.gd")

const SEATS: int = 4
const SLOTS: int = 4

## The seats' corner panels, by seat (each has `set_quick`), and where icons are looked up.
var _panels: Array = []
var _registry: RegistryScript = null
var _spells: SpellsScript = null
## By seat * SLOTS + slot: the bag and id bound (`&""`: none).
var _bags: Array[StringName] = []
var _ids: Array[StringName] = []
## By seat: bag -> {id -> copies}, as `bag_changed` said last.
var _held: Array[Dictionary] = [{}, {}, {}, {}]
## By seat: drawn as it stands at the next change (a body announced anew).
var _at_once: Array[bool] = [true, true, true, true]
## The icon of an item with none of its own: one, so a count's change is never taken for another item.
var _no_icon: Texture2D = PlaceholderTexture2D.new()
## By seat: "bag/id" -> [seconds left, whole cooldown] as last told, for items recharging.
var _charges: Array[Dictionary] = [{}, {}, {}, {}]


func _init() -> void:
	_bags.resize(SEATS * SLOTS)
	_ids.resize(SEATS * SLOTS)
	_bags.fill(&"")
	_ids.fill(&"")


func bind(events: EventsScript, panels: Array, registry: RegistryScript, spells: SpellsScript) -> void:
	_panels = panels
	_registry = registry
	_spells = spells
	if events != null:
		events.quick_bound.connect(_on_quick_bound)
		events.bag_changed.connect(_on_bag_changed)
		events.inventory_announced.connect(_on_inventory_announced)
		events.item_recharging.connect(_on_item_recharging)


## What seat `seat`'s slot `slot` is bound to: [bag, id] (for tests).
func bound_of(seat: int, slot: int) -> Array[StringName]:
	return [_bags[seat * SLOTS + slot], _ids[seat * SLOTS + slot]]


## Everything forgotten (a run ended): the panels' slots go bound to nothing.
func clear() -> void:
	for seat in SEATS:
		_held[seat] = {}
		_charges[seat] = {}
		_at_once[seat] = true
		for slot in SLOTS:
			_bags[seat * SLOTS + slot] = &""
			_ids[seat * SLOTS + slot] = &""
			_tell(seat, slot, true)


func _on_inventory_announced(seat: int, _body: int) -> void:
	if seat >= 0 and seat < SEATS:
		_held[seat] = {}
		_charges[seat] = {}
		_at_once[seat] = true


func _on_quick_bound(seat: int, slot: int, bag: StringName, id: StringName) -> void:
	if seat < 0 or seat >= SEATS or slot < 0 or slot >= SLOTS:
		return
	_bags[seat * SLOTS + slot] = bag
	_ids[seat * SLOTS + slot] = id
	_tell(seat, slot, _at_once[seat])
	if slot == SLOTS - 1:
		# The announcement's last slot: later changes play.
		_at_once[seat] = false


func _on_bag_changed(seat: int, bag: StringName, ids: Array[StringName], counts: PackedInt32Array, _capacity: int) -> void:
	if seat < 0 or seat >= SEATS:
		return
	var copies: Dictionary = {}
	for at in mini(ids.size(), counts.size()):
		copies[ids[at]] = int(copies.get(ids[at], 0)) + counts[at]
	_held[seat][bag] = copies
	for slot in SLOTS:
		if _bags[seat * SLOTS + slot] == bag:
			_tell(seat, slot, _at_once[seat])


func _on_item_recharging(seat: int, bag: StringName, id: StringName, left: float, whole: float) -> void:
	if seat < 0 or seat >= SEATS:
		return
	var key: String = "%s/%s" % [bag, id]
	if left > 0.0:
		_charges[seat][key] = [left, whole]
	else:
		_charges[seat].erase(key)
	for slot in SLOTS:
		if _bags[seat * SLOTS + slot] == bag and _ids[seat * SLOTS + slot] == id:
			_tell_charge(seat, slot)


## Seat `seat`'s slot `slot`: its item's recharge as last told (none: ready).
func _tell_charge(seat: int, slot: int) -> void:
	if seat >= _panels.size() or _panels[seat] == null:
		return
	var key: String = "%s/%s" % [_bags[seat * SLOTS + slot], _ids[seat * SLOTS + slot]]
	var told: Array = _charges[seat].get(key, [0.0, 0.0])
	_panels[seat].call(&"set_quick_recharge", slot, float(told[0]), float(told[1]), _at_once[seat])


func _tell(seat: int, slot: int, at_once: bool) -> void:
	if seat >= _panels.size() or _panels[seat] == null:
		return
	var bag: StringName = _bags[seat * SLOTS + slot]
	var id: StringName = _ids[seat * SLOTS + slot]
	var icon: Texture2D = null
	var count: int = 0
	if id != &"":
		icon = ItemLooks.of(ItemKinds.kind_in(bag, id), id, _registry, _spells)["icon"] as Texture2D
		if icon == null:
			icon = _no_icon
		count = int((_held[seat].get(bag, {}) as Dictionary).get(id, 0))
	_panels[seat].call(&"set_quick", slot, icon, count, at_once)
	_tell_charge(seat, slot)

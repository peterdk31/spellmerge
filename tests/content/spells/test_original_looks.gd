extends "res://tests/support/suite.gd"
## The cards' looks (staffs C0, C0b): every modifier gives off a particle style, no modifier
## shares one with an infusion, the first six modifiers never share with each other, and the
## later ones share only the kinds docs/DECISIONS.md allows, so a shot shows which cards are on it.
##
## godot --headless --path . --script res://tests/content/spells/test_original_looks.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")

const RegistryScript := preload("res://core/registry/registry.gd")

## The first six modifiers, which never share a look with each other.
const FIRST_SIX: Array[StringName] = [&"split", &"pierce", &"homing", &"chain", &"bigger", &"faster"]

## The look kinds later modifiers may share (docs/DECISIONS.md, "The later cards' looks"): 9
## burst, 12 glitter, 15 weight, 16 ripple, 17 curl, 18 zig, 19 double, 20 converge, 21 drift. A
## share is for cards that rarely sit on one shot or say the same thing; a new card may take one
## of these kinds with no edit here (its folder alone adds it); any other kind must be its own.
const SHARED_KINDS: Array[int] = [9, 12, 15, 16, 17, 18, 19, 20, 21]

var _first_six: Array[ModifierBase] = []
var _later: Array[ModifierBase] = []
var _infusions: Array[ElementBase] = []


## Every modifier and infusion the registry finds, so a new card folder is checked with no edit.
func before_each() -> void:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	_first_six.clear()
	_later.clear()
	_infusions.clear()
	for res: Resource in registry.get_all(&"spells"):
		if res is ElementBase:
			_infusions.append(res as ElementBase)
		elif res is ModifierBase:
			var card := res as ModifierBase
			if FIRST_SIX.has(card.id):
				_first_six.append(card)
			else:
				_later.append(card)


func _all() -> Array[ModifierBase]:
	var all: Array[ModifierBase] = []
	all.append_array(_first_six)
	all.append_array(_later)
	return all


func test_the_registry_finds_the_cards() -> void:
	check_equal(_first_six.size(), FIRST_SIX.size(), "the first six")
	check(_later.size() > 20 and _infusions.size() >= 6, "the later modifiers (%d) and the infusions (%d)" % [_later.size(), _infusions.size()])


func test_every_modifier_has_a_look() -> void:
	for card: ModifierBase in _all():
		check(card.look_layer > 0 and card.look_layer < ManagerScript.LOOK_COUNT, "%s gives off a look" % card.id)


func test_no_modifier_shares_a_look_with_an_infusion() -> void:
	var taken: Dictionary = {}
	for infusion: ElementBase in _infusions:
		taken[infusion.look_layer] = infusion.id
	for card: ModifierBase in _all():
		check(not taken.has(card.look_layer), "%s's look is not an infusion's (kind %d, %s)" % [card.id, card.look_layer, str(taken.get(card.look_layer, ""))])


func test_no_first_modifier_shares_a_look() -> void:
	var seen: Dictionary = {}
	for card: ModifierBase in _first_six:
		check(not seen.has(card.look_layer), "%s has a look of its own among the first six (kind %d)" % [card.id, card.look_layer])
		seen[card.look_layer] = card.id
	for card: ModifierBase in _later:
		check(not seen.has(card.look_layer) or card.look_layer == 9, "%s does not hide a first card (kind %d)" % [card.id, card.look_layer])


func test_shared_looks_are_the_allowed_ones() -> void:
	var by_kind: Dictionary = {}
	for card: ModifierBase in _all():
		var ids: Array = by_kind.get(card.look_layer, [])
		ids.append(String(card.id))
		by_kind[card.look_layer] = ids
	for kind: int in by_kind:
		var ids: Array = by_kind[kind]
		if ids.size() < 2:
			continue
		check(SHARED_KINDS.has(kind), "kind %d is shared by %s, which is not allowed" % [kind, str(ids)])

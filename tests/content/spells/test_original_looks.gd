extends "res://tests/support/suite.gd"
## The cards' looks (staffs C0, C0b): every modifier gives off a particle style, no modifier
## shares one with an infusion, the first six modifiers never share with each other, and the
## later ones share only the kinds docs/DECISIONS.md allows, so a shot shows which cards are on it.
##
## godot --headless --path . --script res://tests/content/spells/test_original_looks.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")

const FIRST_SIX: Array[ModifierBase] = [
	preload("res://content/spells/modifiers/split/split.tres"),
	preload("res://content/spells/modifiers/pierce/pierce.tres"),
	preload("res://content/spells/modifiers/homing/homing.tres"),
	preload("res://content/spells/modifiers/chain/chain.tres"),
	preload("res://content/spells/modifiers/bigger/bigger.tres"),
	preload("res://content/spells/modifiers/faster/faster.tres"),
]

const LATER: Array[ModifierBase] = [
	preload("res://content/spells/modifiers/zap/zap.tres"),
	preload("res://content/spells/modifiers/blast/blast.tres"),
	preload("res://content/spells/modifiers/bounce/bounce.tres"),
	preload("res://content/spells/modifiers/deflect/deflect.tres"),
	preload("res://content/spells/modifiers/echo/echo.tres"),
	preload("res://content/spells/modifiers/ghost/ghost.tres"),
	preload("res://content/spells/modifiers/growth/growth.tres"),
	preload("res://content/spells/modifiers/heavy/heavy.tres"),
	preload("res://content/spells/modifiers/hold/hold.tres"),
	preload("res://content/spells/modifiers/linger/linger.tres"),
	preload("res://content/spells/modifiers/magnet/magnet.tres"),
	preload("res://content/spells/modifiers/mirror/mirror.tres"),
	preload("res://content/spells/modifiers/overcharge/overcharge.tres"),
	preload("res://content/spells/modifiers/possess/possess.tres"),
	preload("res://content/spells/modifiers/reach/reach.tres"),
	preload("res://content/spells/modifiers/recoil/recoil.tres"),
	preload("res://content/spells/modifiers/relay/relay.tres"),
	preload("res://content/spells/modifiers/return/return.tres"),
	preload("res://content/spells/modifiers/shield/shield.tres"),
	preload("res://content/spells/modifiers/short_delay/short_delay.tres"),
	preload("res://content/spells/modifiers/siphon/siphon.tres"),
	preload("res://content/spells/modifiers/slow/slow.tres"),
	preload("res://content/spells/modifiers/sniper/sniper.tres"),
	preload("res://content/spells/modifiers/spiral/spiral.tres"),
	preload("res://content/spells/modifiers/sticky/sticky.tres"),
]

const INFUSIONS: Array[ElementBase] = [
	preload("res://content/spells/elements/fire/fire.tres"),
	preload("res://content/spells/elements/frost/frost.tres"),
	preload("res://content/spells/elements/storm/storm.tres"),
	preload("res://content/spells/elements/void/void.tres"),
	preload("res://content/spells/elements/lightning/lightning.tres"),
	preload("res://content/spells/elements/mend/mend.tres"),
]

## The kinds later modifiers may share, and with whom (docs/DECISIONS.md, "The later cards'
## looks"). A share is for cards that rarely sit on one shot or say the same thing; anything
## not listed here must have a kind of its own.
const ALLOWED_SHARES: Dictionary = {
	9: ["split", "blast", "overcharge"],
	12: ["sniper", "reach"],
	15: ["heavy", "sticky"],
	16: ["growth", "linger"],
	17: ["spiral", "return", "relay", "recoil"],
	18: ["bounce", "zap", "deflect"],
	19: ["echo", "mirror", "ghost"],
	20: ["magnet", "siphon", "possess"],
	21: ["slow", "hold", "short_delay"],
}


func _all() -> Array[ModifierBase]:
	var all: Array[ModifierBase] = []
	all.append_array(FIRST_SIX)
	all.append_array(LATER)
	return all


func test_every_modifier_has_a_look() -> void:
	for card: ModifierBase in _all():
		check(card.look_layer > 0 and card.look_layer < ManagerScript.LOOK_COUNT, "%s gives off a look" % card.id)


func test_no_modifier_shares_a_look_with_an_infusion() -> void:
	var taken: Dictionary = {}
	for infusion: ElementBase in INFUSIONS:
		taken[infusion.look_layer] = infusion.id
	for card: ModifierBase in _all():
		check(not taken.has(card.look_layer), "%s's look is not an infusion's (kind %d, %s)" % [card.id, card.look_layer, str(taken.get(card.look_layer, ""))])


func test_no_first_modifier_shares_a_look() -> void:
	var seen: Dictionary = {}
	for card: ModifierBase in FIRST_SIX:
		check(not seen.has(card.look_layer), "%s has a look of its own among the first six (kind %d)" % [card.id, card.look_layer])
		seen[card.look_layer] = card.id
	for card: ModifierBase in LATER:
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
		check(ALLOWED_SHARES.has(kind), "kind %d is shared by %s, which is not allowed" % [kind, str(ids)])
		if ALLOWED_SHARES.has(kind):
			var allowed: Array = ALLOWED_SHARES[kind]
			for id: String in ids:
				check(allowed.has(id), "%s may not share kind %d" % [id, kind])

extends "res://tests/support/suite.gd"
## The builder tree's data (docs/milestones/M2-builder-tree.md, part T3): each compiled spell
## knows its own card slots (`CompiledSpell.card_slots`), and `Spells.staff_view` gives every
## cast a `tree` of rows, depth first, built from the real cards.
##
## godot --headless --path . --script res://tests/core/test_staff_tree.gd

const SpellsScript := preload("res://core/spells/spells.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

var _registry: Node
var _spells: SpellsScript
var _staff: StaffBase


func before_each() -> void:
	_registry = own(RegistryScript.new()) as Node
	_registry.call("scan")
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _registry
	_staff = StaffBase.new()
	_staff.id = &"test"
	_staff.slots = 20
	_staff.draw = 1


func _ids(text: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for word in text.split(" ", false):
		out.append(&"" if word == "-" else StringName(word))
	return out


## The tree of the staff's first cast.
func _tree(text: String) -> Array:
	var view: Dictionary = _spells.staff_view(_ids(text), _staff)
	var casts: Array = view["casts"]
	check(not casts.is_empty(), "%s casts something" % text)
	return (casts[0] as Dictionary)["tree"] if not casts.is_empty() else []


## Rows as [depth, trigger, slots] for an easy compare.
func _shape(rows: Array) -> Array:
	var out: Array = []
	for row: Dictionary in rows:
		out.append([int(row["depth"]), int(row["trigger"]), Array(row["slots"] as PackedInt32Array)])
	return out


func test_each_trigger_has_a_row_with_its_own_payload() -> void:
	# on hit · on expire · bolt · fire · nova · zap · nova
	var rows: Array = _tree("on_hit on_expire bolt fire nova zap nova")
	check_equal(rows.size(), 3, "the bolt, then a row for each trigger: %s" % [_shape(rows)])
	if rows.size() != 3:
		return
	check_equal(_shape(rows)[0], [0, -1, [2]], "the bolt's row holds its own card")
	check_equal(rows[0]["name"], _spells.component_name(&"bolt"), "named by its carrier")
	check_equal(_shape(rows)[1], [1, 0, [3, 4]], "on hit fires the fire nova")
	check_equal(rows[1]["name"], _spells.component_name(&"on_hit"), "a trigger row is named by its trigger card")
	check_equal(int(rows[2]["depth"]), 1, "on expire at the same depth")
	check_equal(int(rows[2]["trigger"]), 1, "on expire's own row")
	check((rows[2]["slots"] as PackedInt32Array).has(6), "on expire fires the last nova: %s" % [rows[2]["slots"]])
	check(rows[0].has("mana") and rows[0].has("damage"), "the cast's first row has its numbers")
	check(not rows[1].has("mana"), "other rows do not")


func test_payloads_nest_depth_first() -> void:
	# The decoy's timer fires a fire bolt whose on expire fires the frost nova (the blast joins
	# it); on hurt takes the group after that: the last bolt.
	var rows: Array = _tree("timer on_hurt hold decoy on_expire fire bolt blast frost nova bolt")
	var shape: Array = _shape(rows)
	check_equal(shape.size(), 4, "decoy, timer, on expire, on hurt: %s" % [shape])
	if shape.size() != 4:
		return
	check_equal(shape[0], [0, -1, [2, 3]], "the held decoy")
	check_equal(shape[1], [1, 0, [5, 6]], "the timer fires the fire bolt")
	check_equal(shape[2], [2, 4, [7, 8, 9]], "whose on expire fires the blast frost nova, one level in")
	check_equal(shape[3], [1, 1, [10]], "on hurt fires the last bolt")
	check_equal(rows[3]["name"], _spells.component_name(&"on_hurt"), "named On Hurt")


func test_a_payload_with_a_multicast_has_a_row_per_carrier() -> void:
	var rows: Array = _tree("on_hit bolt double nova frost bolt")
	var shape: Array = _shape(rows)
	check_equal(shape, [[0, -1, [1]], [1, 0, [2, 3]], [1, -1, [4, 5]]], "the double on the first carrier's row, the frost bolt on its own row with no trigger")
	if rows.size() == 3:
		check_equal(rows[2]["name"], _spells.component_name(&"bolt"), "the further carrier is named by its carrier")


func test_a_fallback_has_a_row() -> void:
	var rows: Array = _tree("fire")
	check_equal(_shape(rows), [[0, -1, [0]]], "fire on the caster")
	if rows.size() == 1:
		check_equal(rows[0]["name"], SpellsScript.TREE_ON_CASTER, "named for where it lands")
	var payload: Array = _tree("on_hit bolt frost")
	check_equal(_shape(payload), [[0, -1, [1]], [1, 0, [2]]], "frost where the bolt hits")
	if payload.size() == 2:
		check_equal(payload[1]["name"], _spells.component_name(&"on_hit"), "the trigger row keeps the trigger's name")


func test_a_wasted_trigger_has_no_row() -> void:
	check_equal(_shape(_tree("on_hit bolt")), [[0, -1, [1]]], "on hit with nothing to fire")
	# On block needs a shield or deflect on its carrier; its payload is read but wasted with it.
	check_equal(_shape(_tree("on_block bolt nova")), [[0, -1, [1]]], "on block with no shield")


func test_card_slots_are_set_where_the_cards_attach() -> void:
	var compiled: CompiledStaff = _spells.compile_staff(_ids("fire homing bolt nova"), _staff)
	var bolt: CompiledSpell = compiled.casts[0].group.spells[0]
	check_equal(Array(bolt.card_slots), [0, 1, 2], "the infusion and modifier, then the carrier")
	var nova: CompiledSpell = compiled.casts[1].group.spells[0]
	check_equal(Array(nova.card_slots), [3], "the next cast's nova alone")
	var wasted: CompiledStaff = _spells.compile_staff(_ids("return beam"), _staff)
	check_equal(Array(wasted.casts[0].group.spells[0].card_slots), [1], "a wasted card is not one of the carrier's")

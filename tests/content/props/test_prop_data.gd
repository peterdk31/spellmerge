extends "res://tests/support/suite.gd"
## Every prop (props W6, docs/milestones/props.md): its data is sound (`PropBase.problems`, with the
## names the game knows), its staffs pass the spell validator, a body of it can be made from the
## shared scene, and every cast its triggers make it can pay from a full pool (a still prop's pools
## never refill). Found by folder (`content/props/<id>/<id>.tres`), so a new prop is checked too; the
## test exploding barrel (tests/gameplay/actor/fixtures) stands in for the casts until the first props (W9).
##
## godot --headless --path . --script res://tests/content/props/test_prop_data.gd

const RegistryScript := preload("res://core/registry/registry.gd")
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const PropNames := preload("res://tests/content/props/prop_names.gd")
const EXPLODING_BARREL: PropBase = preload("res://tests/gameplay/actor/fixtures/exploding_barrel.tres")
const SCENE: PackedScene = preload("res://content/props/base/prop.tscn")

var _world: Fixture


func before_each() -> void:
	_world = Fixture.new(root)


func after_each() -> void:
	_world.free_all()


func _props() -> Array[PropBase]:
	var found: Array[PropBase] = []
	for item: Variant in _world.registry.call("get_all", "props"):
		if item is PropBase:
			found.append(item as PropBase)
	return found


func test_every_prop_is_sound() -> void:
	var known: Dictionary = PropNames.known(_world.registry)
	for data in _props():
		check_equal(data.problems(known), PackedStringArray(), "%s: its data is sound" % data.id)
		for entry: StaffCards in data.staffs:
			check_equal(SpellValidator.check_staff(entry.staff).size(), 0, "%s: its staff is valid" % data.id)


## Every prop's look loads (props W7): each state has one (`PropBase.problems` names one missing),
## every layer's picture is there, and a mask has lit pixels to give off from; the test exploding
## barrel too.
func test_every_props_look_loads_and_its_masks_are_not_empty() -> void:
	var all: Array[PropBase] = _props()
	all.append(EXPLODING_BARREL)
	for data in all:
		check_equal(data.look_problems(), PackedStringArray(), "%s: its looks are sound" % data.id)
		for look in data.looks:
			for i in look.layers.size():
				var layer: PropLayer = look.layers[i]
				for source in layer.motes:
					if source.from == MoteSource.From.MASK:
						check(not ArtPixels.pixels_of(layer.texture).is_empty(), "%s: the mask of %s's layer %d has lit pixels" % [data.id, look.state_id, i])


func test_the_shared_body_has_every_part_a_prop_needs() -> void:
	for data in _props():
		check(data.scene == SCENE, "%s stands on the shared body" % data.id)
	var body: Actor = SCENE.instantiate() as Actor
	var kinds: Array[String] = []
	for child in body.get_children():
		for kind: Script in [Health, Hurtbox, Footprint, Caster, PropStateTriggers, ActorController, Mover]:
			if is_instance_of(child, kind):
				kinds.append(kind.get_global_name())
	check_equal(kinds, ["Health", "Hurtbox", "Footprint", "Caster", "PropStateTriggers"] as Array[String], "health, a hurt shape, ground, staffs and state triggers; no controller, no Mover")
	check_equal(body.idle_team, Fixture.ActorsScript.TEAM_WORLD, "the world's")
	check(body.get_node_or_null("Sprite") is Sprite2D, "a Sprite for its looks' first layer (a hit flashes it)")
	check(body.get_node_or_null("PropLook") is PropLook, "its look")
	body.free()


func test_every_cast_a_prop_reacts_with_is_paid_from_a_full_pool() -> void:
	var all: Array[PropBase] = _props()
	all.append(EXPLODING_BARREL)
	for data in all:
		var body: Actor = _world.add(PropBody.make(data), Vector2.ZERO)
		for state in data.states.list:
			for row in state.triggers:
				if row.cast <= 0:
					continue
				var at: int = row.cast - 1
				check(body.caster.has_staff(at), "%s: %s casts staff %d, which it holds built" % [data.id, state.state_id, row.cast])
				var cost: float = body.caster.next_cast_mana(at)
				check(cost >= 0.0 and cost <= body.caster.max_mana_of(at), "%s: staff %d costs %s of its %s" % [data.id, row.cast, cost, body.caster.max_mana_of(at)])

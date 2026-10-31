extends "res://tests/core/test_card_rules.gd"
## The card rules on the horde's swarm (horde swarm S3, docs/milestones/horde-swarm.md, "Where a
## rule needs a full actor: promotion"): every card does on a swarmer what it does on a full enemy
## of the same kind. It plays every card on every carrier as test_card_rules.gd does (the same
## cards found by itself, the same scenes, the same world and trace), with every enemy that casts
## nothing made a standing `crypt_mite` (its data with no walking speed): once as full actors of its
## scene (with their own AI), once as swarmers of a swarm. The two traces must be equal, line for
## line: hits, damage, statuses, deaths, moves, pulls, swaps, possessions, the bodies' places and
## health. `possess` on a swarmer promotes it to the full actor (`Swarm.promote`), so its trace
## goes on as the full actor's; the test checks that it was promoted wherever possess is not
## wasted. Scenes in which no such enemy stands (the open floor, a shooter, a donor, the wizard
## hurt) are left out: they hold no swarmer.
##
## It extends the card rules test for its probes and its world: the four matrix tests here play the
## parity instead of the works-or-wasted check, and the test of two alike casts plays them on
## swarmers.
##
## godot --headless --path . --script res://tests/core/test_card_rules_swarm.gd

const SwarmScript := preload("res://gameplay/horde/swarm.gd")
const MiteData: EnemyBase = preload("res://content/enemies/crypt_mite/crypt_mite.tres")

## True while `_make_world` makes swarmers.
var _as_swarm: bool = false
## The standing mite kind by health (a weak target's and the rest's).
var _kinds: Dictionary = {}
## The world of the last run (read after it for its swarm's promotions).
var _last_world: World = null


func _make_world() -> World:
	var world: World = World.new(root, _shelf, _staff)
	world.kind_of = _kind
	world.as_swarm = _as_swarm
	_last_world = world
	return world


## The standing crypt mite of `health`, prepared once.
func _kind(health: float) -> SwarmKind:
	if _kinds.has(health):
		return _kinds[health]
	var data := MiteData.duplicate() as EnemyBase
	data.move_speed = 0.0
	data.max_health = health
	var kind := SwarmKind.new()
	kind.enemy_id = data.id
	kind.prepare(data)
	_kinds[health] = kind
	return kind


func test_the_same_cast_writes_the_same_trace() -> void:
	# On swarmers too: two alike casts in the busiest scene with swarmers write the same trace.
	for form in _forms:
		var cards: Array[StringName] = [form.id]
		if form.carries_payload():
			cards.append(_payload.id)
		var seconds: float = minf(form.wind_up + form.lifetime + AFTER_LIFE, LONGEST)
		_as_swarm = true
		var first: PackedStringArray = _run(cards, form, CROWD_AGAIN, seconds)
		var second: PackedStringArray = _run(cards, form, CROWD_AGAIN, seconds)
		_as_swarm = false
		check(first == second, "`%s` on swarmers writes another trace the second time: %s" % [form.id, _first_difference(first, second)])
		check(not first.is_empty(), "`%s` on swarmers writes something" % form.id)


func test_every_modifier_works_or_is_wasted_on_every_carrier() -> void:
	var cards: Array[SpellComponent] = []
	cards.assign(_modifiers)
	_parity("Modifiers", cards, true)


func test_every_trigger_works_or_is_wasted_on_every_carrier() -> void:
	var cards: Array[SpellComponent] = []
	cards.assign(_triggers)
	_parity("Triggers", cards)


func test_every_infusion_works_or_is_wasted_on_every_carrier() -> void:
	var cards: Array[SpellComponent] = []
	cards.assign(_elements)
	_parity("Infusions", cards)


func test_every_multicast_works_or_is_wasted_on_every_carrier() -> void:
	var cards: Array[SpellComponent] = []
	cards.assign(_multicasts)
	_parity("Multicasts", cards)


## Every card of `cards` on every carrier, in each of its scenes with swarmers: the swarm's trace
## equals the full actors'. `with_possess`: possess is among them, so some swarmer is promoted.
func _parity(title: String, cards: Array[SpellComponent], with_possess: bool = false) -> void:
	if _payload == null or _shot == null:
		return
	var started: int = Time.get_ticks_msec()
	var played: int = 0
	var differ: int = 0
	var promoted: int = 0
	for card in cards:
		var possess: bool = card is ModifierBase and (card as ModifierBase).behaviour == ModifierBase.Behaviour.POSSESS
		for form in _forms:
			if reach(form) < 0.0 or (not ONLY_FORM.is_empty() and String(form.id) != ONLY_FORM):
				continue
			for scene in _scenes_of(card):
				if not _has_swarmers(scene):
					continue
				var with: Array[StringName] = _casts(card, form, scene, false)[0]
				var seconds: float = _seconds(form, scene, with)
				_as_swarm = false
				var full: PackedStringArray = _run(with, form, scene, seconds)
				_as_swarm = true
				var swarm: PackedStringArray = _run(with, form, scene, seconds, full)
				_as_swarm = false
				played += 1
				if swarm != full:
					differ += 1
					if OS.has_environment("SWARM_EXPLAIN"):
						print("FULL:\n%s\nSWARM:\n%s" % ["\n".join(full.slice(0, 30)), "\n".join(swarm.slice(0, 30))])
					check(false, "`%s` on `%s` (scene: %s): a swarmer's trace is not a full mite's: %s" % [card.id, form.id, scene["name"], _first_difference(full, swarm)])
				var swarm_of: SwarmScript = _last_world.swarm if _last_world != null else null
				if swarm_of != null and swarm_of.promoted_count > 0:
					promoted += 1
				elif possess and not _compiler.compile_staff(with, _staff).wasted.has(0) and full.size() > 0 and _possessed(full):
					check(false, "`%s` on `%s` possessed a full mite but promoted no swarmer" % [card.id, form.id])
	print("\n%s on swarmers: %d casts, %d differ from full mites, %d promoted a swarmer, %d ms\n" % [title, played, differ, promoted, Time.get_ticks_msec() - started])
	if with_possess:
		check(promoted > 0, "possess promoted a swarmer somewhere")


## How long the cast of `with` on `form` runs in `scene` (as `_changes` runs it).
func _seconds(form: FormBase, scene: Dictionary, with: Array[StringName]) -> float:
	var seconds: float = minf(form.wind_up + form.lifetime + AFTER_LIFE, LONGEST)
	if scene.get("repeat", false):
		var plain: CompiledStaff = _compiler.compile_staff(with, _staff)
		var delay: float = plain.casts[0].delay if not plain.is_empty() else 0.0
		seconds = minf(delay + form.wind_up + form.lifetime + AFTER_LIFE, LONGEST)
	return seconds


## True when `scene` puts an enemy that casts nothing (a swarmer here) in the world.
static func _has_swarmers(scene: Dictionary) -> bool:
	if scene.get("donor", false):
		return false
	for key: String in ["line", "crowd", "second", "side", "back", "behind"]:
		if scene.get(key, false):
			return true
	return false


## True when the trace asked for a possession.
static func _possessed(trace: PackedStringArray) -> bool:
	for line in trace:
		if line.contains(" possess "):
			return true
	return false


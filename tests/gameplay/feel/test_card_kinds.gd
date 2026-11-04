extends "res://tests/support/suite.gd"
## Spectacle by card (gameplay/feel/card_kinds.gd; docs/milestones/spell-spectacle-2.md, S2): a
## shot's motes and marks come from its spell's cards, looked up through its tag. A kind that names
## a card is that card's spell's only; a card no kind names sheds exactly its look layer's, as
## before (every card of the content is checked); a shot with no spell sheds by its look; a tag a
## rebuilt staff reuses gets its new spell's kinds; the trails' births carry the tag; a kind that
## names nothing is thrown only where a cue names it; a room may name its walls' kinds; and the
## kind table holds far more than the 16 kinds the shader's arrays did.

const MotesScript := preload("res://gameplay/feel/mote.gd")
const MarksScript := preload("res://gameplay/feel/marks.gd")
const CardKindsScript := preload("res://gameplay/feel/card_kinds.gd")
const SpectacleScript := preload("res://gameplay/feel/spectacle.gd")
const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const ARENA: StringName = &"arena_01"


## A spell runtime with only what the motes ask: `profile(tag)` and the tag of the cue being sent.
class FakeSpells:
	extends Node
	var spells: Dictionary = {}
	var cue_tag: int = 0

	func profile(tag: int) -> CompiledSpell:
		return spells.get(tag)


var registry: RegistryScript


func before_each() -> void:
	registry = own(RegistryScript.new()) as RegistryScript
	registry.scan()


## The content's mote kinds, in id order.
func _content_kinds() -> Array[MoteKind]:
	var kinds: Array[MoteKind] = []
	for found: Resource in registry.get_all(&"motes"):
		kinds.append(found as MoteKind)
	return kinds


func _pool(kinds: Array[MoteKind] = []) -> MotesScript:
	var motes: MotesScript = own(MotesScript.new(4096, 0, kinds if not kinds.is_empty() else _content_kinds())) as MotesScript
	root.add_child(motes)
	return motes


## A spell of the form `form`, the infusions `elements` and the modifiers `modifiers`.
static func _spell(form: StringName, elements: Array[StringName], modifiers: Array[StringName]) -> CompiledSpell:
	var spell := CompiledSpell.new()
	spell.form_id = form
	spell.element_ids = elements
	spell.modifier_ids = modifiers
	return spell


## The packed look of the cards `ids` (their look layers), as the staff compiler packs it.
func _look(ids: Array[StringName]) -> int:
	var kinds := PackedInt32Array()
	for id in ids:
		var card: Resource = registry.get_resource(&"spells", id)
		var layer: Variant = card.get(&"look_layer") if card != null else null
		if layer != null:
			kinds.append(int(layer))
	return ProjectilesScript.pack_look(kinds)


func _book(motes: MotesScript, spells: FakeSpells, marks: MarksScript = null) -> CardKindsScript:
	var book := CardKindsScript.new()
	book.registry = registry
	book.spells = spells
	book.use_motes(motes)
	book.use_marks(marks)
	return book


func _ids(motes: MotesScript, kinds: PackedInt32Array) -> Array[StringName]:
	var ids: Array[StringName] = []
	for k in kinds:
		ids.append(motes.kinds()[k].id)
	return ids


func test_a_kind_naming_a_card_is_that_cards_spells_only() -> void:
	var motes: MotesScript = _pool()
	var spells: FakeSpells = own(FakeSpells.new()) as FakeSpells
	var heavy: int = SpellTag.make(0, 0, 1, 0)
	var sticky: int = SpellTag.make(0, 0, 2, 0)
	var fire_heavy: int = SpellTag.make(0, 0, 3, 0)
	var both: int = SpellTag.make(0, 0, 4, 0)
	spells.spells[heavy] = _spell(&"bolt", [], [&"heavy"])
	spells.spells[sticky] = _spell(&"bolt", [], [&"sticky"])
	spells.spells[fire_heavy] = _spell(&"bolt", [&"fire"], [&"heavy"])
	spells.spells[both] = _spell(&"bolt", [], [&"heavy", &"sticky"])
	var book: CardKindsScript = _book(motes, spells)
	check(motes.has_card_kinds(), "the content has a kind that names a card (grit, heavy's)")
	check_equal(_ids(motes, book.motes_of(heavy, _look([&"heavy"]))), [&"grit"] as Array[StringName], "heavy's spell sheds heavy's grit")
	check_equal(_ids(motes, book.motes_of(sticky, _look([&"sticky"]))), _ids(motes, motes.kinds_of_look(_look([&"sticky"]))), "sticky, on heavy's layer, sheds that layer's as before")
	check_equal(_ids(motes, book.motes_of(fire_heavy, _look([&"fire", &"heavy"]))), [&"ember", &"grit"] as Array[StringName], "fire and heavy: fire's embers and heavy's grit")
	check_equal(_ids(motes, book.motes_of(both, _look([&"heavy", &"sticky"]))), [&"grit"] as Array[StringName], "heavy and sticky: the layer has no kind of its own, so heavy's grit")
	check_equal(book.motes_of(0, _look([&"heavy"])), motes.kinds_of_look(_look([&"heavy"])), "a shot with no spell (an enemy's): its look's")
	check_equal(book.motes_of(SpellTag.make(0, 0, 9, 0), _look([&"heavy"])), motes.kinds_of_look(_look([&"heavy"])), "a tag whose spell is gone: its look's")


## Every card of the content that no kind names sheds exactly what its look layer shed before S2
## (and in the same order), alone and with fire.
func test_every_card_no_kind_names_keeps_its_looks_motes() -> void:
	var motes: MotesScript = _pool()
	var spells: FakeSpells = own(FakeSpells.new()) as FakeSpells
	var book: CardKindsScript = _book(motes, spells)
	var node: int = 0
	var checked: int = 0
	for found: Resource in registry.get_all(&"spells"):
		var kind: StringName = found.call(&"kind") if found.has_method(&"kind") else &""
		if not [&"form", &"element", &"modifier"].has(kind):
			continue
		var id: StringName = found.get(&"id")
		if not motes.kinds_of_card(id).is_empty():
			continue
		for elements: Array[StringName] in [[] as Array[StringName], [&"fire"] as Array[StringName]]:
			var cards: Array[StringName] = elements.duplicate()
			var spell: CompiledSpell
			if kind == &"form":
				spell = _spell(id, elements, [])
			elif kind == &"element":
				cards.append(id)
				spell = _spell(&"bolt", cards, [])
			else:
				cards.append(id)
				spell = _spell(&"bolt", elements, [id])
			node += 1
			var tag: int = SpellTag.make(0, 0, node % 500, 0)
			spells.spells[tag] = spell
			var look: int = _look(cards)
			check_equal(book.motes_of(tag, look), motes.kinds_of_look(look), "%s %s sheds its look's motes" % [id, elements])
			checked += 1
	check(checked > 40, "every card was checked (%d spells)" % checked)


func test_a_tag_a_rebuilt_staff_reuses_gets_its_new_spell() -> void:
	var motes: MotesScript = _pool()
	var spells: FakeSpells = own(FakeSpells.new()) as FakeSpells
	var book: CardKindsScript = _book(motes, spells)
	var look: int = _look([&"heavy"])
	var tag: int = SpellTag.make(1, 2, 3, 5)
	spells.spells[tag] = _spell(&"bolt", [], [&"heavy"])
	check_equal(_ids(motes, book.motes_of(tag, look)), [&"grit"] as Array[StringName], "the first build: heavy")
	# Eight rebuilds later the generation ring is back at 5: the same tag, another spell.
	check_equal(SpellTag.make(1, 2, 3, 5 + 8), tag, "the generation ring wraps after 8")
	spells.spells[tag] = _spell(&"bolt", [], [&"sticky"])
	# A spell is checked once a frame: the next frame sees the new build (a frame late at most).
	book.new_frame()
	check_equal(book.motes_of(tag, look), motes.kinds_of_look(look), "the new build's sticky: its layer's, not the old spell's grit")
	check_equal(book.kept(), 1, "one entry, worked out again")


func test_the_kept_spells_are_bounded() -> void:
	var motes: MotesScript = _pool()
	var spells: FakeSpells = own(FakeSpells.new()) as FakeSpells
	var book: CardKindsScript = _book(motes, spells)
	for node in CardKindsScript.CACHE_MOST + 10:
		var tag: int = SpellTag.make(node / 500, 0, node % 500, 0)
		spells.spells[tag] = _spell(&"bolt", [], [&"heavy"])
		book.motes_of(tag, _look([&"heavy"]))
	check(book.kept() <= CardKindsScript.CACHE_MOST, "at most CACHE_MOST kept: %d" % book.kept())


func test_a_trail_birth_gives_off_its_spells_kinds() -> void:
	var motes: MotesScript = _pool()
	var spells: FakeSpells = own(FakeSpells.new()) as FakeSpells
	var book: CardKindsScript = _book(motes, spells)
	motes.use_cards(book)
	var heavy: int = SpellTag.make(1023, 3, 511, 7)
	var sticky: int = SpellTag.make(5, 1, 7, 2)
	spells.spells[heavy] = _spell(&"bolt", [], [&"heavy"])
	spells.spells[sticky] = _spell(&"bolt", [], [&"sticky"])
	var layer: int = int(registry.get_resource(&"spells", &"heavy").get(&"look_layer"))
	check_equal(_ids(motes, book.layer_motes(heavy, layer)), [&"grit"] as Array[StringName], "heavy's layer in heavy's spell: grit")
	check_equal(book.layer_motes(sticky, layer), motes.kinds_of_layer(layer), "in sticky's: the layer's, as before")
	check_equal(book.layer_motes(0, layer), motes.kinds_of_layer(layer), "a shot with no spell: the layer's")
	var stride: int = ProjectilesScript.SPARK_BIRTH_STRIDE
	var births := PackedFloat32Array()
	births.resize(stride * 2)
	for n in 2:
		var i: int = n * stride
		var tag: int = [heavy, sticky][n]
		births[i + ProjectilesScript.SPARK_BACK_X] = -1.0
		births[i + ProjectilesScript.SPARK_KIND] = float(layer)
		births[i + ProjectilesScript.SPARK_LOOK] = float(_look([&"heavy"]))
		births[i + ProjectilesScript.SPARK_CORE] = 1.0
		births[i + ProjectilesScript.SPARK_TAG] = float(tag & ((1 << ProjectilesScript.SPARK_TAG_BITS) - 1))
		births[i + ProjectilesScript.SPARK_TAG + 1] = float(tag >> ProjectilesScript.SPARK_TAG_BITS)
		check_equal(ProjectilesScript.spark_tag(births, i), tag, "a spell's tag (above 2^24) is read back whole from its floats")
	motes.give_off(births, 2)
	var kinds: Array[StringName] = []
	for row in 2:
		kinds.append(motes.kinds()[roundi(motes.row_data(row)[MotesScript.ROW_KIND] * MotesScript.KIND_CODE)].id)
	check_equal(kinds, [&"grit", motes.kinds()[motes.kinds_of_layer(layer)[0]].id] as Array[StringName], "heavy's birth gives off grit, sticky's its layer's")


func test_the_manager_writes_a_births_tag() -> void:
	var mgr: ProjectilesScript = own(ProjectilesScript.new()) as ProjectilesScript
	mgr.actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	root.add_child(mgr)
	var tag: int = SpellTag.make(700, 2, 300, 6)
	var slot: int = mgr.spawn(0, Vector2(40.0, 40.0), Vector2.RIGHT * 120.0, 2.0, 4.0, 1, 0, tag)
	check(slot >= 0, "a shot")
	check_equal(mgr.get_tag_of(slot), tag, "it carries the tag")
	mgr.set_look(slot, _look([&"heavy"]))
	mgr.spark_motes = true
	var found: bool = false
	for frame in 120:
		mgr.update_draw()
		mgr.step(1.0 / 60.0)
		for n in mgr.spark_birth_count:
			check_equal(ProjectilesScript.spark_tag(mgr.spark_births, n * ProjectilesScript.SPARK_BIRTH_STRIDE), tag, "its births carry its tag")
			found = true
		if found:
			break
	check(found, "it gave off a birth")


func test_a_kind_that_names_nothing_is_thrown_only_where_named() -> void:
	var motes: MotesScript = _pool()
	var ash: int = motes.kind_index(&"ash")
	check(ash >= 0, "ash is a kind")
	for layer in range(0, MotesScript.LOOK_LAYERS + 1):
		check(not motes.kinds_of_look(1 << maxi(layer - 1, 0) if layer > 0 else 0).has(ash), "no look sheds ash (layer %d)" % layer)
	check(not motes.surface_kinds().has(ash), "no wall sheds it")
	var fireball: CueBase = registry.get_resource(&"cues", &"fireball") as CueBase
	var named: bool = false
	for part: Dictionary in fireball.parts:
		named = named or (part.get("part") == &"motes" and StringName(part.get("kind", "")) == &"ash")
	check(named, "the fireball cue names it")
	var world: Array = _feel()
	var feel: FeelScript = world[1]
	var before: int = feel.motes().next_row()
	feel.play_cue(&"fireball", 0, Vector2(80.0, 80.0), Vector2.RIGHT, 30.0, Color(1.0, 0.5, 0.2), _look([&"fire"]))
	var rows: Array[StringName] = []
	var ash_source: int = -1
	for row in range(before, feel.motes().next_row()):
		var data: PackedFloat32Array = feel.motes().row_data(row)
		var id: StringName = feel.motes().kinds()[roundi(data[MotesScript.ROW_KIND] * MotesScript.KIND_CODE)].id
		if not rows.has(id):
			rows.append(id)
		if id == &"ash":
			ash_source = roundi(data[MotesScript.ROW_SOURCE] * MotesScript.SOURCE_CODE)
	check(rows.has(&"ash"), "a fireball throws ash: %s" % [rows])
	check(ash_source >= MotesScript.TABLE_SOURCE, "in the colours of what burned (its part's `colours`, a ramp-table row): %d" % ash_source)
	var cue := CueBase.new()
	cue.id = &"test"
	cue.parts = [{"part": &"motes", "kind": &"ash", "colours": &"stone"}]
	check_equal(cue.problems().size(), 1, "a part's colours are spell or surface: %s" % [cue.problems()])


func test_more_kinds_than_the_old_arrays_load_and_draw() -> void:
	var kinds: Array[MoteKind] = []
	for n in 40:
		var kind := MoteKind.new()
		kind.id = StringName("k%d" % n)
		kind.gravity = 100.0 + n
		kind.look_layers = PackedInt32Array([0])
		kinds.append(kind)
	var motes: MotesScript = _pool(kinds)
	check_equal(motes.kinds().size(), 40, "every kind is kept (the shader held 16)")
	check_equal(motes.kind_numbers(39)[0].x, 139.0, "the last kind's numbers are in its row")
	motes.burst(39, Vector2.ZERO, Vector2.RIGHT, 1, Vector2(10.0, 10.0), 0.0, Vector2.ZERO, Vector2(1.0, 1.0), 0, Color.WHITE)
	var data: PackedFloat32Array = motes.row_data(0)
	check_equal(roundi(data[MotesScript.ROW_KIND] * MotesScript.KIND_CODE), 39, "a row names kind 39")
	# As a renderer that keeps the colour as bytes reads it back.
	check_equal(roundi(roundf(data[MotesScript.ROW_KIND] * 255.0) / 255.0 * MotesScript.KIND_CODE), 39, "and keeps naming it in bytes")
	check(motes.mote_land(0).z < INF, "and it flies by its own numbers (mote_land reads them)")


func test_a_mark_naming_a_card_is_that_cards_spells_only() -> void:
	var motes: MotesScript = _pool()
	var kinds: Array[MarkKind] = []
	for found: Resource in registry.get_all(&"marks"):
		kinds.append(found as MarkKind)
	var dent := MarkKind.new()
	dent.id = &"dent"
	dent.form = "crack"
	dent.cards = [&"heavy"]
	kinds.append(dent)
	var marks: MarksScript = own(MarksScript.new(0, kinds)) as MarksScript
	root.add_child(marks)
	var spells: FakeSpells = own(FakeSpells.new()) as FakeSpells
	var book: CardKindsScript = _book(motes, spells, marks)
	var heavy: int = SpellTag.make(0, 0, 1, 0)
	var frost_heavy: int = SpellTag.make(0, 0, 2, 0)
	var frost: int = SpellTag.make(0, 0, 3, 0)
	spells.spells[heavy] = _spell(&"bolt", [], [&"heavy"])
	spells.spells[frost_heavy] = _spell(&"bolt", [&"frost"], [&"heavy"])
	spells.spells[frost] = _spell(&"bolt", [&"frost"], [])
	var dent_k: int = marks.kind_index(&"dent")
	check_equal(book.marks_of(heavy, _look([&"heavy"])), PackedInt32Array([dent_k]), "heavy's spell leaves heavy's dent")
	check_equal(book.marks_of(frost_heavy, _look([&"frost", &"heavy"])), PackedInt32Array([marks.kind_index(&"frost"), dent_k]), "with frost: frost's rime and the dent")
	check_equal(book.marks_of(frost, _look([&"frost"])), marks.kinds_of_look(_look([&"frost"])), "frost alone: its look's, as before")
	check_equal(book.marks_of(0, _look([&"heavy"])), PackedInt32Array(), "a shot with no spell: its look's (none for heavy's layer)")


func test_a_room_names_its_walls_kinds() -> void:
	var world: Array = _feel()
	var feel: FeelScript = world[1]
	var spectacle: SpectacleScript = feel.get_node("Spectacle") as SpectacleScript
	var room := RoomBase.new()
	room.debris_colors = PackedColorArray([Color("c8b090"), Color("8c6c48"), Color("4c3828")])
	spectacle.use_room(room)
	check_equal(spectacle.surface_kinds(), feel.motes().surface_kinds(), "a room that names none: every surface kind")
	room.surface_kinds = [&"grit", &"no_such_kind"]
	spectacle.use_room(room)
	check_equal(spectacle.surface_kinds(), PackedInt32Array([feel.motes().kind_index(&"grit")]), "a room's own (an unknown one left out)")
	var before: int = feel.motes().next_row()
	feel.projectiles.impact_look = 0
	(world[0] as EventsScript).projectile_impact.emit(0, null, Vector2(60.0, 60.0), Vector2.RIGHT)
	var rows: Array[StringName] = []
	for row in range(before, feel.motes().next_row()):
		var id: StringName = feel.motes().kinds()[roundi(feel.motes().row_data(row)[MotesScript.ROW_KIND] * MotesScript.KIND_CODE)].id
		if not rows.has(id):
			rows.append(id)
	check(rows.has(&"grit") and not rows.has(&"chip"), "a wall hit sheds the room's kinds, not chips: %s" % [rows])
	var source: int = roundi(feel.motes().row_data(feel.motes().next_row() - 1)[MotesScript.ROW_SOURCE] * MotesScript.SOURCE_CODE)
	check(source >= MotesScript.TABLE_SOURCE, "in the walls' colours (a ramp-table row): %d" % source)


func test_feel_sheds_a_hits_and_a_cues_spell_kinds() -> void:
	var world: Array = _feel()
	var bus: EventsScript = world[0]
	var feel: FeelScript = world[1]
	var spells: FakeSpells = world[2]
	var tag: int = SpellTag.make(0, 1, 4, 3)
	spells.spells[tag] = _spell(&"bolt", [&"fire"], [&"heavy"])
	var enemy := Node2D.new()
	root.add_child(enemy)
	own(enemy)
	var motes: MotesScript = feel.motes()
	var before: int = motes.next_row()
	feel.projectiles.impact_look = _look([&"fire", &"heavy"])
	feel.projectiles.impact_tag = tag
	bus.projectile_impact.emit(0, enemy, Vector2(60.0, 60.0), Vector2.RIGHT)
	feel.projectiles.impact_tag = 0
	check(_row_ids(motes, before).has(&"grit"), "a hit of the spell sheds its heavy's grit: %s" % [_row_ids(motes, before)])
	before = motes.next_row()
	spells.cue_tag = tag
	bus.cue_shown.emit(0, &"fireball", Vector2(90.0, 60.0), Vector2.RIGHT, 30.0, Color(1.0, 0.5, 0.2), _look([&"fire", &"heavy"]))
	spells.cue_tag = 0
	check(_row_ids(motes, before).has(&"grit"), "its blast's cue throws its cards' kinds too: %s" % [_row_ids(motes, before)])
	before = motes.next_row()
	bus.cue_shown.emit(0, &"fireball", Vector2(90.0, 60.0), Vector2.RIGHT, 30.0, Color(1.0, 0.5, 0.2), _look([&"fire", &"heavy"]))
	check(not _row_ids(motes, before).has(&"grit"), "a cue with no spell: its look's (heavy's layer has none)")


func _row_ids(motes: MotesScript, from: int) -> Array[StringName]:
	var found: Array[StringName] = []
	for row in range(from, motes.next_row()):
		var id: StringName = motes.kinds()[roundi(motes.row_data(row)[MotesScript.ROW_KIND] * MotesScript.KIND_CODE)].id
		if not found.has(id):
			found.append(id)
	return found


func _feel() -> Array:
	var bus: EventsScript = own(EventsScript.new()) as EventsScript
	var feel: FeelScript = own(FeelScript.new()) as FeelScript
	var spells: FakeSpells = own(FakeSpells.new()) as FakeSpells
	var preset := FeelPresetScript.new()
	preset.hit_sound = &""
	feel.events = bus
	feel.registry = registry
	feel.actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	feel.projectiles = own(ProjectilesScript.new()) as ProjectilesScript
	feel.spells = spells
	feel.drive_engine = false
	feel.preset = preset
	root.add_child(feel)
	bus.room_entered.emit(ARENA)
	feel.step(1.0 / 60.0)
	return [bus, feel, spells]

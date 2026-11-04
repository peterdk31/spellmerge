extends "res://tests/support/screenshot.gd"
## Spectacle by card (gameplay/feel/card_kinds.gd; docs/milestones/spell-spectacle-2.md, S2), before
## and after, for the owner's eyes. `card_motes`: a heavy bolt hitting a body as any shot with no
## spell sheds (its look layer's: sparks, as before S2), the same bolt of a spell with heavy (heavy's
## own grit), a fire-and-heavy bolt (fire's embers and heavy's grit), and a fireball cue without and
## with its ash (a kind no card names, thrown because the cue names it). Columns are moments after it
## happened, each cell its own; `card_motes_heavy_4x` is the heavy rows' second column at 4x, and
## `card_motes_ash_4x` the fireballs' last two columns at 3x.

const ActorsScript := preload("res://core/actors/actors.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const DUMMY := preload("res://content/enemies/training_dummy/idle.svg")
const FIRE := preload("res://content/spells/elements/fire/fire.tres")
const HEAVY := preload("res://content/spells/modifiers/heavy/heavy.tres")
## Frames from each cell's moment to the shot (60 a second).
const PHASES: Array[int] = [3, 12, 30, 72]
const ROW_HEIGHT: float = 62.0
const SIZE: float = 40.0
const ROWS: Array[StringName] = [&"heavy, no spell", &"heavy's spell", &"fire + heavy", &"fireball, no ash", &"fireball"]


## A spell runtime that knows the sheet's spells by tag (the game's knows the staffs' only).
class SheetSpells:
	extends Node
	var spells: Dictionary = {}
	var cue_tag: int = 0

	func profile(tag: int) -> CompiledSpell:
		return spells.get(tag)


var _spells: SheetSpells = null
var _heavy_tag: int = 0
var _fire_heavy_tag: int = 0


func take() -> void:
	if not need(["Feel", "Actors", "Events", "Projectiles"]):
		return
	var feel: Node = root.get_node("Feel")
	feel.set("drive_engine", false)
	var spectacle: Node = feel.call(&"spectacle") as Node
	spectacle.call(&"_on_room_entered", &"arena_01")
	_spells = SheetSpells.new()
	root.add_child(_spells)
	_heavy_tag = SpellTag.make(0, 0, 1, 0)
	_fire_heavy_tag = SpellTag.make(0, 0, 2, 0)
	_spells.spells[_heavy_tag] = _spell([], [&"heavy"])
	_spells.spells[_fire_heavy_tag] = _spell([&"fire"], [&"heavy"])
	spectacle.set(&"spells", _spells)
	await _sheet(ROWS, "card_motes")


static func _spell(elements: Array[StringName], modifiers: Array[StringName]) -> CompiledSpell:
	var spell := CompiledSpell.new()
	spell.form_id = &"bolt"
	spell.element_ids = elements
	spell.modifier_ids = modifiers
	return spell


## One sheet: a row for each of `rows`, a column for each phase.
func _sheet(rows: Array[StringName], shot_name: String) -> void:
	var actors: ActorsScript = root.get_node("Actors") as ActorsScript
	actors.clear()
	await settle(30)
	lay_floor()
	var cells: Array = []
	for r in rows.size():
		label(String(rows[r]), Vector2(4.0, 40.0 + ROW_HEIGHT * r))
		for c in PHASES.size():
			var actor: int = actors.open(ActorsScript.TEAM_WIZARDS, 0)
			var at := Vector2(170.0 + 120.0 * c, 46.0 + ROW_HEIGHT * r)
			cells.append([actor, at, PHASES[c], r])
	for c in PHASES.size():
		label("%.2f s" % (PHASES[c] / 60.0), Vector2(150.0 + 120.0 * c, 2.0))
	var longest: int = PHASES.max()
	for frame in longest:
		for cell: Array in cells:
			if longest - frame == cell[2]:
				_make(int(cell[3]), int(cell[0]), cell[1] as Vector2)
		await physics_frame
	var image: Image = await grab()
	save(image, shot_name)
	# The heavy rows side by side at their second moment, and the fireballs at their last two.
	save_crop(image, on_screen(Vector2(290.0, 46.0 + ROW_HEIGHT * 0.5)), shot_name + "_heavy_4x", Vector2i(60, 110), 4)
	save_crop(image, on_screen(Vector2(470.0, 46.0 + ROW_HEIGHT * 3.5)), shot_name + "_ash_4x", Vector2i(150, 120), 3)


## Set off row `row`'s moment by `actor` at `at`.
func _make(row: int, actor: int, at: Vector2) -> void:
	var events: Node = root.get_node("Events")
	var shots: ProjectilesScript = root.get_node("Projectiles") as ProjectilesScript
	var heavy: int = 1 << (HEAVY.look_layer - 1)
	var fire: int = 1 << (FIRE.look_layer - 1)
	match row:
		0, 1, 2:
			var target: Sprite2D = _body(DUMMY, at)
			shots.impact_look = heavy | (fire if row == 2 else 0)
			shots.impact_core = FIRE.tint if row == 2 else Color.WHITE
			shots.impact_form = &"bolt"
			shots.impact_tag = [0, _heavy_tag, _fire_heavy_tag][row]
			events.emit_signal(&"projectile_impact", actor, target, at, Vector2.RIGHT)
			shots.impact_look = 0
			shots.impact_core = Color.WHITE
			shots.impact_form = &""
			shots.impact_tag = 0
		_:
			var cue: CueBase = root.get_node("Feel").call(&"cue_of", &"fireball") as CueBase
			var parts: Array[Dictionary] = cue.parts
			if row == 3:
				var without: Array[Dictionary] = []
				for part: Dictionary in parts:
					if StringName(part.get("kind", "")) != &"ash":
						without.append(part)
				cue.parts = without
			events.emit_signal(&"cue_shown", actor, &"fireball", at, Vector2.RIGHT, SIZE, FIRE.tint, fire)
			cue.parts = parts


## A body showing `texture` at `at` (its `Sprite`), left on the sheet.
func _body(texture: Texture2D, at: Vector2) -> Sprite2D:
	var body := Node2D.new()
	body.global_position = at
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	body.add_child(sprite)
	root.add_child(body)
	return sprite

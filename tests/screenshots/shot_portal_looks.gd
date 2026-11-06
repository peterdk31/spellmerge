extends "res://tests/support/screenshot.gd"
## Portals as the game draws them (docs/milestones/portal.md): a plain portal a held beam goes
## through, out of its exit; a fire homing split portal whose three exits fan ahead, a held
## beam into its mouth coming out of all three as burning legs that bend onto a dummy off the line; and a frost portal of player 2
## with a held beam of its own. Each gate is a ring in its caster's colour (gameplay/feel/
## portal_rings.gd), the mouth swirling in, the exits out with a notch, a dotted line between.
## `portal_looks` is the whole screen and `portal_looks_ring` a crop of the homing row.

const ActorSeats := preload("res://tests/support/actor_seats.gd")
const DUMMY := preload("res://content/enemies/training_dummy/idle.svg")
## (The homing row's dummy stands within the homing card's reach, 160 px, of the exits.)
## Each row: the portal's cards, the beam's cards, where both are cast from, and a dummy (INF for none).
const ROWS: Array = [
	[[&"hold", &"portal"], [&"hold", &"beam"], Vector2(40.0, 60.0), Vector2.INF],
	[[&"hold", &"fire", &"homing", &"split", &"portal"], [&"hold", &"beam"], Vector2(40.0, 200.0), Vector2(270.0, 240.0)],
	[[&"hold", &"frost", &"portal"], [&"hold", &"beam"], Vector2(40.0, 330.0), Vector2(320.0, 330.0)],
]


func take() -> void:
	if not need(["Spells", "Projectiles", "Feel"]):
		return
	settle_frames = 8
	var spells: Node = root.get_node("Spells")
	var projectiles: Node = root.get_node("Projectiles")
	projectiles.call("set_bounds", Rect2(Vector2.ZERO, SCREEN))
	var actors: ActorSeats.ActorsScript = ActorSeats.autoload()
	if actors == null:
		fail("there is no Actors autoload")
		return
	var wizards: PackedInt32Array = ActorSeats.seat_wizards(actors, 2)
	# A staff with room for every row's cards, and no spread, so the shot shows the rule.
	var staff_base := StaffBase.new()
	staff_base.id = &"portal_looks"
	staff_base.slots = 8
	staff_base.cooldown = 0.0
	staff_base.spread = 0.0
	lay_floor()
	for row: Array in ROWS:
		if (row[3] as Vector2).is_finite():
			var dummy := Node2D.new()
			dummy.position = row[3]
			root.add_child(dummy)
			place(DUMMY, 1.0, row[3])
			projectiles.call("add_target", dummy, 10.0, 1)
	for i in ROWS.size():
		var row: Array = ROWS[i]
		var wizard: int = wizards[0] if i < 2 else wizards[1]
		var portal: Array[StringName] = []
		portal.assign(row[0])
		var beam: Array[StringName] = []
		beam.assign(row[1])
		var staff: int = (i % 2) * 2
		spells.call("install_staff", wizard, staff, spells.call("compile_staff", portal, staff_base))
		spells.call("install_staff", wizard, staff + 1, spells.call("compile_staff", beam, staff_base))
		spells.call("cast_staff", wizard, staff, row[2], Vector2.RIGHT, 100.0)
		spells.call("cast_staff", wizard, staff + 1, row[2], Vector2.RIGHT, 100.0)
		label(" ".join(PackedStringArray(portal)) + "  +  " + " ".join(PackedStringArray(beam)), row[2] + Vector2(0.0, -40.0))
	await settle()
	await shot("portal_looks")
	await snap(Vector2(220.0, 210.0), "portal_looks_ring", Vector2i(200, 150), 3)

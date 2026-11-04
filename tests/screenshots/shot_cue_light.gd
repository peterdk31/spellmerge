extends "res://tests/support/screenshot.gd"
## Cues lighting the room (docs/milestones/spell-spectacle-2.md, S6 item 4): in the crypt arena
## made dark (ambient 0.6, so the light reads), with spell light on, a row of cues played as player
## 1's at once: `heal`, `level_up`, `revive`, `shield_block`, `rune_burst` and `blast`, a few
## frames in (`cue_light`, and `cue_light_2x` round the row). Before the `light` part their
## flashes lit by their kinds (`SpellLight.EFFECT_LIGHT`); a cue with a `light` part lights by it
## instead.

const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ROOM := preload("res://content/rooms/crypt/arena_01.tscn")
const CUES: Array[StringName] = [&"heal", &"level_up", &"revive", &"shield_block", &"rune_burst", &"blast"]
const MIDDLE := Vector2(320.0, 200.0)
const GAP: float = 80.0


func take() -> void:
	if not need(["Feel"]):
		return
	var feel: Node = root.get_node("Feel")
	var actors: ActorSeats.ActorsScript = ActorSeats.autoload()
	if actors == null:
		fail("there is no Actors autoload")
		return
	ActorSeats.seat_wizards(actors)
	var room: Node = ROOM.instantiate()
	root.add_child(room)
	feel.set("drive_engine", false)
	feel.call("set_spell_light", true)
	if feel.call("light") == null:
		fail("no spell light with the setting on")
		return
	await settle(20)
	feel.call("light").call("set_ambient", 0.6)
	for i in CUES.size():
		var at: Vector2 = MIDDLE + Vector2((float(i) - (CUES.size() - 1) * 0.5) * GAP, 0.0)
		feel.call("play_cue", CUES[i], 0, at, Vector2.RIGHT, 24.0)
	await settle(4)
	var image: Image = await grab()
	save(image, "cue_light")
	save_crop(image, MIDDLE, "cue_light_2x", Vector2i(240, 50), 2)

extends "res://tests/support/suite.gd"
## Each kind of pickup's sound (gameplay/feel/pickup_sounds.gd; the owner's ask of 2026-11-19): a
## coin, a key, a reroll, a potion and a reward each play their own, every other kind the card's;
## every sound is a file the game's registry finds; one sound plays once a frame at most (a boss's
## coins are one clink); a pickup where nobody of this machine hears plays nothing (Audio's ears,
## connected biomes CB12) and does not use up its frame; `item_picked_up` plays it. Each plays on an
## Audio of the test's own over a registry of the test's own (silent streams).
const PickupSoundsScript := preload("res://gameplay/feel/pickup_sounds.gd")
const AudioScript := preload("res://core/audio/audio.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const SoundBook := preload("res://tests/core/audio/sound_book.gd")

const OWN_SOUNDS: Array[StringName] = [ItemKinds.COIN, ItemKinds.KEY, ItemKinds.REROLL, ItemKinds.POTION, EventsScript.PICKUP_REWARD]

var audio: AudioScript
var sounds: PickupSoundsScript


func before_each() -> void:
	var book: SoundBook = own(SoundBook.new()) as SoundBook
	book.know(_every_sound())
	audio = AudioScript.new()
	audio.registry = book
	root.add_child(audio)
	sounds = PickupSoundsScript.new()
	sounds.audio = audio


func after_each() -> void:
	audio.clear_world()
	audio.free()


static func _every_sound() -> Array[StringName]:
	return PickupSoundsScript.ids()


## Heard only west of x = 100.
static func _west(at: Vector2) -> bool:
	return at.x < 100.0


func test_each_kind_has_its_own_sound_and_the_rest_the_cards() -> void:
	check_equal(PickupSoundsScript.sound_of(ItemKinds.COIN), &"pickup_coin", "a coin")
	check_equal(PickupSoundsScript.sound_of(ItemKinds.KEY), &"pickup_key", "a key")
	check_equal(PickupSoundsScript.sound_of(ItemKinds.REROLL), &"pickup_reroll", "a reroll")
	check_equal(PickupSoundsScript.sound_of(ItemKinds.POTION), &"pickup_potion", "a potion")
	check_equal(PickupSoundsScript.sound_of(EventsScript.PICKUP_REWARD), &"pickup_reward", "a reward")
	for kind: StringName in [ItemKinds.CARD, ItemKinds.STAFF, ItemKinds.RELIC, &"something_new"]:
		check_equal(PickupSoundsScript.sound_of(kind), &"pickup_card", "%s: the card's" % kind)
	var seen: Dictionary = {}
	for kind: StringName in OWN_SOUNDS:
		seen[PickupSoundsScript.sound_of(kind)] = true
	seen[PickupSoundsScript.sound_of(ItemKinds.CARD)] = true
	check_equal(seen.size(), 6, "six sounds, each its own")
	check_equal(_every_sound().size(), 6, "and the six are every pickup sound")


func test_every_sound_is_a_file_the_registry_finds() -> void:
	var registry: RegistryScript = own(RegistryScript.new()) as RegistryScript
	registry.scan()
	for id: StringName in _every_sound():
		check(registry.get_sound(id) is AudioStreamRandomizer, "%s: its baked variants are found" % id)


func test_one_sound_plays_once_a_frame_at_most() -> void:
	check(sounds.picked_up(ItemKinds.COIN, Vector2(10, 0), 5) >= 0, "the first coin of a frame clinks")
	for i in 19:
		check_equal(sounds.picked_up(ItemKinds.COIN, Vector2(10 + i, 0), 5), -1, "the others in that frame do not")
	check(sounds.picked_up(ItemKinds.KEY, Vector2(10, 0), 5) >= 0, "another kind in that frame plays")
	check(sounds.picked_up(ItemKinds.CARD, Vector2(10, 0), 5) >= 0, "a card in that frame plays")
	check_equal(sounds.picked_up(ItemKinds.RELIC, Vector2(10, 0), 5), -1, "a relic, the card's sound, not again")
	check(sounds.picked_up(ItemKinds.COIN, Vector2(10, 0), 6) >= 0, "a coin the next frame clinks")


func test_a_pickup_nobody_here_hears_plays_nothing() -> void:
	audio.ears.heard = _west
	check_equal(sounds.picked_up(ItemKinds.COIN, Vector2(400, 0), 5), -1, "in a room nobody of this machine is in: silent")
	check(sounds.picked_up(ItemKinds.COIN, Vector2(40, 0), 5) >= 0, "and it did not use up the frame for one heard")


func test_item_picked_up_plays_its_kinds_sound() -> void:
	var bus: EventsScript = own(EventsScript.new()) as EventsScript
	sounds.bind(bus)
	bus.item_picked_up.emit(0, ItemKinds.POTION, &"potion_heal", Vector2(10, 0))
	check_equal(sounds.picked_up(ItemKinds.POTION, Vector2(10, 0), Engine.get_process_frames()), -1, "the event played this frame's potion")
	check(sounds.picked_up(ItemKinds.KEY, Vector2(10, 0), Engine.get_process_frames()) >= 0, "and no other kind's")


func test_with_no_audio_nothing_plays() -> void:
	var silent := PickupSoundsScript.new()
	check_equal(silent.picked_up(ItemKinds.COIN, Vector2.ZERO, 1), -1, "no Audio: silent")

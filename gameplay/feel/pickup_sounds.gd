extends RefCounted
## Each kind of pickup's own sound (the owner's ask of 2026-11-19): it hears `item_picked_up` (an
## actor picked up an item of a kind, at a world point; core/events) and plays its kind's sound
## there through Audio (`Audio.play(id, at)`), whose ears leave it silent in a room nobody of this
## machine is in (connected biomes CB12). A coin, a key, a reroll and a potion each have their own;
## a card, a staff, a relic and any other kind share the card's papery flick; a reward item's offer
## taken (`PICKUP_REWARD`) plays the grandest. The sounds are generated (`audio/sfx/pickup_*/`).
##
## One sound plays once a frame at most: a boss's handful of coins taken in one frame is one clink,
## never twenty stacked. Feel owns one; it is view only and allocates nothing as it plays.
##
##     var sounds := PickupSounds.new()
##     sounds.audio = audio
##     sounds.bind(events)

const EventsScript := preload("res://core/events/events.gd")
const AudioScript := preload("res://core/audio/audio.gd")

## The sound of each kind with one of its own; every other kind's is `OTHER`.
const SOUNDS: Dictionary[StringName, StringName] = {
	ItemKinds.COIN: &"pickup_coin",
	ItemKinds.KEY: &"pickup_key",
	ItemKinds.REROLL: &"pickup_reroll",
	ItemKinds.POTION: &"pickup_potion",
	EventsScript.PICKUP_REWARD: &"pickup_reward",
}
const OTHER: StringName = &"pickup_card"

## The Audio service the sounds play on (null: silent).
var audio: AudioScript = null

## The frame each sound last played in (-1: never).
var _played: Dictionary[StringName, int] = {}


func _init() -> void:
	for id: StringName in ids():
		_played[id] = -1


func bind(events: EventsScript) -> void:
	if events != null:
		events.item_picked_up.connect(_on_item_picked_up)


## The sound a pickup of `kind` plays.
static func sound_of(kind: StringName) -> StringName:
	return SOUNDS.get(kind, OTHER)


## Every pickup sound, each once (`OTHER` last).
static func ids() -> Array[StringName]:
	var found: Array[StringName] = []
	for kind: StringName in SOUNDS:
		found.append(SOUNDS[kind])
	found.append(OTHER)
	return found


## A pickup of `kind` at `at` in drawn frame `frame`: its sound plays there, unless it already
## played in this frame. The voice used, or -1 for none (played already, nobody hears there, no
## sound or no Audio).
func picked_up(kind: StringName, at: Vector2, frame: int) -> int:
	var id: StringName = sound_of(kind)
	if audio == null or _played[id] == frame:
		return -1
	var voice: int = audio.play(id, at)
	if voice >= 0:
		_played[id] = frame
	return voice


func _on_item_picked_up(_actor: int, kind: StringName, _id: StringName, at: Vector2) -> void:
	picked_up(kind, at, Engine.get_process_frames())

class_name BossIntroHold
extends RefCounted
## A boss's intro as the game's (docs/milestones/boss-intro.md, rule 2): the game stops on the
## room's tick for it, and only commands move it on, so on every machine and in a replay it opens,
## turns its pages and closes on the same ticks. Flow's state (it holds one, as it holds its
## `RoomAdds`); the HUD draws it from the events alone and knows nothing of this.
##
## - **It opens** (`open_in`) at the end of a room's setup, for the first boss with an intro
##   (`EnemyBase.boss_intro`) among the room's own enemies, when the run's rules have intros on
##   (`SessionRules.boss_intros`), and never twice in a room: the game stops (`Sim.stop(STOP)`) and
##   `boss_intro_opened` goes out, fresh.
## - **A page turns** (`turn`) when a seat's A names the page it is on (`boss_intro_next_requested`):
##   two presses of one page on one tick turn it once. `boss_intro_paged`; past the last page it
##   closes.
## - **It closes** (`close`): the stop is let go (the game goes on when no other stop stands: a pause
##   menu, a waited-for pad) and `boss_intro_closed` goes out. Flow closes it too when its boss leaves
##   the tree (`watch`, a step that runs through its stop), when the last seat leaves, and with the
##   room's enemies (`clear`: the room or the run ends).
## - **A snapshot** saves and restores its members; `rebuild_derived` tells it open again, not
##   fresh, so the HUD shows that page already revealed (rule 3), or closed (no actor) when none is.

const ActorsScript := preload("res://core/actors/actors.gd")
const EventsScript := preload("res://core/events/events.gd")

## The reason the intro stops the game (`Sim.stop`).
const STOP: StringName = &"boss_intro"

## Not state: the bus (set by Flow).
const DERIVED: Array[StringName] = [&"events"]
## State as who it points at: the boss whose intro is open.
const REFS: Array[StringName] = [&"boss"]

var events: EventsScript = null

## The boss whose intro is open (null when none is, or it went).
var boss: Node = null
## Its actor id (kept: the closing names it after its body went).
var boss_id: int = ActorsScript.NONE
## The page it is on (0 the first).
var page: int = 0
## True while it is open (the game stands stopped for STOP).
var opened: bool = false
## True once the room's intro opened: it never opens twice in a room (`clear` forgets it).
var done: bool = false


## Open the intro of the first boss with one among `enemies` (the room's own, as they stood), on
## `game` (the run's sim: its rules and its stops). True when it opened.
func open_in(enemies: Array[Node], game: Sim) -> bool:
	if opened or done or game == null or game.rules.boss_intros == 0:
		return false
	for enemy: Node in enemies:
		var actor := enemy as Actor
		if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree() or actor.id == ActorsScript.NONE:
			continue
		if actor.data == null or not actor.data.boss or actor.data.boss_intro == null:
			continue
		boss = actor
		boss_id = actor.id
		page = 0
		opened = true
		done = true
		game.stop(STOP)
		_tell_opened(true)
		return true
	return false


## A seat asked for the next page, having seen `shown` (`boss_intro_next_requested`): the page turns
## only while `shown` is still the page; past the last it closes. True when it closed.
func turn(shown: int, game: Sim) -> bool:
	if not opened or shown != page:
		return false
	var intro: BossIntro = intro_of()
	page += 1
	if intro == null or page >= intro.pages():
		close(game)
		return true
	if events != null:
		events.boss_intro_paged.emit(page)
	return false


## Close it (nothing when it is not open): the stop is let go and `boss_intro_closed` told. The room's
## intro stays done. True when it closed.
func close(game: Sim) -> bool:
	if not opened:
		return false
	var id: int = boss_id
	opened = false
	boss = null
	boss_id = ActorsScript.NONE
	page = 0
	if game != null:
		game.go(STOP)
	if events != null:
		events.boss_intro_closed.emit(id)
	return true


## Close it when its boss is gone from the tree (Flow's step, run through STOP). True when it closed.
func watch(game: Sim) -> bool:
	if not opened:
		return false
	if is_instance_valid(boss) and boss.is_inside_tree():
		return false
	return close(game)


## The room's enemies went (the next room, the run's end): closed if open, and the next room may open
## its own.
func clear(game: Sim) -> void:
	close(game)
	done = false


## The intro of the boss open, or null.
func intro_of() -> BossIntro:
	if not is_instance_valid(boss):
		return null
	var actor := boss as Actor
	if actor == null or actor.data == null:
		return null
	return actor.data.boss_intro


## After a snapshot was restored: told open again, not fresh (rule 3), so the HUD shows the page; told
## closed when none is open (no actor: a HUD showing one, its own run's, closes it), so the HUD never
## guesses either way.
func rebuild_derived() -> void:
	if opened:
		_tell_opened(false)
	elif events != null:
		events.boss_intro_closed.emit(ActorsScript.NONE)


func _tell_opened(fresh: bool) -> void:
	var intro: BossIntro = intro_of()
	if events == null or intro == null:
		return
	var data: EnemyBase = (boss as Actor).data
	events.boss_intro_opened.emit(boss_id, data.shown_name(), data.lore, intro, page, fresh)

class_name BossIntroWait
extends RefCounted
## Whether a boss shown waits for its intro, as the view sees it (docs/milestones/boss-intro.md,
## rule 5): the HUD's boss bar and entrance banner and Feel's entrance cue each keep one, so none of
## them depends on which event comes first, and none names another.
##
## A boss shown with no intro (`boss_shown`'s `has_intro` false) never waits: its bar, banner and cue
## come at once. One with an intro waits: for its intro's close (`boss_intro_closed`), when its intro
## opened (`boss_intro_opened`, before or after it was shown), or else for the end of the frame it was
## shown on (`settle`, called once a frame by its owner; while another's intro is open, the end of
## the frame that one closes on): an intro opens on the room's tick, in the
## same call as its body is shown, so one that has not opened by then does not open (the run's rule
## off for automation, `SessionRules.boss_intros`; a boss the sandbox spawned or a phase called). Then
## it is `released`: `played` true when its intro played (no banner and no entrance cue: the overlay was
## the entrance), false when none did (the banner and the cue, as for a boss with no intro).
##
##     var wait := BossIntroWait.new()
##     wait.bind(events)
##     wait.released.connect(func(actor: int, played: bool) -> void: ...)
##     wait.settle()   # once a frame
##
## View only: it never reaches the game.

const ActorsScript := preload("res://core/actors/actors.gd")

## The boss `actor` waits no more: its intro closed (`played`) or none opened for it.
signal released(actor: int, played: bool)

## The bosses shown with an intro that has not opened yet (actor ids), to release at `settle`.
var _waiting: PackedInt32Array = PackedInt32Array()
## The boss whose intro is open (ActorsScript.NONE: none), released when it closes.
var _open: int = ActorsScript.NONE


## Hear the bus's boss events (a null bus: nothing).
func bind(events: Node) -> void:
	if events == null:
		return
	events.connect(&"boss_shown", _on_shown)
	events.connect(&"boss_intro_opened", _on_opened)
	events.connect(&"boss_intro_closed", closed)
	events.connect(&"boss_hidden", hidden)


## The boss `actor` was shown: true when it shows at once (no intro), false when it waits.
func shown(actor: int, has_intro: bool) -> bool:
	if not has_intro:
		return true
	if actor != _open and not _waiting.has(actor):
		_waiting.append(actor)
	return false


## The intro of `actor` opened: it waits for the close, not for the frame's end.
func opened(actor: int) -> void:
	var at: int = _waiting.find(actor)
	if at >= 0:
		_waiting.remove_at(at)
	if _open != ActorsScript.NONE and _open != actor:
		# Another's intro took its place (a snapshot restored): that one played.
		var before: int = _open
		_open = actor
		released.emit(before, true)
		return
	_open = actor


## An intro closed (`boss_intro_closed`; ActorsScript.NONE: whatever is open): its boss is released,
## its intro played.
func closed(actor: int) -> void:
	if _open == ActorsScript.NONE:
		if actor != ActorsScript.NONE:
			var at: int = _waiting.find(actor)
			if at >= 0:
				_waiting.remove_at(at)
				released.emit(actor, true)
		return
	if actor != ActorsScript.NONE and actor != _open:
		return
	var was: int = _open
	_open = ActorsScript.NONE
	released.emit(was, true)


## The boss `actor` left play (`boss_hidden`): it waits no more, and nothing is released for it.
func hidden(actor: int) -> void:
	var at: int = _waiting.find(actor)
	if at >= 0:
		_waiting.remove_at(at)


## The end of a frame: every boss still waiting with no intro open for it is released, unplayed.
## While an intro is open the others wait on (a second boss with an intro in the room: the hold
## opens only the first's), and are released, unplayed, at the end of the frame it closed on.
## Allocates nothing when none waits.
func settle() -> void:
	if _open != ActorsScript.NONE:
		return
	while not _waiting.is_empty():
		var actor: int = _waiting[0]
		_waiting.remove_at(0)
		released.emit(actor, false)


## Forget everything (a run starts or ends), releasing nothing.
func clear() -> void:
	_waiting.clear()
	_open = ActorsScript.NONE


## True while `actor` waits (shown with an intro, not yet released).
func is_waiting(actor: int) -> bool:
	return _waiting.has(actor) or (_open == actor and actor != ActorsScript.NONE)


func _on_shown(actor: int, _boss_name: String, _lore: String, _marks: PackedFloat32Array, has_intro: bool) -> void:
	shown(actor, has_intro)


func _on_opened(actor: int, _boss_name: String, _lore: String, _intro: BossIntro, _page: int, _fresh: bool) -> void:
	opened(actor)

class_name NetHandshake
extends RefCounted
## How two machines come to hold a link (netcode spike S4, docs/milestones/netcode-spike.md): each
## hands the other one code, by the players' copy and paste, and then a `NetLink` is there. Host
## and Join (`NetPlay`) know only this; what the codes are and what carries the link is a
## handshake's own: WebRTC (`NetRtc`), or two ends in one process (the tests').
##
## - **The host** calls `offer`, waits for `code()` (its code, for the other player), then `take`s
##   the code that comes back.
## - **The joining machine** `take`s the host's code and waits for `code()`: its own, to send back.
## - Both call `poll` every physics step until `link()` is there (open) or `problem()` says why it
##   never will be. A handshake has no clock or thread of its own.
##
## A code given to `take` is untrusted text: a handshake checks it before using it and says why
## when it refuses one (the player may paste another).


## The host's start: its code is being made. "" when it began, else why it cannot.
func offer() -> String:
	return "this build cannot link two machines"


## The other machine's code. "" when it was taken, else why it was not. Nothing changes then,
## unless `problem()` says so after: the handshake itself failed on it.
func take(_code: String) -> String:
	return "this build cannot link two machines"


## This machine's code for the other player, "" while it is not made yet.
func code() -> String:
	return ""


## Move on: called every physics step by whoever holds it.
func poll() -> void:
	pass


## The link once the machines found each other (open), else null.
func link() -> NetLink:
	return null


## Why no link will come ("" while one still may, or is there).
func problem() -> String:
	return ""


## Give up: nothing more is made or looked for. A link already handed over is its holder's.
func close() -> void:
	pass

class_name NetWhy
extends RefCounted
## Why something of net/ did not work (online lobby L5b, docs/milestones/online-lobby.md): a name
## of `OnlineWhy` with its few facts, which is all that leaves net/ for the screen (the HUD words
## it), and `text`, which says the same for a log or a test and is never shown to a player.
##
## A handshake answers with one (`NetHandshake`: null when nothing is wrong), so whoever holds it
## passes the name on without reading a sentence, and another kind of handshake fails by the same
## names.

var name: StringName
## The name's facts (`OnlineWhy`): numbers, yes or no, names, a room's code as read. Never text
## off the wire.
var facts: Dictionary
## For the log and the tests only.
var text: String


func _init(why: StringName, in_words: String, with: Dictionary = {}) -> void:
	assert(OnlineWhy.ALL.has(why), "NetWhy: %s is no name of OnlineWhy" % why)
	name = why
	text = in_words
	facts = with


func _to_string() -> String:
	return text

class_name NetRelay
extends RefCounted
## A relay two machines may link through when they find no direct way (a TURN server): where it
## is, and the short-lived user name and password it takes. Plain data that crosses from whoever
## hands relays out (the room server today, `NetSignal`; a platform's own later) to whoever links
## (`NetRtc`): neither knows the other's form of it. No relay is `null`.

## Its addresses (`turn:name:port?transport=udp`, checked by whoever read them).
var urls: PackedStringArray = PackedStringArray()
var username: String = ""
var credential: String = ""


func _init(relay_urls: PackedStringArray = PackedStringArray(), relay_username: String = "", relay_credential: String = "") -> void:
	urls = relay_urls.duplicate()
	username = relay_username
	credential = relay_credential

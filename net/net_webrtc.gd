class_name NetWebRTC
extends RefCounted
## Whether this build can link two machines over WebRTC (netcode spike S3,
## docs/milestones/netcode-spike.md). A browser has WebRTC of its own. A desktop build has it
## through the WebRTC extension, which `ci/build/webrtc.sh` puts in every Linux and Windows build
## and in the test runs; a checkout that never ran the build script has none, and Host and Join
## (S4) say so instead of making a peer (the engine logs an error for a peer made without it).
##
## Nothing loads the extension from a script: the engine's `WebRTCPeerConnection` uses it where it
## is there. This only asks whether its peer class exists (registered, not yet proven to link:
## S4's two-peer test is that).

## The peer class the extension registers (godotengine/webrtc-native).
const EXTENSION_PEER: StringName = &"WebRTCLibPeerConnection"


static func available() -> bool:
	return OS.has_feature("web") or ClassDB.class_exists(EXTENSION_PEER)

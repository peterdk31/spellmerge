extends "res://tests/support/suite.gd"
## The WebRTC extension is in the test runs (netcode spike S3, docs/milestones/netcode-spike.md):
## `ci/build/build.sh` puts the pinned release in `addons/webrtc_native/` and sets
## SPELLMERGE_WEBRTC=required, and this fails if the engine did not load it. In a checkout that
## never ran the build script the test only says so, as the native module's tests do.


func test_the_test_runs_have_webrtc() -> void:
	if NetWebRTC.available():
		return
	if OS.get_environment("SPELLMERGE_WEBRTC") == "required":
		check(false, "SPELLMERGE_WEBRTC=required, but the WebRTC extension is not loaded (ci/build/webrtc.sh)")
	else:
		print("  no WebRTC extension in this checkout (ci/build/webrtc.sh): not checked")

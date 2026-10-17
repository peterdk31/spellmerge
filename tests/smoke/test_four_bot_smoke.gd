extends "res://tests/smoke/four_bot_smoke.gd"
## Runs the 4-bot smoke test under `ci/build/build.sh --quick --tests`, which only
## picks up `test_*.gd`. Nothing is added: the test is the parent script.
##
## godot --headless --path . --script res://tests/smoke/test_four_bot_smoke.gd

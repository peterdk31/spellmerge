extends "res://tests/support/suite.gd"
## The horde's gems take their look from data (gameplay/horde/gem_look.tres, S6 item 14 of
## docs/milestones/spell-spectacle-2.md): the glow's colours, the quad's size and the breathing.
##
## godot --headless --path . --script res://tests/gameplay/horde/test_gem_look.gd

const GemsScript := preload("res://gameplay/horde/horde_gems.gd")


func test_the_gems_are_drawn_in_their_look_s_colours_and_size() -> void:
	var look: GemLook = load("res://gameplay/horde/gem_look.tres") as GemLook
	check(look != null, "the gems' look is there")
	if look == null:
		return
	var gems: MultiMeshInstance2D = own(GemsScript.new()) as MultiMeshInstance2D
	var glow: Gradient = (gems.texture as GradientTexture2D).gradient
	check_equal(glow.colors[0], look.core_color, "a white-hot core")
	check_equal(glow.colors[1], look.glow_color, "in the look's glow")
	check_equal(glow.colors[3], look.edge_color, "out to its edge")
	check_equal((gems.multimesh.mesh as QuadMesh).size, Vector2(look.size, look.size), "as big as the look says")


func test_the_glow_breathes_by_the_look() -> void:
	var look: GemLook = load("res://gameplay/horde/gem_look.tres") as GemLook
	var gems: Node = own(GemsScript.new())
	var lowest: float = 1.0
	for i in 60:
		gems.call(&"step", 1.0 / 60.0, PackedVector2Array(), PackedByteArray(), 0.0)
		lowest = minf(lowest, (gems as CanvasItem).self_modulate.a)
	check(lowest < 1.0 and lowest >= 1.0 - look.pulse_depth - 0.001, "it dims by at most its pulse depth (%f)" % lowest)

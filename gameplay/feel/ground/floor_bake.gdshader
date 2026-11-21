shader_type canvas_item;
render_mode blend_premul_alpha;
// A room's floor baked into one texture (floor_bake.gd): the texture holds the layers' sum with its
// colour premultiplied by its alpha, so it is drawn premultiplied (`glow` false). The glow is added
// in the bake as it is added on screen (its colour times its alpha, `glow` true) and leaves the
// alpha alone: over a clear pixel (the void through a pit) it is only light, as on screen.

uniform bool glow = false;

// COLOR comes in as the texture's colour times the item's (Godot's canvas default).
void fragment() {
	if (glow) {
		COLOR = vec4(COLOR.rgb * COLOR.a, 0.0);
	}
}

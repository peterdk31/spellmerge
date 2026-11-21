shader_type canvas_item;
render_mode blend_premul_alpha;
// A room's floor baked into one texture (floor_bake.gd): the texture holds the layers' sum with its
// colour premultiplied by its alpha, so it is drawn premultiplied (`glow` false). The glow is added
// in the bake as it is added on screen (its colour times its alpha, `glow` true) and leaves the
// alpha alone: over a clear pixel (the void through a pit) it is only light, as on screen.

uniform bool glow = false;

// The item's own colour (its modulate), before the texture is applied.
varying vec4 item;

void vertex() {
	item = COLOR;
}

void fragment() {
	vec4 colour = texture(TEXTURE, UV) * item;
	if (glow) {
		// Added: its colour times its alpha, the alpha left alone.
		COLOR = vec4(colour.rgb * colour.a, 0.0);
	} else {
		// The baked texture is premultiplied already: a modulate's alpha (a fade) scales it all.
		COLOR = vec4(colour.rgb * item.a, colour.a);
	}
}

shader_type canvas_item;
// A reaction's flash: the sprite's shape in the plain colour it was tinted with (its modulate),
// keeping its transparency, so the colour is the reaction's own and not bent by the art.

varying vec3 tint;

// In vertex(), COLOR is the item's vertex colour with its modulate already applied.

void vertex() {
	tint = COLOR.rgb;
}

void fragment() {
	COLOR.rgb = tint;
}

shader_type canvas_item;
// A boss's portrait in its intro (docs/milestones/boss-intro.md, rule 6): the same art from
// silhouette to colour. `reveal` 0 draws every opaque pixel in `dark` (the silhouette), 1 in its own
// colours; `rim` (0 to 1) draws the art's outer edge, each opaque pixel with a clear neighbour, in
// `rim_color` (the accent, 1 px of the art); `flash` (0 to 1) whitens it all (the reveal's flash).
// Drawn by `hud/panels/boss/boss_intro.gd` at whole-number scale, its texture filtered by nearest.

uniform float reveal : hint_range(0.0, 1.0) = 0.0;
uniform float rim : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 dark : source_color = vec4(0.0784, 0.0706, 0.1216, 1.0);
// The frame drawn, left and right, in the sheet's UV: a neighbour past it is clear, never the next
// frame's pixel.
uniform vec2 frame_x = vec2(0.0, 1.0);

// 1 when `uv` is inside the frame and `alpha` (the sheet's there) is opaque.
float opaque_at(vec2 uv, float alpha) {
	float inside = step(frame_x.x, uv.x) * step(uv.x, frame_x.y) * step(0.0, uv.y) * step(uv.y, 1.0);
	return inside * step(0.5, alpha);
}

void fragment() {
	vec4 own = texture(TEXTURE, UV);
	float shown = step(0.5, own.a);
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec2 right = UV + vec2(px.x, 0.0);
	vec2 left = UV - vec2(px.x, 0.0);
	vec2 down = UV + vec2(0.0, px.y);
	vec2 up = UV - vec2(0.0, px.y);
	float inner = opaque_at(right, texture(TEXTURE, right).a)
		* opaque_at(left, texture(TEXTURE, left).a)
		* opaque_at(down, texture(TEXTURE, down).a)
		* opaque_at(up, texture(TEXTURE, up).a);
	float edge = shown * (1.0 - inner);
	vec3 colour = mix(dark.rgb, own.rgb, reveal);
	colour = mix(colour, rim_color.rgb, edge * rim);
	colour = mix(colour, vec3(1.0), flash);
	// COLOR comes in as the texture times the node's modulate: keep the modulate's alpha alone.
	COLOR = vec4(colour, shown * COLOR.a / max(own.a, 0.001));
}

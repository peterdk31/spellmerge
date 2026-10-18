shader_type canvas_item;
// A red glow at the screen edges. `strength` (0 to 1) is how red; `corner` (0 to 1
// on both axes) is the screen corner of the wizard who was hit, where it is strongest.

uniform float strength = 0.0;
uniform vec2 corner = vec2(0.5, 0.5);

void fragment() {
	vec2 centre = abs(UV - vec2(0.5)) * 2.0;
	float edge = smoothstep(0.3, 1.0, max(centre.x, centre.y * 1.3));
	float near = 1.0 - clamp(distance(UV, corner) / 1.2, 0.0, 1.0);
	COLOR = vec4(0.85, 0.1, 0.1, strength * edge * (0.45 + 0.55 * near));
}

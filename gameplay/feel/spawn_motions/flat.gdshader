shader_type canvas_item;
// A spawning body's light (spawn styles AS3, `materialize`): what is drawn in the draw's own colour,
// flat, keeping the art's transparency (its rows built out of light, its scan line).

varying vec4 flat_colour;

void vertex() {
	flat_colour = COLOR;
}

void fragment() {
	COLOR.rgb = flat_colour.rgb;
}

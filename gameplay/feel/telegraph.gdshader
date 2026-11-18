// SPDX-License-Identifier: GPL-3.0-or-later
// A telegraph lane (staffs F8b; a cue's `lane` part since cast timing T6b, gameplay/feel/lanes.gd):
// drawn on a Sprite2D whose region is the lane. Where the cast winding up goes, `beam_length` pixels along the aim and
// `telegraph_lane` pixels either side of the middle at the caster's end (`lanes.gd` keeps it to 14
// but for a body's pass, a dash's), widening evenly to
// `telegraph_lane_end` at the far end (a cone: a spray's; as wide as at the start for any other,
// `Carrier.lane_radius`). `telegraph_progress` runs 0 to 1 over the
// windup: the dashes march toward the tip, the arrowhead grows, the lane brightens, and the last
// part is white-hot.
//
// Its own small shader, not a mode of a shot shader: with a crowd winding up at once the
// shot shader's size made every telegraph pixel cost as much as a shot's, and the web build (and
// the stress run in the software renderer CI uses) went over its frame budget. The look is the
// shot shader's beam look: the ramp of a material (docs/STYLE.md: enemy telegraphs use Fire
// colours and are brighter than anything else on screen), hot = light halfway to white, glow =
// base toward light, additive glow with premultiplied alpha.
shader_type canvas_item;
render_mode blend_premul_alpha;

// The material's base and light shades (Fire for the imp).
uniform vec4 ramp_base : source_color = vec4(0.878, 0.349, 0.184, 1.0);
uniform vec4 ramp_light : source_color = vec4(1.0, 0.635, 0.235, 1.0);
uniform float beam_length = 0.0;
uniform float telegraph_progress = 0.0;
uniform float telegraph_lane = 6.0;
// Pixels either side of the middle at the far end (below `telegraph_lane`: as wide as it).
uniform float telegraph_lane_end = 0.0;
// 1 to 0 over a beat as the caster's aim locks (boss plan OB14, `lanes.gd`): the lane flashes hot.
uniform float telegraph_beat = 0.0;

// The widest a lane is drawn either side (pixels; `lanes.gd` makes its sprite tall enough).
const float LANE_MOST = 72.0;

float falloff(float x, float reach) {
	float k = max(1.0 - x / reach, 0.0);
	return k * k;
}

void fragment() {
	vec3 mid = ramp_base.rgb;
	vec3 hi = ramp_light.rgb;
	vec3 hot = mix(hi, vec3(1.0), 0.5);
	vec3 glow = mix(mid, hi, 0.35);
	float len = max(beam_length, 1.0);
	float at = floor(UV.x / TEXTURE_PIXEL_SIZE.x);
	float y = floor(UV.y / TEXTURE_PIXEL_SIZE.y - 0.5 / TEXTURE_PIXEL_SIZE.y);
	float p = clamp(telegraph_progress, 0.0, 1.0);
	bool last = p >= 0.8;
	float near = clamp(telegraph_lane, 1.0, LANE_MOST);
	float far = clamp(max(telegraph_lane_end, near), near, LANE_MOST);
	float lane = round(mix(near, far, clamp(at / len, 0.0, 1.0)));
	float beat = clamp(telegraph_beat, 0.0, 1.0);
	// The arrowhead at the far end, growing as the cast nears.
	float head = round(mix(3.0, 7.0, p));
	float back = len - at;
	float side = abs(y + 0.5);
	if (back >= 0.0 && back <= head && side <= back * 0.9 + 0.5) {
		COLOR = vec4(last || back < 1.5 ? hot : hi, 1.0);
	} else if (at < 0.0 || at > len) {
		COLOR = vec4(0.0);
	} else if ((y == 0.0 || y == -1.0) && mod(at - floor(p * 24.0), 8.0) < 4.0 && back > head) {
		// Dashes down the middle, marching toward the tip as the windup runs.
		COLOR = vec4(last ? hot : hi, 1.0);
	} else if (side == lane + 0.5 && mod(at, 3.0) < 1.0) {
		// The lane's edges, dotted, so the hit width reads.
		COLOR = vec4(beat > 0.0 ? hot : mid, 1.0);
	} else {
		float inside = side <= lane + 0.5 ? 1.0 : falloff(side - lane, 3.0);
		float lit = inside * (0.14 + 0.3 * p + 0.5 * beat) + 0.4 * p * falloff(side, 2.0);
		COLOR = vec4(glow * lit, 0.0);
	}
}

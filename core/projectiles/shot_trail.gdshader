// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
// world_vertex_coords: VERTEX is in world space in vertex(), so each quad is placed in the world
// and every pixel can be found on the world's pixel grid (nothing else moves its vertices).
render_mode blend_premul_alpha, world_vertex_coords;

// A shot in flight and its trail (the projectile manager's trail batches; core/README.md, "The
// shot shaders"; the owner, 2026-10-28: "the tail of projectiles turn with the projectile"): a
// shot leaves its tail and its card particles in the world, where it was, as the mockup does.
// The projectile manager keeps each shot's path in `trail_data`, one row per trail of
// TRAIL_SAMPLES texels (x, y, odometer, time), a ring written 30 times a second and at every
// bounce and end. Each pixel of travel (a very fast shot's every 2-4, `gap`) leaves one tail pixel there, which drifts a little and
// cools through the ramp in its own time (0.1-0.3 s), so the tail bends with any path and frays
// at its end by itself; each 60th of a second may give off a particle of one of the shot's kinds
// from where the shot was then, which moves on its own from there (embers rise, flecks hang,
// gusts blow back and curl, sparks jump, void pulls in to the shot). The pixel's or particle's
// number is its place on the path (the odometer) or its moment, so it stays the same pixel from
// frame to frame. A trail outlives its shot by its longest life, so a tail cools where it ended.
// Everything is drawn on the world's pixel grid, axis-aligned: the core is a `+` whatever way
// the shot flies, and a line is one pixel per step, as the mockup draws it.
//
// PARTICLES ARE GEOMETRY (the owner, 2026-10-29). Windows browsers compile WebGL through
// Direct3D, and the big, branchy fragment stage this shader had (every pixel walking its piece's
// tail pixels and births, a branch per look kind) took the compiler about 90 s on a real GPU,
// until the browser killed its GPU process. So the VERTEX stage does the work and the fragment
// stage only colours a pixel of its own quad: a few small modes, no loops, no kinds.
// A trail is one instance of a mesh (`trail_mesh` in projectile_manager.gd) of small quads, each
// told in its UV which QUAD KIND (Q_*) and which slot it is. The vertex shader works out, from
// `trail_data`, what that slot is now and puts its quad round it alone, or folds it away:
//   Q_HEAD_LIGHT  the core's light (and void's dark heart);
//   Q_PIECE_LIGHT a piece of the path between two samples, the tail's light round it (a dash:
//                 the light of a speed streak instead);
//   Q_SPARK_LIGHT the light of the particle born at moment `slot` back from now;
//   Q_SPARK       that particle's pixel (a one-pixel line for a streak, a small star or cross);
//   Q_TAIL        tail pixel `slot` back from the head along the path (a dash: a speed streak);
//   Q_JAG         a 4-pixel step of the jagged line lightning draws behind its shot;
//   Q_CORE        the core: a white-hot `+`, pierce's run, void's dark heart.
// The mesh draws the lights first (added; the head's first, as its dark heart dims what is
// under it), then the pixels, oldest first and the core last, so the newest is on top.
// The particle kinds are DATA, not code: one row each in the tables below (LOOK TABLE), read by
// one routine (`spark`), so a new kind is a new row.
// The instance carries its data in its transform (the batch must sit untransformed at the
// origin): origin the head (where the shot is drawn this frame), x axis (row, newest sample's
// number), y axis (samples kept, TF_* flags). The colour and the custom data are the look
// (`shot_look.gdshaderinc`; worked out per vertex here, `look_from_color`).

#include "res://core/projectiles/shot_palette.gdshaderinc"
#include "res://core/projectiles/shot_look.gdshaderinc"

// The spark pool's share (set by the projectile manager, 1.0 is everything): the fraction of
// every shot's particles and of every tail that is drawn this frame. Tails go first.
uniform float particle_share = 1.0;
uniform float trail_share = 1.0;
// The paths, and the moment the heads are drawn at (the simulation clock less what the drawing
// lags behind the last step), in the samples' clock.
uniform sampler2D trail_data : filter_nearest;
uniform float trail_now = 0.0;

// Samples a row holds (TRAIL_SAMPLES in projectile_manager.gd), the steps of a search through
// them (2^5 = 32), the moments a particle may be born a second, and the flags (TRAIL_* there):
// the shot is alive (its core is drawn and its path runs on to the head), an orbit shot (a
// shorter tail), a wizard's dash (speed streaks in the player's colours and the dash's cards, no
// tail, no core).
const int TRAIL_SAMPLES = 32;
const int SEARCH_STEPS = 5;
const float BIRTHS = 60.0;
const float TF_HEAD = 1.0;
const float TF_ORBIT = 2.0;
const float TF_DASH = 4.0;
// The longest anything of a trail lives (TRAIL_KEEP; no particle row lives longer).
const float TRAIL_LONGEST = 1.0;
// The tail pixels a trail has (TRAIL_TAIL_PIXELS), and the most pixels of path one of them
// stands for: a shot too fast to leave one every pixel for its tail's life leaves one every
// `gap` (up to TAIL_GAP_MAX), so its tail reaches as far, sparser (an atom's long streak).
const float TAIL_PIXELS = 128.0;
const float TAIL_GAP_MAX = 4.0;
// The quad kinds (TRAIL_Q_* in projectile_manager.gd), in UV.y.
const float Q_HEAD_LIGHT = 0.0;
const float Q_PIECE_LIGHT = 1.0;
const float Q_SPARK_LIGHT = 2.0;
const float Q_SPARK = 3.0;
const float Q_TAIL = 4.0;
const float Q_JAG = 5.0;
const float Q_CORE = 6.0;
// The fragment's modes: a round light, the tail's light round a piece, pixels (a square, a
// cross, a line beside it), a one-pixel line.
const float M_GLOW = 0.0;
const float M_TAIL_GLOW = 1.0;
const float M_PIXELS = 2.0;
const float M_LINE = 3.0;
// A neighbour or a line that is not there.
const vec2 FAR = vec2(1.0e7);

// ---- LOOK TABLE: one row per particle kind ----
// The rows are:
//   0       a plain shot's twinkle
//   1-12    the look kinds by number (L_*; 11, the weave, gives off nothing)
//   13-15   a dash's own: its speed streaks, and fire and frost from its feet
//   16, 17  the kinds L_HOPS (chain) and L_WAKE (faster), moved up past the dash's rows
//   18-24   the kinds 15-21 the same way (kind + 3): weight, ripple, curl, zig, double, converge, drift
// A particle `j` born at moment `id` where the shot was (`at`, flying along `dir`, `side` its
// left) with its numbers h(n) in [0, 1) (`th`) and `ago` seconds old, `u` of its life:
//   life                   LIFE_BACK.x + LIFE_BACK.y h
//   start  at (or the shot, CIRCLE.w 1) + dir (LIFE_BACK.z + LIFE_BACK.w h)
//          + (h - 0.5, h - 0.5) JITTER.xy + the same re-rolled every frame x JITTER.z
//          + side (h - 0.5) JITTER.w
//   thrown v = -dir (VELOCITY.x + VELOCITY.y h) + side (h - 0.5) VELOCITY.z
//          + ((h - 0.5) VELOCITY.w, -(UP_DRAG.x + UP_DRAG.y h)), slowed by UP_DRAG.z each 60th
//          of a second (1 none), and turning at (h - 0.5) UP_DRAG.w radians a second
//   floats (h - 0.5, h - 0.5) CIRCLE.z ago, and up (CIRCLE.x + CIRCLE.y h) ago
//   circles at (RADIUS.x + RADIUS.y h + RADIUS.z u) (x zoom if SPIN.x) (1 - u)^RADIUS.w, at the
//          angle h 2 pi + SPIN.y ago + SPIN.z u (1.2 + h) either way
//   drawn  a pixel, or with SPIN.w a one-pixel line back to - v TIP.x - dir TIP.y (2 + zoom);
//          a small cross round it in ARM.z while u is in ARM.x-ARM.y (for a share SHOW.w)
//   shown  when (frame + id BLINK.x + j BLINK.y + BLINK.z) mod BLINK.w >= SHOW.x, its number
//          re-rolled every frame >= SHOW.y, and u > SHOW.z
//   colour COLOURS[u x ARM.w steps] (SHADES 0-17, 18 the shot's light, 19 and 20 the player's
//          light and base)
//   light  TIP.z (1 - 0.75 u) (SHINE.x falloff(r, SHINE.y) + SHINE.z falloff(r, SHINE.w))
//   given off by TIP.w of the moments (one of the shot's kinds picked at random; a dash twice
//          as often, its feet always).
const int ROW_TWINKLE = 0;
const int ROW_DASH_STREAK = 13;
const int ROW_DASH_EMBER = 14;
const int ROW_DASH_FLECK = 15;
const int ROW_HOPS = 16;
const int ROW_WAKE = 17;
const int ROWS = 25;
//                                  twinkle                embers                    flecks                    gusts                    pull                      sparks                    motes                    glints                    streaks              burst                orbiters             weave                glitter              dash streak            dash ember             dash fleck             hops                   wake
const vec4 LIFE_BACK[ROWS] = vec4[](vec4(0.3, 0.3, 0.0, -8.0), vec4(0.3, 0.35, 0.0, -4.0), vec4(0.5, 0.4, 0.0, -14.0), vec4(0.1, 0.12, 0.0, 0.0), vec4(0.22, 0.18, 0.0, 0.0), vec4(0.05, 0.1, 0.0, -10.0), vec4(0.5, 0.3, 0.0, 0.0), vec4(0.6, 0.0, 0.0, -6.0), vec4(0.25, 0.0, 0.0, 0.0), vec4(0.5, 0.0, 0.0, 0.0), vec4(0.8, 0.0, 0.0, 0.0), vec4(0.0), vec4(0.5, 0.0, 0.0, 0.0), vec4(0.1, 0.08, -4.0, 8.0), vec4(0.45, 0.4, 0.0, 0.0), vec4(0.6, 0.4, 0.0, 0.0), vec4(0.3, 0.2, 0.0, -4.0), vec4(0.2, 0.15, 0.0, -2.0), vec4(0.45, 0.3, 0.0, -2.0), vec4(0.5, 0.1, 0.0, -4.0), vec4(0.35, 0.2, 0.0, -2.0), vec4(0.22, 0.1, 0.0, -2.0), vec4(0.4, 0.1, 0.0, -4.0), vec4(0.3, 0.1, 10.0, 4.0), vec4(0.7, 0.2, 0.0, -3.0));
const vec4 JITTER[ROWS] = vec4[](vec4(4.0, 4.0, 0.0, 0.0), vec4(0.0, 2.0, 0.0, 0.0), vec4(3.0, 3.0, 0.0, 0.0), vec4(0.0, 0.0, 0.0, 7.0), vec4(0.0), vec4(0.0, 0.0, 6.0, 0.0), vec4(4.0, 4.0, 0.0, 0.0), vec4(4.0, 4.0, 0.0, 0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0, 0.0, 0.0, 13.0), vec4(0.0), vec4(0.0), vec4(0.0, 0.0, 0.0, 6.0), vec4(0.0, 0.0, 0.0, 5.0), vec4(0.0, 0.0, 0.0, 6.0), vec4(0.0), vec4(0.0, 0.0, 0.0, 3.0), vec4(0.0), vec4(0.0, 0.0, 0.0, 4.0), vec4(0.0, 0.0, 0.0, 6.0), vec4(0.0, 0.0, 0.0, 2.0));
const vec4 VELOCITY[ROWS] = vec4[](vec4(0.0), vec4(14.0, 0.0, 0.0, 14.0), vec4(0.0), vec4(80.0, 70.0, 40.0, 0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(60.0, 50.0, 0.0, 0.0), vec4(0.0), vec4(0.0), vec4(0.0, 0.0, 110.0, 0.0), vec4(110.0, 60.0, 20.0, 0.0), vec4(0.0), vec4(0.0), vec4(22.0, 20.0, 0.0, 0.0), vec4(20.0, 10.0, 80.0, 0.0), vec4(8.0, 0.0, 44.0, 0.0), vec4(45.0, 10.0, 0.0, 0.0), vec4(-8.0, 0.0, 0.0, 0.0));
const vec4 UP_DRAG[ROWS] = vec4[](vec4(0.0, 0.0, 1.0, 0.0), vec4(10.0, 24.0, 0.97, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 1.0, 9.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.94, 0.0), vec4(-16.0, -14.0, 1.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 1.0, 11.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0));
const vec4 CIRCLE[ROWS] = vec4[](vec4(6.0, 0.0, 0.0, 0.0), vec4(0.0), vec4(0.0, 0.0, 4.0, 0.0), vec4(0.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(0.0), vec4(14.0, 0.0, 0.0, 0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(0.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(0.0), vec4(4.0, 8.0, 0.0, 0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(0.0));
const vec4 RADIUS[ROWS] = vec4[](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(6.0, 6.0, 0.0, 1.4), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(2.0, 0.0, 6.0, 0.0), vec4(4.5, 0.0, 0.0, 0.0), vec4(0.0), vec4(2.5, 1.5, 0.0, 0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(1.0, 0.0, 9.0, 0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0));
const vec4 SPIN[ROWS] = vec4[](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(1.0, 0.0, 0.0, 0.0), vec4(1.0, 5.0, 0.0, 0.0), vec4(0.0), vec4(1.0, 0.0, 0.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(0.0), vec4(0.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(1.0, 0.0, 0.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(0.0), vec4(0.0));
const vec4 TIP[ROWS] = vec4[](vec4(0.0, 0.0, 0.7, 0.18), vec4(0.0, 0.0, 1.0, 0.45), vec4(0.0, 0.0, 0.9, 0.32), vec4(0.025, 0.0, 0.8, 0.4), vec4(0.0, 0.0, 0.7, 0.55), vec4(0.0, 0.0, 1.2, 0.45), vec4(0.0, 0.0, 0.7, 0.25), vec4(0.0, 0.0, 0.8, 0.25), vec4(0.0, 1.0, 0.6, 0.25), vec4(0.0, 0.0, 0.8, 0.25), vec4(0.0, 0.0, 0.6, 0.25), vec4(0.0), vec4(0.0, 0.0, 0.6, 0.25), vec4(0.025, 0.0, 0.4, 1.0), vec4(0.0, 0.0, 1.0, 1.0), vec4(0.0, 0.0, 0.8, 1.0), vec4(0.14, 0.0, 0.9, 1.0), vec4(0.04, 0.0, 0.9, 0.7), vec4(0.12, 0.0, 0.5, 0.4), vec4(0.0, 0.0, 0.9, 1.0), vec4(0.07, 0.0, 0.9, 1.0), vec4(0.06, 0.0, 0.8, 0.5), vec4(0.0, 1.0, 0.5, 0.5), vec4(0.0, 0.0, 0.9, 1.0), vec4(0.0, 0.0, 0.5, 0.4));
const vec4 SHINE[ROWS] = vec4[](vec4(0.16, 2.5, 0.07, 7.0), vec4(0.16, 2.5, 0.07, 7.0), vec4(0.16, 2.5, 0.07, 7.0), vec4(0.16, 2.5, 0.07, 7.0), vec4(0.16, 2.5, 0.07, 7.0), vec4(0.16, 2.5, 0.07, 7.0), vec4(0.16, 2.5, 0.07, 7.0), vec4(0.16, 2.5, 0.07, 7.0), vec4(0.16, 2.5, 0.07, 7.0), vec4(0.16, 2.5, 0.07, 7.0), vec4(0.16, 2.5, 0.07, 7.0), vec4(0.16, 2.5, 0.07, 7.0), vec4(0.16, 2.5, 0.07, 7.0), vec4(0.16, 3.0, 0.0, 1.0), vec4(0.16, 2.5, 0.07, 7.0), vec4(0.16, 2.5, 0.07, 7.0), vec4(0.16, 2.5, 0.07, 7.0), vec4(0.16, 2.5, 0.07, 7.0), vec4(0.16, 2.5, 0.07, 7.0), vec4(0.16, 2.5, 0.07, 7.0), vec4(0.16, 2.5, 0.07, 7.0), vec4(0.16, 2.5, 0.07, 7.0), vec4(0.16, 2.5, 0.07, 7.0), vec4(0.16, 2.5, 0.07, 7.0), vec4(0.16, 2.5, 0.07, 7.0));
const vec4 BLINK[ROWS] = vec4[](vec4(3.0, 1.0, 0.0, 7.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(3.0, 1.0, 0.0, 7.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(1.0, 0.0, 3.0, 6.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(3.0, 1.0, 0.0, 7.0), vec4(0.0, 0.0, 0.0, 2.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(3.0, 1.0, 0.0, 5.0), vec4(0.0, 0.0, 0.0, 1.0), vec4(0.0, 0.0, 0.0, 3.0));
const vec4 SHOW[ROWS] = vec4[](vec4(2.0, 0.0, -1.0, 0.0), vec4(0.0, 0.22, -1.0, 0.0), vec4(2.0, 0.0, -1.0, 0.3), vec4(0.0, 0.0, -1.0, 0.0), vec4(0.0, 0.0, -1.0, 0.0), vec4(0.0, 0.0, -1.0, 0.0), vec4(0.0, 0.0, -1.0, 0.0), vec4(0.0, 0.0, 0.2, 1.0), vec4(0.0, 0.0, -1.0, 0.0), vec4(0.0, 0.0, -1.0, 0.0), vec4(0.0, 0.0, -1.0, 0.0), vec4(0.0, 0.0, -1.0, 0.0), vec4(3.0, 0.0, -1.0, 0.0), vec4(0.0, 0.0, -1.0, 0.0), vec4(0.0, 0.3, -1.0, 0.0), vec4(2.0, 0.0, -1.0, 0.0), vec4(0.0, 0.0, -1.0, 0.0), vec4(0.0, 0.0, -1.0, 0.0), vec4(0.0, 0.0, -1.0, 0.0), vec4(0.0, 0.0, -1.0, 0.0), vec4(0.0, 0.0, -1.0, 0.0), vec4(0.0, 0.0, -1.0, 0.0), vec4(1.0, 0.0, -1.0, 0.0), vec4(0.0, 0.0, -1.0, 0.0), vec4(1.0, 0.0, -1.0, 0.0));
const vec4 ARM[ROWS] = vec4[](vec4(2.0, 0.0, 0.0, 3.0), vec4(2.0, 0.0, 0.0, 4.0), vec4(0.0, 0.2, 8.0, 4.0), vec4(2.0, 0.0, 0.0, 3.0), vec4(2.0, 0.0, 0.0, 4.0), vec4(2.0, 0.0, 0.0, 3.0), vec4(2.0, 0.0, 0.0, 2.0), vec4(0.35, 0.6, 17.0, 1.0), vec4(2.0, 0.0, 0.0, 1.0), vec4(2.0, 0.0, 0.0, 2.0), vec4(2.0, 0.0, 0.0, 1.0), vec4(2.0, 0.0, 0.0, 1.0), vec4(2.0, 0.0, 0.0, 1.0), vec4(2.0, 0.0, 0.0, 2.0), vec4(2.0, 0.0, 0.0, 4.0), vec4(2.0, 0.0, 0.0, 4.0), vec4(2.0, 0.0, 0.0, 2.0), vec4(2.0, 0.0, 0.0, 3.0), vec4(2.0, 0.0, 0.0, 3.0), vec4(2.0, 0.0, 0.0, 3.0), vec4(2.0, 0.0, 0.0, 3.0), vec4(2.0, 0.0, 0.0, 3.0), vec4(2.0, 0.0, 0.0, 3.0), vec4(2.0, 0.0, 0.0, 3.0), vec4(2.0, 0.0, 0.0, 3.0));
const vec4 COLOURS[ROWS] = vec4[](vec4(17.0, 18.0, 18.0, 18.0), vec4(5.0, 2.0, 1.0, 0.0), vec4(17.0, 8.0, 8.0, 7.0), vec4(5.0, 4.0, 3.0, 3.0), vec4(9.0, 10.0, 11.0, 11.0), vec4(17.0, 14.0, 13.0, 13.0), vec4(14.0, 13.0, 13.0, 13.0), vec4(17.0), vec4(17.0), vec4(2.0, 1.0, 1.0, 1.0), vec4(17.0), vec4(17.0), vec4(5.0), vec4(19.0, 20.0, 20.0, 20.0), vec4(5.0, 2.0, 1.0, 0.0), vec4(17.0, 8.0, 8.0, 7.0), vec4(18.0, 17.0, 4.0, 4.0), vec4(18.0, 17.0, 16.0, 15.0), vec4(16.0, 15.0, 15.0, 15.0), vec4(17.0, 16.0, 15.0, 15.0), vec4(18.0, 17.0, 16.0, 16.0), vec4(17.0, 5.0, 4.0, 4.0), vec4(16.0, 16.0, 15.0, 15.0), vec4(17.0, 5.0, 4.0, 4.0), vec4(4.0, 3.0, 3.0, 3.0));

// How long a trail with each kind draws its particles (seconds; x a shot, y a dash): the trail's
// window is the longest of its kinds' and its tail's (a dash's at least 0.18 s; a plain shot's,
// with no kind among 1-9, its twinkles' 0.6 s), so a kind that lives longer than its trail's
// window (void's pull, a shield's sparks) is cut there, as the mockup's trails are.
const vec2 WINDOW[22] = vec2[](vec2(0.6, 0.0), vec2(0.65, 0.85), vec2(0.9, 1.0), vec2(0.22), vec2(0.0), vec2(0.15), vec2(0.8), vec2(0.6), vec2(0.25), vec2(0.5), vec2(0.0), vec2(0.0), vec2(0.0), vec2(0.5), vec2(0.35), vec2(0.7), vec2(0.6), vec2(0.5), vec2(0.3), vec2(0.5), vec2(0.4), vec2(0.9));

// What the vertex stage hands a pixel (by mode; see `fragment`): the pixel's world position, the
// mode, three numbers and three colours.
varying vec2 world;
varying flat float mode;
varying flat vec4 v0;
varying flat vec4 v1;
varying flat vec4 v2;
varying flat vec4 c0;
varying flat vec4 c1;
varying flat vec4 c2;

// ---- Vertices ----

// Sample `k` back from the newest (0) of trail `row`: x, y, odometer, time.
vec4 trail_texel(float row, float newest, float k) {
	float n = newest - k;
	return texelFetch(trail_data, ivec2(int(mod(n, float(TRAIL_SAMPLES))), int(row)), 0);
}

// For each of `v`'s two numbers, the newest sample from `first` back to `last` whose time
// (`by_time`) or odometer is at most it, the older end of the piece it is on: its k, or -1 when
// even the oldest is later. Both are searched at once, and the vertex stage searches the path in
// one place only (`vertex`): the compiler builds a loop once for every place it is called from,
// and the Direct3D one takes its time over each.
vec2 samples_before(float row, float newest, float first, float last, vec2 v, bool by_time) {
	vec2 lo_k = vec2(first);
	vec2 hi_k = vec2(last);
	for (int i = 0; i < SEARCH_STEPS; i++) {
		vec2 half_k = floor((lo_k + hi_k) * 0.5);
		vec4 s0 = trail_texel(row, newest, half_k.x);
		vec4 s1 = trail_texel(row, newest, half_k.y);
		vec2 earlier = vec2(lessThanEqual(by_time ? vec2(s0.w, s1.w) : vec2(s0.z, s1.z), v));
		hi_k = mix(hi_k, half_k, earlier);
		lo_k = mix(half_k + 1.0, lo_k, earlier);
	}
	vec4 s0 = trail_texel(row, newest, lo_k.x);
	vec4 s1 = trail_texel(row, newest, lo_k.y);
	vec2 earlier = vec2(lessThanEqual(by_time ? vec2(s0.w, s1.w) : vec2(s0.z, s1.z), v));
	vec2 inside = vec2(lessThanEqual(lo_k, vec2(last))) * (first <= last ? 1.0 : 0.0);
	return mix(vec2(-1.0), lo_k, earlier * inside);
}

// A number in [0, 1) from three whole numbers and the trail's row: an integer hash, so a pixel's
// number (its place on the path, its moment) keeps its looks however large it grows.
uint mix_bits(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

float th(float a, float b, float c, float row) {
	uint h = mix_bits(uint(int(a)) ^ mix_bits(uint(int(b)) + mix_bits(uint(int(c)) + uint(int(row)) * 7919u + 40503u)));
	return float(h & 16777215u) / 16777216.0;
}

// How far a pixel thrown at 1 px/s has gone after `ago` seconds, slowed by `drag` each 60th of a
// second (the mockup's particles).
float dragged(float ago, float drag) {
	float f = ago * 60.0;
	return drag * (1.0 - pow(drag, f)) / (1.0 - drag) / 60.0;
}

// Component `i` (0-3) of `v`.
float pick4(vec4 v, float i) {
	return i < 0.5 ? v.x : (i < 1.5 ? v.y : (i < 2.5 ? v.z : v.w));
}

// Colour `i` of a table row: SHADES 0-17, 18 the shot's light, 19 and 20 its player's.
vec3 tone(float i, Look L) {
	int k = int(i + 0.5);
	int pi = int(L.player);
	return k < 18 ? SHADES[k] : (k == 18 ? L.hi : (k == 19 ? P_LIGHT[pi] : P_BASE[pi]));
}

// The trail's window (WINDOW): how far back from now its particles are drawn.
float trail_window(vec3 b, bool dash, float tail) {
	float longest = dash ? max(tail, 0.18) : tail;
	bool any = false;
	for (int k = 1; k <= 21; k++) {
		if (bit_set(b, float(k))) {
			longest = max(longest, dash ? WINDOW[k].y : WINDOW[k].x);
			any = any || k <= 9;
		}
	}
	if (!any && !dash) {
		longest = max(longest, WINDOW[0].x);
	}
	return min(longest, TRAIL_LONGEST);
}

// The kind given off by particle `j` born at moment `id`, or -2 for none: one of the shot's
// kinds, picked at random, each at its own rate (TIP.w); a plain shot's twinkle is -1. A dash
// gives off two speed streaks (kind 0) and its cards at twice a shot's rate, fire and frost
// always.
int kind_row(float kind) {
	return int(kind + (kind > 12.5 ? 3.5 : 0.5));
}

float trail_kind(float id, float j, bool dash, vec4 kinds, float row) {
	if (dash && j < 1.5) {
		return 0.0;
	}
	if (kinds.w < 0.5) {
		return !dash && j < 0.5 && th(id, j, 151.0, row) < TIP[ROW_TWINKLE].w * particle_share ? -1.0 : -2.0;
	}
	float i = min(floor(th(id, j, 152.0, row) * kinds.w), kinds.w - 1.0);
	float word = i < 4.0 ? kinds.x : (i < 8.0 ? kinds.y : kinds.z);
	float look = mod(floor(word / exp2(mod(i, 4.0) * 5.0) + 0.001), 32.0);
	float rate = TIP[kind_row(look)].w;
	if (dash) {
		rate = look == L_EMBERS || look == L_FLECKS ? 1.0 : min(rate * 2.0, 1.0);
	}
	return th(id, j, 153.0, row) < rate * particle_share ? look : -2.0;
}

// The particle `j` born at moment `id`, as it is now: where (`pos`, and `tip` for a line), its
// colours (alpha 0 for hidden) and its light.
struct Spark {
	bool alive;
	vec2 pos;
	vec2 tip;
	bool line;
	vec4 rgb;
	vec4 arm;
	float glow;
	vec4 light;
};

// One routine for every kind, driven by its row of the LOOK TABLE. `t_top` is when the path
// ends (now for a live shot), `head_end` its newest end, `window` the trail's (WINDOW), `target`
// where the shot is (or was last: void pulls in to it, shields circle it), `k` the sample before
// its moment (`samples_before`, by time).
Spark spark(float row, float newest, float count, float skip, vec4 head_end, float t_top, float window, vec2 target, bool dash, float id, float j, float k, Look L) {
	Spark S;
	S.alive = false;
	S.pos = vec2(0.0);
	S.tip = vec2(0.0);
	S.line = false;
	S.rgb = vec4(0.0);
	S.arm = vec4(0.0);
	S.glow = 0.0;
	S.light = vec4(0.0);
	float t = id / BIRTHS;
	float ago = trail_now - t;
	if (ago < 0.0 || ago > window || t >= t_top) {
		return S;
	}
	float kind = trail_kind(id, j, dash, L.emits, row);
	if (kind < -1.5) {
		return S;
	}
	// The piece it was born on, and where on it.
	if (k < 0.0) {
		return S;
	}
	vec4 A = trail_texel(row, newest, k);
	vec4 B = k < skip + 0.5 ? head_end : trail_texel(row, newest, k - 1.0);
	vec2 ab = B.xy - A.xy;
	float len = length(ab);
	vec2 dir = len > 0.001 ? ab / len : vec2(1.0, 0.0);
	vec2 side = vec2(-dir.y, dir.x);
	vec2 at = mix(A.xy, B.xy, clamp((t - A.w) / max(B.w - A.w, 0.0001), 0.0, 1.0));
	// Its row: a shot's kinds circle the shot; a dash's circle where they were born, from beside
	// its body, and its fire and frost fall from its feet.
	int r = kind < 0.0 ? ROW_TWINKLE : kind_row(kind);
	vec2 base = at;
	vec2 centre = target;
	if (dash) {
		centre = at;
		if (kind < 0.5) {
			r = ROW_DASH_STREAK;
		} else if (kind == L_EMBERS || kind == L_FLECKS) {
			r = kind == L_EMBERS ? ROW_DASH_EMBER : ROW_DASH_FLECK;
			base = at + vec2(0.0, r == ROW_DASH_FLECK ? 7.0 : 8.0) + (vec2(th(id, j, 135.0, row), th(id, j, 136.0, row)) - 0.5) * vec2(8.0, 2.0);
		} else {
			base = at + side * (th(id, j, 141.0, row) - 0.5) * 10.0;
		}
	}
	float hs = 200.0 + 20.0 * float(r);
	vec4 lb = LIFE_BACK[r];
	float life = lb.x + lb.y * th(id, j, hs, row);
	if (ago >= life) {
		return S;
	}
	float u = ago / life;
	float z = L.zoom;
	float frame = floor(trail_now * 60.0);
	vec4 jit = JITTER[r];
	vec4 vel = VELOCITY[r];
	vec4 ud = UP_DRAG[r];
	vec4 ci = CIRCLE[r];
	vec4 ra = RADIUS[r];
	vec4 sp = SPIN[r];
	vec4 tp = TIP[r];
	vec2 pos = mix(base, centre, ci.w) + dir * (lb.z + lb.w * th(id, j, hs + 1.0, row));
	pos += (vec2(th(id, j, hs + 2.0, row), th(id, j, hs + 3.0, row)) - 0.5) * jit.xy;
	pos += (vec2(th(id, frame, hs + 4.0, row), th(id, frame, hs + 5.0, row)) - 0.5) * jit.z;
	pos += side * (th(id, j, hs + 6.0, row) - 0.5) * jit.w;
	vec2 v = -dir * (vel.x + vel.y * th(id, j, hs + 7.0, row)) + side * (th(id, j, hs + 8.0, row) - 0.5) * vel.z;
	v += vec2((th(id, j, hs + 9.0, row) - 0.5) * vel.w, -(ud.x + ud.y * th(id, j, hs + 10.0, row)));
	float curl = (th(id, j, hs + 11.0, row) - 0.5) * ud.w;
	float turn = curl * ago;
	vec2 v_now = vec2(v.x * cos(turn) - v.y * sin(turn), v.x * sin(turn) + v.y * cos(turn));
	if (abs(curl) < 0.01) {
		pos += v * (ud.z < 0.999 ? dragged(ago, ud.z) : ago);
	} else {
		pos += vec2(v.x * sin(turn) - v.y * (1.0 - cos(turn)), v.x * (1.0 - cos(turn)) + v.y * sin(turn)) / curl;
	}
	pos += (vec2(th(id, j, hs + 12.0, row), th(id, j, hs + 13.0, row)) - 0.5) * ci.z * ago;
	pos.y -= (ci.x + ci.y * th(id, j, hs + 14.0, row)) * ago;
	float ang = th(id, j, hs + 15.0, row) * 6.2832 + sp.y * ago + sp.z * u * (th(id, j, hs + 16.0, row) < 0.5 ? -1.0 : 1.0) * (1.2 + th(id, j, hs + 17.0, row));
	float radius = (ra.x + ra.y * th(id, j, hs + 18.0, row) + ra.z * u) * (sp.x > 0.5 ? z : 1.0) * pow(max(1.0 - u, 0.0001), ra.w);
	pos += vec2(cos(ang), sin(ang)) * radius;
	vec4 bl = BLINK[r];
	vec4 sh = SHOW[r];
	vec4 arm = ARM[r];
	bool shown = mod(frame + id * bl.x + j * bl.y + bl.z, bl.w) >= sh.x && th(id, frame, hs + 19.0, row) >= sh.y && u > sh.z;
	float steps = arm.w;
	S.alive = true;
	S.pos = pos;
	S.line = sp.w > 0.5;
	S.tip = pos - v_now * tp.x - dir * tp.y * (2.0 + z);
	S.rgb = shown ? vec4(tone(pick4(COLOURS[r], min(floor(u * steps), steps - 1.0)), L), 1.0) : vec4(0.0);
	S.arm = shown && u >= arm.x && u < arm.y && th(id, j, hs + 20.0, row) < sh.w ? vec4(tone(arm.z, L), 1.0) : vec4(0.0);
	S.glow = tp.z * (1.0 - 0.75 * u);
	S.light = SHINE[r];
	return S;
}

void vertex() {
	float row = MODEL_MATRIX[0].x;
	float newest = MODEL_MATRIX[0].y;
	float count = row < 0.0 ? 0.0 : MODEL_MATRIX[1].x;
	float flags = MODEL_MATRIX[1].y;
	vec2 head = MODEL_MATRIX[3].xy;
	// The mesh's vertex: its slot and corner in UV.x (slot + 0.25 or 0.75), its quad kind and
	// corner in UV.y (kind + 0.25 or 0.75).
	float slot = floor(UV.x);
	float quad = floor(UV.y);
	vec2 corner = vec2(fract(UV.x) > 0.5 ? 1.0 : 0.0, fract(UV.y) > 0.5 ? 1.0 : 0.0);
	Look L = look_from_color(COLOR, INSTANCE_CUSTOM.rgb, row < 0.0 ? 0.0 : mod(row, 61.0) * 1.618, true);
	// Zoom 0 in the look (`look_core_zoom`): a speck, its core one pixel; the rest is drawn at 1.
	bool speck = floor(COLOR.r * 255.0 + 0.5) < 4.0;
	float z = L.zoom;
	vec3 b = L.bits;
	int pi = int(L.player);
	bool live = flag_set(flags, TF_HEAD);
	bool dash = flag_set(flags, TF_DASH);
	bool lightning = bit_set(b, L_SPARKS);
	bool pull = bit_set(b, L_PULL);
	float mul = bit_set(b, L_FLECKS) ? 1.5 : (bit_set(b, L_SPARKS) ? 0.7 : (pull ? 1.1 : 1.0));
	if (flag_set(flags, TF_ORBIT)) {
		mul *= 0.8;
	}
	float tail = dash ? 0.0 : 0.3 * mul * trail_share;
	// Every light of the trail: lightning flickers, void's is dimmer; a dash's in its player's colour.
	float flicker = (lightning ? 0.55 + 0.9 * hash_seeded(floor(sim_time * 20.0), 0.0, 21.0, L.seed) : 1.0) * (pull ? 0.6 : 1.0);
	vec3 hue = dash ? P_BASE[pi] : L.glow;
	// The newest samples can be later than the moment drawn (taken in the step being drawn
	// towards): they are not drawn yet.
	float skip = 0.0;
	for (int j = 0; j < 4; j++) {
		if (float(j) >= count || trail_texel(row, newest, float(j)).w <= trail_now + 0.0001) {
			break;
		}
		skip += 1.0;
	}
	// Where the shot is (or was last), and the newest end of its path: the head while it lives.
	vec4 last = count > skip ? trail_texel(row, newest, skip) : vec4(head, 0.0, trail_now);
	vec2 target = live || count <= skip ? head : last.xy;
	vec4 head_end = vec4(head, last.z + distance(head, last.xy), trail_now);
	float o_top = live ? head_end.z : last.z;
	float t_top = live ? trail_now : last.w;
	if (count <= skip || (!live && count - skip < 2.0)) {
		t_top = -1.0e9;
		o_top = -1.0e9;
	}
	vec2 q_lo = vec2(0.0);
	vec2 q_hi = vec2(0.0);
	float m = M_PIXELS;
	vec4 a0 = vec4(0.0);
	vec4 a1 = vec4(FAR, FAR);
	vec4 a2 = vec4(0.0);
	vec4 k0 = vec4(0.0);
	vec4 k1 = vec4(0.0);
	vec4 k2 = vec4(0.0);
	bool shown = false;
	// A particle's slot: its moment back from now, and which of the moment's.
	bool is_spark = quad == Q_SPARK_LIGHT || quad == Q_SPARK || (dash && slot < 32.0 && (quad == Q_PIECE_LIGHT || quad == Q_TAIL));
	bool streak_slot = quad == Q_PIECE_LIGHT || quad == Q_TAIL;
	float id = floor(trail_now * BIRTHS) - (streak_slot ? floor(slot * 0.5) : slot);
	// A tail pixel's number (its place on the path: one every `gap` pixels, from the shot's pace
	// over its whole kept path, so it holds still while the shot flies), and the ends of a step of
	// lightning's line.
	float gap = 1.0;
	if (!dash && count - skip >= 2.0) {
		vec4 oldest = trail_texel(row, newest, count - 1.0);
		float pace = (o_top - oldest.z) / max(t_top - oldest.w, 0.001);
		gap = clamp(ceil(pace * tail / TAIL_PIXELS), 1.0, TAIL_GAP_MAX);
	}
	float n = (ceil(o_top / gap) - 1.0 - slot) * gap;
	float o_hi = min(4.0 * (floor(o_top / 4.0) - slot + 1.0), o_top);
	float o_lo = 4.0 * (floor(o_top / 4.0) - slot);
	// The one search of the path: the pieces the quad's moment, pixel or step ends are on.
	vec2 key = is_spark ? vec2(id / BIRTHS) : (quad == Q_TAIL ? vec2(n) : vec2(o_hi, o_lo));
	vec2 before = samples_before(row, newest, skip, count - 1.0, key, is_spark);
	if (is_spark) {
		float j = streak_slot ? mod(slot, 2.0) : (dash ? 2.0 : 0.0);
		Spark S = spark(row, newest, count, skip, head_end, t_top, trail_window(b, dash, tail), target, dash, id, j, before.x, L);
		if (S.alive) {
			vec2 px = floor(S.pos);
			if (quad == Q_SPARK_LIGHT || quad == Q_PIECE_LIGHT) {
				m = M_GLOW;
				shown = true;
				float reach = max(S.light.y, S.light.w);
				q_lo = px + 0.5 - reach;
				q_hi = px + 0.5 + reach;
				a0 = vec4(px + 0.5, 0.0, 1.0);
				a1 = vec4(S.glow * flicker * S.light.x, S.light.y, S.glow * flicker * S.light.z, S.light.w);
				k0 = vec4(hue, 1.0);
			} else if (S.line) {
				m = M_LINE;
				shown = S.rgb.a > 0.0;
				q_lo = min(S.pos, S.tip) - 1.0;
				q_hi = max(S.pos, S.tip) + 1.0;
				a0 = vec4(S.pos, S.tip);
				a2 = vec4(1.0e9, 0.0, 0.0, 0.0);
				k0 = S.rgb;
			} else {
				shown = S.rgb.a > 0.0 || S.arm.a > 0.0;
				q_lo = px - 1.0;
				q_hi = px + 2.0;
				a0 = vec4(px, 1.0, 1.0);
				k0 = S.rgb;
				k1 = S.arm;
			}
		}
	} else if (quad == Q_HEAD_LIGHT || quad == Q_CORE) {
		// The head, while the shot lives: the core and its light.
		if (live && !dash) {
			shown = true;
			// The way it flies: from its newest sample to the head.
			vec2 last_at = count > 0.0 ? trail_texel(row, newest, 0.0).xy : head - vec2(1.0, 0.0);
			vec2 fly = head - last_at;
			fly = length(fly) > 0.01 ? normalize(fly) : vec2(1.0, 0.0);
			vec2 at = head;
			if (bit_set(b, L_WEAVE)) {
				// Homing weaves it a pixel either side.
				at += vec2(-fly.y, fly.x) * (triangle(sim_time * 3.0 + L.seed * 0.25) > 0.0 ? 1.0 : 0.0);
			}
			vec2 px = floor(at);
			if (quad == Q_HEAD_LIGHT) {
				m = M_GLOW;
				// A speck's light is a smaller one.
				float reach = speck ? 6.0 : 8.0 + 2.0 * z;
				q_lo = px + 0.5 - reach;
				q_hi = px + 0.5 + reach;
				a0 = vec4(px + 0.5, pull ? 0.45 : 0.0, 6.0);
				a1 = vec4((speck ? 0.6 : 0.8) * flicker, speck ? 2.0 : 3.0 + z, 0.35 * flicker, reach);
				k0 = vec4(hue, 1.0);
			} else {
				// A white-hot pixel with four round it, a pixel more each side a zoom (a speck's
				// is the pixel alone); pierce lengthens it along the flight; void's is a dark
				// heart ringed in pink.
				float half_size = 3.0 + 2.0 * z;
				q_lo = px - half_size;
				q_hi = px + half_size + 1.0;
				a0 = vec4(px, 1.0, speck ? 0.0 : z);
				if (bit_set(b, L_STREAKS)) {
					a1 = vec4(at, at - fly * (2.0 + z));
				}
				k0 = vec4(pull ? OUTLINE : L.hot, 1.0);
				k1 = vec4(pull ? VOID_LIGHT : L.hi, 1.0);
				k2 = pull ? vec4(VOID_BASE, 1.0) : vec4(0.0);
			}
		}
	} else if (quad == Q_PIECE_LIGHT && !dash) {
		// A piece of the path: from sample `slot` + skip to the next newer (or the head), and the
		// tail's light round it while it is young.
		float ia = slot + skip;
		if (ia < count && (slot > 0.5 || live)) {
			vec4 A = trail_texel(row, newest, ia);
			vec4 B = slot < 0.5 ? head_end : trail_texel(row, newest, ia - 1.0);
			vec2 ab = B.xy - A.xy;
			float len = length(ab);
			if (trail_now - B.w <= tail && len >= 0.001 && B.z - A.z >= 0.001) {
				shown = true;
				m = M_TAIL_GLOW;
				// The far ends of its neighbours: a pixel takes its light from the piece nearest it.
				if (ia + 1.0 < count) {
					a1.xy = trail_texel(row, newest, ia + 1.0).xy;
				}
				if (slot > 1.5) {
					a1.zw = trail_texel(row, newest, ia - 2.0).xy;
				} else if (slot > 0.5 && live) {
					a1.zw = head;
				}
				float reach = 8.0 + 2.0 * z;
				q_lo = min(A.xy, B.xy) - reach;
				q_hi = max(A.xy, B.xy) + reach;
				float speed = len / max(B.w - A.w, 0.001);
				float tl = max(tail, 0.01);
				a0 = vec4(A.xy, B.xy);
				a2 = vec4((trail_now - A.w) / tl, (trail_now - B.w) / tl, 3.0 + z + speed * 0.012 + 6.0, z);
				k0 = vec4(hue, (pull ? 0.45 : 0.75) * flicker);
			}
		}
	} else if (quad == Q_TAIL && !dash) {
		// Tail pixel `slot` back from the head: one pixel per pixel of travel, thrown back a
		// little, cooling as it ages (and lightning's only now and then).
		float k = before.x;
		if (k >= 0.0) {
			vec4 A = trail_texel(row, newest, k);
			vec4 B = k < skip + 0.5 ? head_end : trail_texel(row, newest, k - 1.0);
			vec2 ab = B.xy - A.xy;
			float len = length(ab);
			float fr = (n - A.z) / max(B.z - A.z, 0.001);
			float tn = mix(A.w, B.w, fr);
			float ago = trail_now - tn;
			float life = (0.1 + 0.2 * th(n, 0.0, 162.0, row)) / 0.3 * tail;
			if (len >= 0.001 && B.z - A.z >= 0.001 && ago >= 0.0 && ago < life && !(lightning && th(n, 0.0, 161.0, row) > 0.35)) {
				vec2 dir = ab / len;
				float speed = len / max(B.w - A.w, 0.001);
				vec2 v = -dir * speed * 0.04 + (vec2(th(n, 0.0, 163.0, row), th(n, 0.0, 164.0, row)) - 0.5) * 5.0;
				vec2 pos = mix(A.xy, B.xy, fr) + (vec2(th(n, 0.0, 165.0, row), th(n, 0.0, 166.0, row)) - 0.5) * 0.8 + v * dragged(ago, 0.94);
				if (bit_set(b, L_GUSTS)) {
					// Storm: the tail sways side to side as it is left.
					pos += vec2(-dir.y, dir.x) * sin(tn * 30.0) * 1.4;
				}
				float u = ago / life;
				vec3 rgb = u < 0.17 ? L.hot : (u < 0.45 ? L.hi : (u < 0.8 ? L.mid : L.lo));
				if (L.plain < 0.5 && th(n, 0.0, 167.0, row) < 0.25) {
					// A quarter of an infused tail is its player's colour.
					rgb = u < 0.25 ? P_LIGHT[pi] : (u < 0.75 ? P_BASE[pi] : P_SHADOW[pi]);
				}
				float size = max(z - 1.0, 1.0);
				vec2 px = floor(pos) - floor((size - 1.0) * 0.5);
				shown = true;
				q_lo = px;
				q_hi = px + size;
				a0 = vec4(px, size, 0.0);
				k0 = vec4(rgb, 1.0);
			}
		}
	} else if (quad == Q_JAG && lightning && !dash) {
		// Step `slot` back from the head of the jagged line lightning draws behind its shot along
		// the last tenth of a second of its path: it bends every 4 pixels, re-rolled every other
		// frame, newer than 0.05 s in its light.
		float jf = floor(trail_now * 30.0);
		vec2 ends[2];
		float agos[2];
		bool found = o_hi > o_lo;
		for (int e = 0; e < 2; e++) {
			float o = e == 0 ? o_hi : o_lo;
			float k = e == 0 ? before.x : before.y;
			found = found && k >= 0.0;
			vec4 A = trail_texel(row, newest, max(k, 0.0));
			vec4 B = k < skip + 0.5 ? head_end : trail_texel(row, newest, k - 1.0);
			float fr = clamp((o - A.z) / max(B.z - A.z, 0.001), 0.0, 1.0);
			vec2 ab = B.xy - A.xy;
			vec2 dir = length(ab) > 0.001 ? normalize(ab) : vec2(1.0, 0.0);
			agos[e] = trail_now - mix(A.w, B.w, fr);
			float node = floor(o / 4.0);
			float off = mix((th(node, jf, 171.0, row) - 0.5) * 4.0, (th(node + 1.0, jf, 171.0, row) - 0.5) * 4.0, fract(o / 4.0)) * min(agos[e] / 0.02, 1.0);
			ends[e] = mix(A.xy, B.xy, fr) + vec2(-dir.y, dir.x) * off;
		}
		if (found && agos[0] <= 0.1) {
			vec2 p0 = ends[0];
			vec2 p1 = ends[1];
			float span = max(agos[1] - agos[0], 0.0001);
			if (agos[1] > 0.1) {
				// Cut where it is a tenth of a second old.
				p1 = mix(p0, p1, (0.1 - agos[0]) / span);
			}
			shown = true;
			m = M_LINE;
			q_lo = min(p0, p1) - 1.0;
			q_hi = max(p0, p1) + 1.0;
			a0 = vec4(p0, p1);
			a2 = vec4(clamp((0.05 - agos[0]) / span, 0.0, 1.0) * distance(ends[0], ends[1]), 0.0, 0.0, 0.0);
			k0 = vec4(ARC_LIGHT, 1.0);
			k1 = vec4(ARC_BASE, 1.0);
		}
	}
	// Folded away when there is nothing to draw.
	VERTEX = shown ? mix(q_lo, q_hi, corner) : vec2(-1.0e6);
	world = VERTEX;
	mode = m;
	v0 = a0;
	v1 = a1;
	v2 = a2;
	c0 = k0;
	c1 = k1;
	c2 = k2;
}

// ---- Fragments ----
// Small on purpose (core/README.md, "The shot shaders"): a pixel only colours itself from what
// its quad's vertices worked out. No loops, no look kinds, nothing read from the path.

// True when the pixel at `P` is on the one-pixel line from `a` to `b`, drawn as the mockup's
// lines are: one pixel per step along the longer axis; `along` is how far along it is.
bool on_line(vec2 P, vec2 a, vec2 b, out float along) {
	vec2 ab = b - a;
	float l = length(ab);
	vec2 c = floor(P) + 0.5;
	if (l < 0.5) {
		along = 0.0;
		return all(equal(floor(P), floor(a)));
	}
	vec2 dir = ab / l;
	along = dot(c - a, dir);
	float s = dot(c - a, vec2(-dir.y, dir.x));
	float thin = 0.5 * max(abs(dir.x), abs(dir.y));
	return along >= -0.5 && along <= l + 0.5 && s >= -thin && s < thin;
}

// How far `c` is from the piece `p`-`q`, or very far when there is no such piece.
float piece_distance(vec2 c, vec2 p, vec2 q) {
	vec2 pq = q - p;
	float len = length(pq);
	if (p.x > 1.0e6 || q.x > 1.0e6 || len < 0.001) {
		return 1.0e9;
	}
	return length(c - (p + pq * clamp(dot(c - p, pq) / (len * len), 0.0, 1.0)));
}

void fragment() {
	vec2 P = world;
	vec2 c = floor(P) + 0.5;
	vec4 colour = vec4(0.0);
	if (mode < M_GLOW + 0.5) {
		// A round light (v0 its middle, the dark it casts and how far; v1 two falloffs).
		float r = length(c - v0.xy);
		float lit = v1.x * falloff(r, v1.y) + v1.z * falloff(r, v1.w);
		colour = vec4(c0.rgb * lit * glow_strength, v0.z * falloff(r, v0.w));
	} else if (mode < M_TAIL_GLOW + 0.5) {
		// The tail's light round its piece v0.xy-v0.zw, as bright as the tail is young there (v2.xy
		// its age at the ends, in tail lives), from the nearest piece (v1 the neighbours' far ends).
		vec2 ab = v0.zw - v0.xy;
		float f = clamp(dot(c - v0.xy, ab) / dot(ab, ab), 0.0, 1.0);
		float dist = length(c - (v0.xy + ab * f));
		float u = clamp(mix(v2.x, v2.y, f), 0.0, 1.0);
		float z = v2.w;
		float lit = c0.a * (1.0 - 0.75 * u) * (1.0 - u) * (0.32 * falloff(dist, 2.0 + z) + 0.36 * falloff(dist, 7.0 + 2.0 * z));
		// A tie goes to the newer piece.
		bool nearest = dist <= piece_distance(c, v1.xy, v0.xy) && dist < piece_distance(c, v0.zw, v1.zw);
		colour = vec4(c0.rgb * (dist <= v2.z && nearest ? lit : 0.0) * glow_strength, 0.0);
	} else if (mode < M_PIXELS + 0.5) {
		// Pixels: a square of v0.z from v0.xy in c0, a cross of arms v0.w round its pixel and a
		// line v1.xy-v1.zw in c1, the pixels between the arms in c2.
		vec2 d = floor(P) - v0.xy;
		vec2 a = abs(d);
		float along;
		if (d.x >= 0.0 && d.y >= 0.0 && d.x < v0.z && d.y < v0.z) {
			colour = c0;
		} else if (((a.x == 0.0 || a.y == 0.0) && a.x + a.y <= v0.w) || (v1.x < 1.0e6 && on_line(P, v1.xy, v1.zw, along))) {
			colour = c1;
		} else if (a.x == 1.0 && a.y == 1.0) {
			colour = c2;
		}
	} else {
		// A one-pixel line from v0.xy to v0.zw: c0 for its first v2.x pixels, then c1.
		float along;
		if (on_line(P, v0.xy, v0.zw, along)) {
			colour = along < v2.x ? c0 : c1;
		}
	}
	COLOR = colour;
}

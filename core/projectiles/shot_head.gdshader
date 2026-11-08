// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
// world_vertex_coords: VERTEX is in world space in vertex(), so each quad is placed in the world
// and every pixel can be found on the world's pixel grid (nothing else moves its vertices).
render_mode blend_premul_alpha, world_vertex_coords;

// A shot in flight (the projectile manager's shot batches; core/README.md, "The shot shaders"):
// its core and the core's light. A shot's tail is motes since the owner's pick of 2026-11-05
// (docs/milestones/spell-spectacle-2.md, S5 step 4: the projectile manager lays it as births, one
// of three tail kinds a shot, and Feel's motes throw them), and so are the card particles it gives
// off (S3) and a dash's speed streaks (S5); the tail this shader once drew from each shot's path
// (a texture of the paths) is gone with the paths. Everything is drawn on the world's pixel grid,
// axis-aligned: the core is a `+` whatever way the shot flies, as the mockup draws it.
//
// PARTICLES ARE GEOMETRY (the owner, 2026-10-29). Windows browsers compile WebGL through
// Direct3D, and a big, branchy fragment stage took the compiler about 90 s on a real GPU, until
// the browser killed its GPU process. So the VERTEX stage does the work and the fragment stage only
// colours a pixel of its own quad: a few small modes, no loops, no kinds.
// A shot is one instance of a mesh (`head_mesh` in projectile_manager.gd) of small quads, each
// told in its UV which QUAD KIND (Q_*) it is. The vertex shader puts each quad round the head, or
// folds it away:
//   Q_LIGHT  the core's light (and void's dark heart);
//   Q_CORE        the core: a white-hot `+`, pierce's run, void's dark heart.
// The light is drawn first (added; void's dark heart dims what is under it), the core last.
// A quad is one triangle (performance, 2026-11-02: every vertex runs the whole vertex stage, and
// three are a quarter less than four): its corners are the box's low corner and twice the box
// along each axis, so the box is inside it, and the fragment stage cuts it to the box (`box`), a
// pixel in it when its centre is, as a square's two triangles take it.
// The instance carries its data in its transform (the batch must sit untransformed at the
// origin): origin the head (where the shot is drawn this frame), x axis (-1, the way it flies' y),
// y axis (the way it flies' x, HF_* flags). The colour and the custom data are the look
// (`shot_look.gdshaderinc`; worked out per vertex here, `look_from_color`).

#include "res://core/projectiles/shot_head.gdshaderinc"

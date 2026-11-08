// SPDX-License-Identifier: GPL-3.0-or-later
shader_type canvas_item;
render_mode blend_premul_alpha;

// A shot drawn whole in its own quad, its tail bent round its path (core/README.md, "The shot
// shaders"): Entities' familiars, orbit shots flying round their wizard (gameplay/ai/entities.gd).
// A shot the projectile manager flies leaves its tail in the world instead (`shot_head.gdshader`).
// The quad is LENGTH x GRID pixels times the zoom, the shot FRONT pixels from its front edge and
// its tail behind, +x along the flight. The code beside the kind is the bend (how its path
// curves, so its tail follows it; BEND_* below). The look (the owner, 2026-10-27): a small
// white-hot core, a long tail of pixels that cool from hot to dark and fray at the end, a soft
// glow round both, and the card particles given off from the tail. Blending is premultiplied:
// its pixels are opaque, the glow added light.

#include "res://core/projectiles/shot_orbit.gdshaderinc"

// SPDX-FileCopyrightText: 2026 peterdk31 and Spellmerge contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The native module's entry point (native/README.md): registers its classes with Godot.

#include <gdextension_interface.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "shot_kernel.h"
#include "swarm_kernel.h"

using namespace godot;

static void initialize_spellmerge(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(ShotKernel);
	GDREGISTER_CLASS(SwarmKernel);
}

static void uninitialize_spellmerge(ModuleInitializationLevel p_level) {
}

extern "C" {
GDExtensionBool GDE_EXPORT spellmerge_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_spellmerge);
	init_obj.register_terminator(uninitialize_spellmerge);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}

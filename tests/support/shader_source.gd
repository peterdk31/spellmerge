extends RefCounted
## A shader's whole source as Godot compiles it, its `#include "res://..."` lines replaced by the
## included files (recursively), for tests that read what a shader does: `Shader.code` is only its
## own file, and the shot shaders and the card looks that start from them draw from includes
## (docs/milestones/card-looks.md).


## The whole source of `shader`.
static func of(shader: Shader) -> String:
	return expand(shader.code)


## `code` with its includes expanded.
static func expand(code: String) -> String:
	var out := PackedStringArray()
	for line: String in code.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("#include \"") and trimmed.ends_with("\""):
			var path: String = trimmed.trim_prefix("#include \"").trim_suffix("\"")
			var included := load(path) as ShaderInclude
			out.append(expand(included.code) if included != null else line)
		else:
			out.append(line)
	return "\n".join(out)

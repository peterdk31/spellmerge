extends RefCounted
## The mote kinds content/motes has, for the content tests that check what names one (every mote
## source in a scene, tests/content/test_mote_sources.gd; a prop's looks,
## tests/content/props/test_prop_data.gd).

const MOTES: String = "res://content/motes/%s.tres"


## What is wrong with the kind `kind`, in words after `owner` (empty when content/motes has it).
static func problems(kind: StringName, owner: String) -> PackedStringArray:
	if kind != &"" and not ResourceLoader.exists(MOTES % kind):
		return PackedStringArray(["%s: '%s' is no mote kind (content/motes/%s.tres)" % [owner, kind, kind]])
	return PackedStringArray()

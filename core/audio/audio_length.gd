class_name AudioLength
extends RefCounted
## How long a sound plays (docs/milestones/sound.md, section 3): a stream's own length, or for an
## `AudioStreamRandomizer` (a sound's baked variants) its longest variant's, since Godot 4.7 gives a
## randomizer's `get_length()` as 0. The voices hold a voice for this long. Null is 0.


static func of(stream: AudioStream) -> float:
	if stream == null:
		return 0.0
	var randomizer := stream as AudioStreamRandomizer
	if randomizer == null:
		return stream.get_length()
	var longest: float = 0.0
	for i in randomizer.streams_count:
		longest = maxf(longest, of(randomizer.get_stream(i)))
	return longest

class_name AudioVolumes
extends RefCounted
## The four volume settings (docs/milestones/sound.md, section 5, "Volumes"): Music, Sound, Ambience
## and UI, each a machine setting (never a run's rule: it changes nothing in the simulation), saved
## by the pause menu (`SaveFile.set_setting`) under its key here and sent as its own
## `*_volume_changed` event (core/events, in percent), which Audio applies to its bus. All four are
## made as the "Ambience volume" was first: `AmbienceVolume`'s stops (0 to 100% by 10, 100% by
## default) on its perceptual curve (`share_of`). The pause menu's Audio tab shows all four (sound
## plan AU8). Its numbers live in core, so the menu (hud) and Audio (core) read the same ones.

## The saved keys. Ambience's keeps the name and saved value it had.
const MUSIC_KEY: StringName = &"music_volume"
const SOUND_KEY: StringName = &"sound_volume"
const AMBIENCE_KEY: StringName = &"ambience_volume"
const UI_KEY: StringName = &"ui_volume"


## The share of a bus's loudness `percent` plays at (0 to 1; `AmbienceVolume.share_of`).
static func share_of(percent: int) -> float:
	return AmbienceVolume.share_of(percent)

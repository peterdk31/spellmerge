extends "res://tests/support/suite.gd"
## Which icon a drawing shows (`IconDetail`, ART2; the owner's answer of 2026-11-26: "keep small HUD
## icons"): a thing's 2x icon wherever its cell shows every pixel of it, its 1x icon (`icon_small`) in
## the HUD's small cells until the HUD is redrawn, and every pickup with both.

const PICKUPS: Array[String] = [
	"res://content/coins/coin/coin.tres", "res://content/keys/key/key.tres",
	"res://content/potions/healing/healing.tres", "res://content/potions/large_healing/large_healing.tres",
	"res://content/potions/max_health/max_health.tres", "res://content/potions/small_healing/small_healing.tres",
	"res://content/potions/vigor/vigor.tres", "res://content/rerolls/reward_reroll/reward_reroll.tres",
]


func test_a_small_cell_shows_the_small_icon() -> void:
	var big := ImageTexture.create_from_image(Image.create_empty(32, 32, false, Image.FORMAT_RGBA8))
	var small := ImageTexture.create_from_image(Image.create_empty(16, 16, false, Image.FORMAT_RGBA8))
	check(IconDetail.fitting(big, small, 8.0) == small, "an 8-layout-pixel cell (16 of the picture) shows the 1x icon")
	check(IconDetail.fitting(big, small, 16.0) == big, "a 16-layout-pixel cell (32 of the picture) shows the 2x icon")
	check(IconDetail.fitting(big, null, 8.0) == big, "with no small icon, the 2x one")
	check(IconDetail.fitting(null, small, 16.0) == small, "with no 2x icon, the small one")


func test_every_pickup_has_both_icons() -> void:
	for path in PICKUPS:
		var item: ItemContent = load(path) as ItemContent
		check(item != null and item.icon != null and item.icon_small != null, "%s has both icons" % path)
		if item == null or item.icon == null or item.icon_small == null:
			continue
		check_equal(ArtDetail.of(item.icon), ArtDetail.DETAIL, "%s: its icon at 2x" % path)
		check_equal(item.icon.get_width(), 32, "%s: 32 art pixels" % path)
		check_equal(item.icon_small.get_width(), 16, "%s: its small icon 16" % path)

class_name IconDetail
extends RefCounted
## Which of a thing's two icons a drawing shows (ART2, the owner's answer of 2026-11-26: "keep small
## HUD icons"): content's icons are drawn at 2x detail (`icon`, 32 art pixels for 16 world units:
## ArtDetail), and the HUD's small cells (8 layout pixels, 16 pixels of the picture: a staff row's
## card, the quick-use cross, an item's hint, the inventory's small tiles) would drop every other row
## and column of them, outline and all. Until the HUD is redrawn at 2x detail, a thing keeps its
## icon at 1x too (`icon_small`, 16 art pixels), and a cell too small to show the big icon's every
## pixel shows the small one. One rule, asked where an icon is drawn: never a list of places.


## `icon`, or `small` when a cell `side` layout pixels across shows fewer pixels of the picture
## than `icon` has (PictureGrid.PICTURE_SCALE a layout pixel) and there is a small one.
static func fitting(icon: Texture2D, small: Texture2D, side: float) -> Texture2D:
	if icon == null or small == null:
		return icon if icon != null else small
	return small if side * float(PictureGrid.PICTURE_SCALE) < float(icon.get_width()) else icon

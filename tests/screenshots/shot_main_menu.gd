extends "res://tests/support/screenshot.gd"
## The main menu as the game opens (ART4 part 4, the pixel font): its title at 40 px, its rows at
## 12 and its notes, `main_menu`; and the title's and the first rows' 4x crop, `main_menu_4x`, where
## each art pixel of the font shows.


func take() -> void:
	var menu: Node = load("res://hud/menus/main_menu/main_menu.tscn").instantiate()
	root.add_child(menu)
	await settle()
	await shot("main_menu")
	var image: Image = await grab()
	var title := menu.find_child("Title", true, false) as Control
	var at: Vector2 = title.get_global_rect().get_center() if title != null else SCREEN * 0.5
	save_crop(image, on_screen(at), "main_menu_4x", Vector2i(80, 40))
	menu.queue_free()

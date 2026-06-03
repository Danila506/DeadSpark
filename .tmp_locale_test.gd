extends SceneTree

func _initialize() -> void:
	var lm: Node = load("res://Autoloads/LocalizationManager.gd").new()
	root.add_child(lm)
	await process_frame
	print("locale after init:", TranslationServer.get_locale())
	print("tr new game init:", tr("Новая игра"))
	lm.call("set_language", "en")
	print("locale en:", TranslationServer.get_locale())
	print("tr new game en:", tr("Новая игра"))
	lm.call("set_language", "ru")
	print("locale ru:", TranslationServer.get_locale())
	print("tr new game ru:", tr("Новая игра"))
	quit()

@tool
extends EditorInspectorPlugin

const DESCRIPTIONS_JSON_PATH := "res://addons/inspector_descriptions/descriptions.json"

const GLOBAL_DESCRIPTIONS := {
	"enabled": "Включает или выключает работу компонента.",
	"player_path": "Путь до узла игрока в дереве сцены.",
	"chunk_size_tiles": "Размер одного чанка в тайлах.",
	"world_seed": "Базовый seed для процедурной генерации.",
	"randomize_seed_on_start": "Если включено, seed будет случайным на каждом запуске.",
	"load_radius_chunks": "Сколько чанков вокруг игрока держать загруженными.",
	"world_chunks_x": "Ширина мира в чанках по оси X.",
	"world_chunks_y": "Высота мира в чанках по оси Y.",
	"fill_probability": "Вероятность заполнения клетки контентом (0..1).",
	"blocked_node_paths": "Список узлов, рядом с которыми нельзя генерировать объекты.",
	"blocked_node_radius_px": "Радиус запрета генерации вокруг blocked-узлов (в пикселях).",
	"debug_log": "Включает отладочные сообщения в Output."
}

var _script_descriptions: Dictionary = {}
var _descriptions_loaded := false

const SCRIPT_DESCRIPTIONS_DEFAULT := {
	"res://World/chunk_world_generator.gd": {
		"tile_map_path": "Путь до TileMapLayer, куда генератор ставит тайлы.",
		"chunk_size_tiles": "Размер одного чанка в тайлах.",
		"clear_existing_on_start": "Очищать ли слой перед стартовой генерацией.",
		"update_interval_sec": "Интервал проверки/подгрузки чанков (в секундах).",
		"ensure_non_empty_chunk": "Гарантировать хотя бы один тайл в чанке.",
		"source_id": "ID источника (source) в TileSet.",
		"tile_options_atlas": "Список atlas-координат тайлов для обычного режима генерации.",
		"tile_option_weights": "Веса выбора соответствующих atlas-координат.",
		"use_terrain_connect": "Использовать режим автосшивки террейна вместо set_cell.",
		"terrain_set_id": "ID набора террейнов (terrain set) в TileSet.",
		"terrain_id": "ID конкретного террейна внутри terrain set.",
		"terrain_ignore_empty": "Игнорировать ли пустые клетки при сшивке террейна."
	},
	"res://World/chunk_tree_spawner.gd": {
		"spawn_parent_path": "Путь до родительского узла, куда будут добавляться инстансы.",
		"tree_scene": "Сцена, которую спавнить в чанках.",
		"tile_size_px": "Размер одной клетки в пикселях для перевода координат.",
		"update_interval_sec": "Интервал обновления видимых чанков (в секундах).",
		"tree_probability": "Вероятность спавна объекта в одной клетке.",
		"min_trees_per_chunk": "Минимальное число объектов в чанке (fallback).",
		"min_spawn_distance_px": "Минимальная дистанция между заспавненными объектами."
	},
	"res://level.gd": {
		"default_cursor_texture": "Текстура обычного курсора.",
		"aim_cursor_texture": "Текстура курсора в режиме прицеливания.",
		"cursor_hotspot": "Точка привязки курсора (hotspot).",
		"world_bounds_generator_path": "Путь до генератора, который отдаёт границы мира.",
		"world_bounds_thickness_px": "Толщина граничных коллизий мира (в пикселях).",
		"world_bounds_collision_layer": "Физический слой граничных стен.",
		"world_bounds_collision_mask": "Физическая маска граничных стен.",
		"bullet_scene": "Сцена пули для fallback-выстрела.",
		"muzzle_marker_group": "Имя группы маркеров дула.",
		"muzzle_fallback_names": "Резервные имена узлов дула, если группа не найдена.",
		"fire_cooldown_sec": "Задержка между выстрелами (секунды).",
		"bullet_speed": "Скорость пули.",
		"bullet_lifetime_sec": "Время жизни пули (секунды).",
		"projectile_layer": "Слой коллизии пули.",
		"projectile_mask": "Маска коллизии пули.",
		"left_hand_slot_name": "Имя слота левой руки в инвентаре.",
		"allowed_left_hand_categories": "Разрешённые категории предметов для левой руки.",
		"blocked_left_hand_categories": "Запрещённые категории предметов для левой руки."
	}
}


func _can_handle(object: Object) -> bool:
	if object == null:
		return false
	var script := object.get_script()
	if script == null:
		return false
	if not (script is Script):
		return false
	var script_path := (script as Script).resource_path
	return script_path.begins_with("res://") and not script_path.begins_with("res://addons/")


func _parse_property(
	object: Object,
	_type: Variant.Type,
	name: String,
	_hint_type: PropertyHint,
	_hint_string: String,
	usage_flags: int,
	_wide: bool
) -> bool:
	# На некоторых версиях/сборках флаги использования могут отличаться,
	# поэтому не привязываемся строго к PROPERTY_USAGE_SCRIPT_VARIABLE.
	if name.is_empty():
		return false
	if name.begins_with("_"):
		return false

	var description := _resolve_description(object, name)
	if description.is_empty():
		description = _fallback_description(name)

	var wrapper := MarginContainer.new()
	wrapper.add_theme_constant_override("margin_left", 14)
	wrapper.add_theme_constant_override("margin_right", 4)
	wrapper.add_theme_constant_override("margin_bottom", 4)

	var label := Label.new()
	label.text = description
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 11)
	label.modulate = Color(0.72, 0.76, 0.82, 1.0)

	wrapper.add_child(label)
	add_custom_control(wrapper)
	return false


func _parse_begin(object: Object) -> void:
	var script := object.get_script()
	var script_path := ""
	if script is Script:
		script_path = (script as Script).resource_path
	if script_path.is_empty():
		return
	if script_path.begins_with("res://addons/"):
		return

	var header := MarginContainer.new()
	header.add_theme_constant_override("margin_left", 8)
	header.add_theme_constant_override("margin_right", 8)
	header.add_theme_constant_override("margin_bottom", 6)

	var label := Label.new()
	label.text = "Описание свойств: активно"
	label.add_theme_font_size_override("font_size", 11)
	label.modulate = Color(0.45, 0.9, 0.55, 1.0)

	header.add_child(label)
	add_custom_control(header)


func _resolve_description(object: Object, property_name: String) -> String:
	_ensure_descriptions_loaded()

	var script := object.get_script()
	if script is Script:
		var script_path := (script as Script).resource_path
		var map := _get_script_description_map(script_path)
		if not map.is_empty() and map.has(property_name):
			return String(map[property_name])

	if GLOBAL_DESCRIPTIONS.has(property_name):
		return String(GLOBAL_DESCRIPTIONS[property_name])

	return ""


func _get_script_description_map(script_path: String) -> Dictionary:
	if _script_descriptions.has(script_path):
		return _script_descriptions[script_path] as Dictionary

	var script_path_lower := script_path.to_lower()
	for key in _script_descriptions.keys():
		var k := String(key)
		if k.to_lower() == script_path_lower:
			return _script_descriptions[key] as Dictionary

	return {}


func _fallback_description(property_name: String) -> String:
	var human := property_name.replace("_", " ").strip_edges()
	if human.is_empty():
		return "Параметр настраивается в инспекторе."
	human = human.substr(0, 1).to_upper() + human.substr(1)
	return "%s (настраивается в инспекторе)." % human


func _ensure_descriptions_loaded() -> void:
	if _descriptions_loaded:
		return
	_descriptions_loaded = true
	_script_descriptions = SCRIPT_DESCRIPTIONS_DEFAULT.duplicate(true)

	if not FileAccess.file_exists(DESCRIPTIONS_JSON_PATH):
		return

	var f := FileAccess.open(DESCRIPTIONS_JSON_PATH, FileAccess.READ)
	if f == null:
		return
	var raw := f.get_as_text()
	if raw.is_empty():
		return
	var parsed := JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return
	var root := parsed as Dictionary
	if not root.has("scripts"):
		return
	var scripts: Variant = root["scripts"]
	if not (scripts is Dictionary):
		return
	var scripts_dict := scripts as Dictionary
	for path_key in scripts_dict.keys():
		var path := String(path_key)
		var values: Variant = scripts_dict[path_key]
		if not (values is Dictionary):
			continue
		var values_dict := values as Dictionary
		if not _script_descriptions.has(path):
			_script_descriptions[path] = {}
		var merged := _script_descriptions[path] as Dictionary
		for prop_key in values_dict.keys():
			merged[String(prop_key)] = String(values_dict[prop_key])
		_script_descriptions[path] = merged

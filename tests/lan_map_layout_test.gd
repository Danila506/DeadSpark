extends Node2D

const LAN_MAP := preload("res://LanMap.tscn")
const OUTPUT_PATH := "res://tests/artifacts/lan_map_preview.png"

var failures: Array[String] = []


func _ready() -> void:
	var map := LAN_MAP.instantiate()
	add_child(map)
	await get_tree().process_frame
	await get_tree().process_frame
	_check_layout(map)
	if OS.get_cmdline_user_args().has("--capture-lan-map"):
		await _capture_overview(map)
	for failure in failures:
		push_error(failure)
	print("LAN_MAP_LAYOUT_TEST=" + ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)


func _capture_overview(map: Node) -> void:
	get_window().size = Vector2i(1280, 720)
	for camera in map.find_children("*", "Camera2D", true, false):
		(camera as Camera2D).enabled = false
	var ui := map.get_node_or_null("UI") as CanvasItem
	if ui != null:
		ui.visible = false
	var hud := map.get_node_or_null("Y-Sort_Objects/HUD") as CanvasItem
	if hud != null:
		hud.visible = false
	var camera := Camera2D.new()
	camera.position = Vector2(960, 540)
	camera.zoom = Vector2(0.62, 0.62)
	camera.enabled = true
	add_child(camera)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var absolute_path := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var save_error := get_viewport().get_texture().get_image().save_png(absolute_path)
	if save_error != OK:
		failures.append("cannot save preview: %s" % save_error)
	else:
		print("LAN_MAP_PREVIEW=" + absolute_path)


func _check_layout(map: Node) -> void:
	var mood_targets: Array[NodePath] = map.get("world_mood_targets")
	_check(mood_targets.has(NodePath("LanGround")), "LanGround must receive the day/night mood grade")
	_check(mood_targets.has(NodePath("RoadLayer")), "manual RoadLayer must receive the day/night mood grade")
	var road_layer := map.get_node_or_null("RoadLayer") as TileMapLayer
	_check(road_layer != null, "manual RoadLayer missing")
	if road_layer != null:
		_check(not road_layer.get_used_cells().is_empty(), "manual RoadLayer has no saved cells")
	_check(map.get_node_or_null("LanMapLayout") == null, "runtime road generator must be absent")
	var expected_props := [
		"LanSilo", "LanCargoTruck", "LanWreckWest", "LanVerticalWreck",
		"LanIndustrialRuins", "LanPoleRoadNorth", "LanHouseSouthWest",
		"LanForesterHouseVariant"
	]
	for prop_name in expected_props:
		_check(map.get_node_or_null("Y-Sort_Objects/%s" % prop_name) != null, "%s missing" % prop_name)
	var loot_house_count := 0
	for child in map.get_node("Y-Sort_Objects").get_children():
		if child.has_method("get_network_loot_items"):
			loot_house_count += 1
	_check(loot_house_count >= 6, "expected at least six LAN loot locations")
	var spawn_root := map.get_node_or_null("NetworkSpawnPoints")
	_check(spawn_root != null and spawn_root.get_child_count() >= 4, "network spawn markers missing")
	var generator := map.get_node_or_null("WorldGeneration/ChunkWorldGenerator")
	_check(generator != null and not bool(generator.get("enabled")), "procedural generation must stay disabled")
	_check(generator != null and generator.get("config") == null, "procedural terrain config must stay detached")


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

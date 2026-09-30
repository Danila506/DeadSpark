extends Node

const HUD_SCENE = preload("res://HUD/hud.tscn")
const BOX_SCENE = preload("res://World/Boxes/Box1/Box1.tscn")
const BOX_PROFILE = preload("res://Resources/WorldGen/Loot/box_loot_profile.tres")
const LOOT_PASS = preload("res://World/Generation/loot_population_pass.gd")

var failures: Array[String] = []


class PlayerFixture extends Node2D:
	signal stats_changed
	signal status_effects_changed
	var max_health := 100.0
	var health := 100.0
	var max_water := 100.0
	var water := 100.0
	var max_food := 100.0
	var food := 100.0
	var max_stamina := 100.0
	var stamina := 100.0
	var is_bleeding := false
	var is_fractured := false
	var is_diseased := false
	func has_passive_regeneration() -> bool: return false


func _ready() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	if not value: failures.append(message)


func _make_box(container_id: String) -> Node:
	var box := BOX_SCENE.instantiate()
	box.world_generated_loot = true
	box.generated_container_id = container_id
	box.loot_profile = BOX_PROFILE
	add_child(box)
	var population_pass: LootPopulationPass = LOOT_PASS.new()
	var output := population_pass.build_manifests(7331, [box])
	population_pass.free()
	_check(output.blocking_errors.is_empty(), "manifest generation failed for " + container_id)
	if output.blocking_errors.is_empty(): box.apply_loot_manifest(LootContainerManifest.from_canonical(output.loot_manifests[0]))
	return box


func _run() -> void:
	var player := PlayerFixture.new()
	player.add_to_group("player")
	add_child(player)
	var hud := HUD_SCENE.instantiate()
	hud.randomize_start_time_on_new_game = false
	add_child(hud)
	hud.set_process(false)
	hud.apply_save_data({"game_time_total_minutes": 120.0})

	var untouched := _make_box("untouched_restock_box")
	await get_tree().process_frame
	untouched.mark_loot_opened()
	var untouched_before := GenerationHashes.sha256_of(untouched.get_save_data().loot_slots)
	hud.add_game_time_minutes(24.0 * 60.0)
	_check(GenerationHashes.sha256_of(untouched.get_save_data().loot_slots) == untouched_before, "untouched container changed after 24 hours")

	hud.apply_save_data({"game_time_total_minutes": 3000.0})
	var box := _make_box("partial_restock_box")
	await get_tree().process_frame
	box.mark_loot_opened()
	var occupied: Array[int] = []
	for index in range(box.loot_slots.size()):
		if box.loot_slots[index] != null: occupied.append(index)
	_check(occupied.size() >= 3, "test box requires at least three initial items")
	var preserved_index := occupied[2]
	var preserved_item: ItemData = box.loot_slots[preserved_index]
	box.loot_slots[occupied[0]] = null
	box.loot_slots[occupied[1]] = null
	hud.add_game_time_minutes(24.0 * 60.0 - 1.0)
	_check(box.loot_slots[preserved_index] == preserved_item, "remaining item changed before the interval elapsed")
	_check(box.loot_slots[occupied[0]] == null and box.loot_slots[occupied[1]] == null, "container refilled too early")
	hud.add_game_time_minutes(1.0)
	_check(box.loot_slots[preserved_index] == preserved_item, "remaining item was replaced during top-up")
	_check(box.get_save_data().loot_restock_state.is_empty(), "completed restock cycle stayed active")

	var saved_source := _make_box("saved_restock_box")
	await get_tree().process_frame
	saved_source.mark_loot_opened()
	var removed_index: int = saved_source.loot_slots.find_custom(func(item): return item != null)
	saved_source.loot_slots[removed_index] = null
	hud.add_game_time_minutes(300.0)
	var saved_state: Dictionary = saved_source.get_save_data()
	var restored := _make_box("saved_restock_box")
	restored.apply_save_data(saved_state)
	await get_tree().process_frame
	hud.add_game_time_minutes(24.0 * 60.0 - 300.0)
	_check(restored.get_save_data().loot_restock_state.is_empty(), "restock interval did not survive save/load")

	if failures.is_empty():
		print("LOOT_DAILY_RESTOCK_TEST=PASS total_minutes=%.1f" % hud.get_game_time_total_minutes())
		get_tree().quit(0)
	else:
		for failure in failures: push_error("Loot daily restock test: " + failure)
		get_tree().quit(1)

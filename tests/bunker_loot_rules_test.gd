extends Node

const BUNKER_SCENE := preload("res://World/Assets/Bunker/Bunker.tscn")
const BUNKER_PROFILE := preload("res://Resources/WorldGen/Loot/bunker_loot_profile.tres")

var _failures: Array[String] = []

class TestItemSpawner extends Node:
	var spawned: Array[Dictionary] = []
	func spawn_world_pickup_at_position(item: ItemData, position: Vector2, runtime_id: String = "", scope: Dictionary = {}) -> bool:
		spawned.append({"item": item, "position": position, "runtime_id": runtime_id, "scope": scope})
		return true


func _ready() -> void:
	_test_profile_content()
	_test_item_count_distribution()
	_test_box_presence_variants()
	_test_spawn_marker()
	_test_spawn_marker_uses_bunker_pool()
	for failure in _failures: push_error("Bunker loot rules: " + failure)
	print("BUNKER_LOOT_RULES_TEST=" + ("PASS" if _failures.is_empty() else "FAIL"))
	get_tree().quit(0 if _failures.is_empty() else 1)


func _test_profile_content() -> void:
	var validation := BUNKER_PROFILE.validate()
	_expect(validation.valid, "profile validation: %s" % str(validation.errors))
	_expect(BUNKER_PROFILE.slot_ids.size() == 3, "container capacity must be three")
	_expect(BUNKER_PROFILE.slot_count_weights == [0.0, 45.0, 40.0, 15.0], "unexpected 1/2/3 item weights")
	var ammo_paths := {}
	var attachment_paths := {}
	var medical_paths := {}
	for entry in BUNKER_PROFILE.entries:
		var item := entry.item as ItemData
		if item == null:
			_expect(false, "null loot entry: %s" % entry.entry_id)
			continue
		if item.is_ammo_item:
			ammo_paths[item.resource_path] = true
		elif item.is_weapon_attachment or item.is_scope_attachment:
			attachment_paths[item.resource_path] = true
		elif item.storage_category == ItemData.StorageCategory.MEDICAL:
			medical_paths[item.resource_path] = true
		else:
			_expect(false, "forbidden bunker item: %s" % item.resource_path)
	_expect(ammo_paths.size() == 3, "all three ammo resources must be included")
	_expect(attachment_paths.size() == 6, "all six weapon modules must be included")
	_expect(medical_paths.size() == 10, "all ten medical resources must be included")


func _test_item_count_distribution() -> void:
	var counts := {1: 0, 2: 0, 3: 0}
	var loot_pass := LootPopulationPass.new()
	for seed in range(1000):
		var manifest := loot_pass._build_container_manifest(seed, "bunker_%d" % seed, BUNKER_PROFILE)
		var item_count := manifest.slots.size()
		_expect(item_count >= 1 and item_count <= 3, "seed %d produced %d items" % [seed, item_count])
		counts[item_count] = int(counts.get(item_count, 0)) + 1
	loot_pass.free()
	_expect(counts[1] > counts[3], "one item must be more common than three: %s" % counts)
	_expect(counts[2] > counts[3], "two items must be more common than three: %s" % counts)


func _test_box_presence_variants() -> void:
	var present := 0
	var absent := 0
	for index in range(64):
		var bunker := BUNKER_SCENE.instantiate()
		bunker.world_generated_mode = true
		bunker.building_generated_object_id = "bunker_variant_%d" % index
		bunker.configure_generated_content(1337)
		if bunker.box_present:
			present += 1
		else:
			absent += 1
			_expect(bunker.get_loot_profile().explicit_empty, "boxless bunker must expose an empty container profile")
		bunker.free()
	_expect(present > 0 and absent > 0, "generated bunkers need both box variants")


func _test_spawn_marker() -> void:
	var bunker := BUNKER_SCENE.instantiate()
	_expect(bunker.get_node_or_null("BunkerInside/SpawnMarker") is Marker2D, "authored item SpawnMarker is missing")
	bunker.free()


func _test_spawn_marker_uses_bunker_pool() -> void:
	var spawner := TestItemSpawner.new()
	spawner.add_to_group("item_spawner_network")
	add_child(spawner)
	var bunker := BUNKER_SCENE.instantiate()
	bunker.world_generated_mode = true
	bunker.building_generated_object_id = "bunker_marker_test"
	bunker.configure_generated_content(1337)
	add_child(bunker)
	bunker._spawn_world_pickups_at_markers_if_needed()
	_expect(spawner.spawned.size() == 1, "SpawnMarker must request exactly one world pickup")
	if not spawner.spawned.is_empty():
		var item := spawner.spawned[0].item as ItemData
		var allowed := item != null and (item.is_ammo_item or item.is_weapon_attachment or item.is_scope_attachment or item.storage_category == ItemData.StorageCategory.MEDICAL)
		_expect(allowed, "SpawnMarker selected an item outside the bunker pool")
		_expect(not String(spawner.spawned[0].runtime_id).is_empty(), "SpawnMarker pickup needs a stable runtime id")
		_expect(not (spawner.spawned[0].scope as Dictionary).is_empty(), "SpawnMarker pickup needs bunker visibility scope")
	bunker.free()
	spawner.free()


func _expect(value: bool, message: String) -> void:
	if not value: _failures.append(message)

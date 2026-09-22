extends Node

func _ready() -> void:
	var failures: Array[String] = []
	var generator := LootPopulationPass.new()
	for name in ["box_loot_profile", "house1_wardrobe_loot_profile", "forester_wardrobe_loot_profile", "two_storied_bedside_loot_profile", "bunker_loot_profile"]:
		var profile := load("res://Resources/WorldGen/Loot/" + name + ".tres") as LootProfile
		var combinations := {}
		var types := {}
		for index in range(32):
			var id := "container_%d" % index
			var manifest := generator._build_container_manifest(1337, id, profile)
			var seen := {}
			for slot in manifest.slots:
				if seen.has(slot.item_resource_key): failures.append("duplicate item in " + name)
				seen[slot.item_resource_key] = true
				types[slot.item_resource_key] = true
			var combination: Array = seen.keys(); combination.sort()
			combinations[str(combination)] = true
			if manifest.manifest_hash() != generator._build_container_manifest(1337, id, profile).manifest_hash(): failures.append("unstable " + name)
		if combinations.size() < 16 or types.size() < 8: failures.append("insufficient variety " + name)
		print("LOOT_VARIETY ", name, " distinct_contents=", combinations.size(), " item_types=", types.size())
	var box := preload("res://World/Boxes/Box1/Box1.tscn").instantiate()
	add_child(box)
	box._ensure_loot()
	var items: Array = box.loot_slots.duplicate()
	box._ensure_loot()
	if box.loot_slots != items: failures.append("rerolled opened box")
	box.loot_slots[0] = null
	var saved: Dictionary = box.get_save_data()
	box.apply_save_data(saved)
	box._ensure_loot()
	if box.loot_slots[0] != null: failures.append("looted item respawned")
	generator.free()
	for failure in failures: push_error(failure)
	print("LOOT_VARIETY_TEST=" + ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)

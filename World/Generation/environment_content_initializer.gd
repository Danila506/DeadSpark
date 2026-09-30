class_name EnvironmentContentInitializer
extends RefCounted

## Prepare providers before _ready so they never take the legacy random path.
static func prepare(instance: Node2D, owner: String, entry: EnvironmentEntry) -> void:
	if instance.get("persistent_id") != null:
		instance.set("persistent_id", owner)
	if instance.has_method("get_loot_container_id"):
		if instance.get("world_generated_loot") != null:
			instance.set("world_generated_loot", true)
			instance.set("generated_container_id", owner)
		else:
			instance.set("world_generated_mode", true)
			instance.set("building_generated_object_id", owner)
		instance.set("persistent_id", owner)
		if entry.loot_profile != null: instance.set("loot_profile", entry.loot_profile)
	if instance.has_method("get_enemy_population_owner_id"):
		instance.set("world_generated_mode", true)
		instance.set("generated_object_id", owner)
	if instance.has_method("get_save_key") and instance.has_method("get_save_data"):
		instance.add_to_group("generated_world_object")
		instance.set_meta("world_generation_id", owner)
		instance.set_meta("world_generation_scene_path", entry.scene.resource_path)

static func materialize(instance: Node2D, seed: int) -> Dictionary:
	var errors: Array[String] = []
	var manifests: Array[Dictionary] = []
	if instance.has_method("configure_generated_content"):
		instance.call("configure_generated_content", seed)
	if instance.has_method("get_loot_container_id"):
		var pass_node := LootPopulationPass.new()
		var result := pass_node.build_manifests(seed, [instance])
		pass_node.free()
		for error in result.blocking_errors: errors.append(String(error))
		for raw in result.loot_manifests:
			var applied: Dictionary = instance.call("apply_loot_manifest", LootContainerManifest.from_canonical(raw))
			for error in applied.get("errors", []): errors.append(String(error))
			manifests.append(raw)
	if instance.has_method("get_enemy_population_owner_id"):
		var pass_node := EnemyPopulationPass.new()
		var result := pass_node.build_manifests(seed, [instance])
		pass_node.free()
		for error in result.blocking_errors: errors.append(String(error))
		for raw in result.population_manifests:
			manifests.append(raw)
			# Clients generate the immutable manifest, but the host owns actors.
			if instance.multiplayer.multiplayer_peer != null and not instance.multiplayer.is_server(): continue
			var manifest := EnemyPopulationManifest.new()
			manifest.owner_generated_object_id = raw.owner_generated_object_id
			manifest.profile_id = raw.profile_id
			for record in raw.records:
				var item := EnemyPopulationRecord.new()
				for key in record: item.set(key, record[key])
				manifest.records.append(item)
			var applied: Dictionary = instance.call("apply_enemy_population_manifest", manifest)
			for error in applied.get("errors", []): errors.append(String(error))
	if errors.is_empty() and instance.has_method("get_save_key"):
		var save_manager := instance.get_node_or_null("/root/GameSaveManager")
		if save_manager != null: save_manager.call("register_persistent_node", instance)
	return {"errors": errors, "manifests": manifests}

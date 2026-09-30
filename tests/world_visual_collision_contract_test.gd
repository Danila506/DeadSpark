extends Node

const LEVEL := preload("res://level.tscn")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var level := LEVEL.instantiate()
	var snow := level.get_node("SnowLayer") as TileMapLayer
	var environment := level.get_node("WorldGeneration/EnvironmentGenerationPass") as EnvironmentGenerationPass
	var failures: Array[String] = []
	for entry in environment.profile.entries:
		if entry == null or not entry.enabled or entry.kind != EnvironmentEntry.Kind.TILE:
			continue
		var layer := environment.get_node_or_null(entry.target_path) as TileMapLayer
		if layer == null or layer.tile_set == null:
			failures.append("%s: missing target TileMapLayer" % entry.entry_id)
			continue
		if layer.tile_set.get_physics_layers_count() > 0 and layer.z_index <= snow.z_index:
			failures.append(
				"%s: collision layer z_index=%d is hidden by snow z_index=%d"
				% [entry.entry_id, layer.z_index, snow.z_index]
			)
	level.free()
	if not failures.is_empty():
		for failure in failures:
			push_error("World visual/collision contract: " + failure)
		get_tree().quit(1)
		return
	print("WORLD_VISUAL_COLLISION_CONTRACT_TEST=PASS")
	get_tree().quit(0)

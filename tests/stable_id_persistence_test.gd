extends Node

const ASSIGNMENT := preload("res://addons/worldgen_poi_tools/stable_id_assignment.gd")
const TEMP_PATH := "user://block_c_stable_id_persistence.tscn"

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var root := Node2D.new()
	var marker := Marker2D.new()
	marker.name = "RenamableMarker"
	root.add_child(marker)
	marker.owner = root
	var static_node := Node2D.new()
	root.add_child(static_node)
	static_node.owner = root
	var group := VillageSpawnGroup.new()
	root.add_child(group)
	group.owner = root
	var assigned := ASSIGNMENT.assign_missing(root)
	_assert(assigned == 2, "Only Marker2D and VillageSpawnGroup receive IDs")
	var marker_id := String(marker.get_meta("stable_id"))
	_assert(not marker_id.is_empty() and not static_node.has_meta("stable_id"), "Structural-only assignment")
	marker.name = "RenamedMarker"
	root.move_child(marker, root.get_child_count() - 1)
	_assert(ASSIGNMENT.assign_missing(root) == 0, "Assignment is idempotent")
	_assert(String(marker.get_meta("stable_id")) == marker_id, "Rename/reorder preserves ID")
	var packed := PackedScene.new()
	_assert(packed.pack(root) == OK, "Temporary scene packs")
	_assert(ResourceSaver.save(packed, TEMP_PATH) == OK, "Temporary scene saves")
	root.queue_free()
	await get_tree().process_frame
	var reopened := load(TEMP_PATH) as PackedScene
	var reopened_root := reopened.instantiate()
	var reopened_marker := reopened_root.get_node("RenamedMarker") as Marker2D
	_assert(String(reopened_marker.get_meta("stable_id")) == marker_id, "Save/reopen preserves ID")
	var duplicate := AuthoredGenerationValidator.validate_structural_markers([{"stable_id": marker_id}, {"stable_id": marker_id}])
	_assert(not bool(duplicate.valid), "Duplicate IDs block validation")
	print("STABLE_ID_PERSISTENCE_TEST=PASS id=" + marker_id)
	get_tree().quit(0)

func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error("Stable ID persistence test: " + message)
		get_tree().quit(1)

extends SceneTree

const VILLAGE = preload("res://Villages/Village.tscn")

func _init() -> void:
	var village := VILLAGE.instantiate() as VillageGenerator
	root.add_child(village)
	village.generate_from_poi("test-poi")
	_assert(village.get_node("GeneratedContent").get_child_count() == 25, "Village parity count")
	var hash_a := village.get_village_content_hash()
	village.clear_generated()
	await process_frame
	_assert(village.get_node("GeneratedContent").get_child_count() == 0, "clear only generated")
	village.generate_from_poi("test-poi")
	_assert(hash_a == village.get_village_content_hash(), "village deterministic hash")
	print(hash_a)
	quit(0)

func _assert(value: bool, message: String) -> void:
	if value: return
	push_error(message)
	quit(1)

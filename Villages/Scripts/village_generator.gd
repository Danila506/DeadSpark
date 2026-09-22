extends Node2D
class_name VillageGenerator

const GENERATED_GROUP: StringName = &"generated_village_object"
const GENERATOR_META_KEY: StringName = &"village_generator_id"
const MARKER_META_KEY: StringName = &"village_spawn_marker_id"

@export var generate_on_ready: bool = false
@export var clear_before_generate: bool = true
@export var generation_seed: int = 1337
@export var search_root_path: NodePath
@export var spawn_parent_path: NodePath

var _generated_nodes: Array[Node] = []
var _generator_id: String = ""
var _poi_id := ""
var _selected_content: Dictionary = {}
var _base_generation_seed := 0
var last_generation_errors: Array[String] = []


func _ready() -> void:
	_generator_id = "village-generator:v2"
	if _base_generation_seed == 0:
		_base_generation_seed = generation_seed
	if generate_on_ready:
		generate()


func generate() -> void:
	last_generation_errors.clear()
	if _generator_id.is_empty():
		_generator_id = "%s:%d" % [_get_node_label(self), get_instance_id()]
	if clear_before_generate:
		clear_generated()

	var search_root := _get_search_root()
	if search_root == null:
		push_warning("VillageGenerator: search root is not configured or does not exist.")
		return

	var groups := _get_spawn_groups(search_root)
	if groups.is_empty():
		push_warning("VillageGenerator: no VillageSpawnGroup nodes found.")
		return

	var structural_markers: Array[Dictionary] = []
	for group in groups:
		for marker in group.get_spawn_markers():
			structural_markers.append({"stable_id": String(marker.get_meta("stable_id", "")), "local_position": marker.position, "local_rotation": marker.rotation, "rotation_used": false})
	var authored_validation := AuthoredGenerationValidator.validate_structural_markers(structural_markers)
	if not bool(authored_validation.get("valid", false)):
		_blocking_error("VillageGenerator: blocking authored marker validation: %s" % "; ".join(authored_validation.get("errors", [])))
		return
	groups.sort_custom(func(a: VillageSpawnGroup, b: VillageSpawnGroup): return a.group_id < b.group_id)
	var unique_registry := {}
	for group in groups:
		_generate_group(group, unique_registry)

func generate_from_poi(poi_id: String) -> void:
	_poi_id = poi_id
	if _base_generation_seed == 0:
		_base_generation_seed = generation_seed
	generation_seed = WorldSeedService.derive_seed(_base_generation_seed, "village/" + poi_id)
	generate()


func clear_generated() -> void:
	for index in range(_generated_nodes.size() - 1, -1, -1):
		var generated_node := _generated_nodes[index]
		if is_instance_valid(generated_node):
			generated_node.queue_free()
	_generated_nodes.clear()
	_selected_content.clear()

	var cleanup_root := _get_cleanup_root()
	if cleanup_root == null:
		return
	_clear_generated_recursive(cleanup_root)


func _generate_group(group: VillageSpawnGroup, unique_registry: Dictionary) -> void:
	if group == null:
		return

	var profile := group.spawn_profile
	if profile == null:
		push_warning("VillageGenerator: spawn group '%s' has no VillageSpawnProfile." % _get_node_label(group))
		return
	if profile.object_pool == null:
		push_warning("VillageGenerator: spawn group '%s' has no VillageObjectPool." % _get_node_label(group))
		return
	if profile.object_pool.is_empty_or_invalid():
		push_warning("VillageGenerator: spawn group '%s' has an empty or invalid VillageObjectPool." % _get_node_label(group))
		return

	if group.group_id.is_empty() or profile.profile_id.is_empty() or profile.object_pool.pool_id.is_empty():
		push_error("VillageGenerator: missing stable group/profile/pool ID.")
		return
	var markers := group.get_spawn_markers()
	for marker in markers:
		if String(marker.get_meta("stable_id", "")).is_empty():
			push_error("VillageGenerator: missing marker stable_id.")
			return
	if markers.is_empty():
		push_warning("VillageGenerator: spawn group '%s' has no child Marker2D spawn points." % _get_node_label(group))
		return

	var min_count := maxi(0, profile.min_spawn_count)
	var max_count := maxi(0, profile.max_spawn_count)
	if max_count < min_count:
		push_warning("VillageGenerator: spawn group '%s' has max_spawn_count lower than min_spawn_count." % _get_node_label(group))
		max_count = min_count

	if min_count > markers.size():
		push_warning("VillageGenerator: spawn group '%s' min_spawn_count is greater than available Marker2D count." % _get_node_label(group))

	var rng := RandomNumberGenerator.new()
	rng.seed = WorldSeedService.derive_seed(generation_seed, "village/group/" + group.group_id)
	var spawn_count := rng.randi_range(min_count, max_count)
	spawn_count = clampi(spawn_count, 0, markers.size())
	if spawn_count <= 0:
		return

	markers.sort_custom(func(a: Marker2D, b: Marker2D): return String(a.get_meta("stable_id")) < String(b.get_meta("stable_id")))
	_shuffle_markers(markers, rng)
	var unique_available := _count_available_unique(profile.object_pool, unique_registry)
	var unique_required := _count_required_unique(profile.object_pool, spawn_count)
	if unique_required > unique_available:
		_blocking_error("Village unique configuration error profile=%s pool=%s group=%s required=%d available=%d" % [profile.profile_id, profile.object_pool.pool_id, group.group_id, unique_required, unique_available])
		return
	for index in spawn_count:
		var marker := markers[index]
		if marker == null:
			continue
		var entry := _pick_entry(profile.object_pool, rng, unique_registry)
		if entry == null:
			push_warning("VillageGenerator: failed to pick scene for marker '%s'." % _get_node_label(marker))
			continue
		_spawn_scene(entry, marker, group)
		if entry.unique_per_template: unique_registry[entry.entry_id] = true


func _spawn_scene(entry: VillageObjectEntry, marker: Marker2D, group: VillageSpawnGroup) -> void:
	var instance := entry.scene.instantiate()
	if instance == null:
		push_warning("VillageGenerator: failed to instantiate scene for marker '%s'." % _get_node_label(marker))
		return
	if not (instance is Node2D):
		push_warning("VillageGenerator: spawned scene for marker '%s' is not Node2D." % _get_node_label(marker))
		instance.queue_free()
		return

	var spawn_parent := _get_spawn_parent(group)
	if spawn_parent == null:
		push_warning("VillageGenerator: spawn parent is not configured or does not exist.")
		instance.queue_free()
		return

	var node_2d := instance as Node2D
	node_2d.add_to_group(GENERATED_GROUP)
	node_2d.set_meta(GENERATOR_META_KEY, _generator_id)
	var marker_id := String(marker.get_meta("stable_id"))
	var object_id := "v2/poi:%s/group:%s/marker:%s/role:root" % [_poi_id, group.group_id, marker_id]
	node_2d.set_meta(MARKER_META_KEY, marker_id)
	node_2d.set_meta("generated_object_id", object_id)
	node_2d.set_meta("selected_entry_id", entry.entry_id)
	_selected_content[object_id] = entry.entry_id
	spawn_parent.add_child(node_2d)
	node_2d.global_position = marker.global_position
	_generated_nodes.append(node_2d)

func get_village_content_hash() -> String:
	return GenerationHashes.sha256_of(_selected_content)

func _pick_entry(pool: VillageObjectPool, rng: RandomNumberGenerator, used: Dictionary) -> VillageObjectEntry:
	var valid: Array[VillageObjectEntry] = []
	for entry in pool.entries:
		if entry != null and entry.is_valid_entry() and (not entry.unique_per_template or not used.has(entry.entry_id)): valid.append(entry)
	if valid.is_empty(): return null
	valid.sort_custom(func(a: VillageObjectEntry, b: VillageObjectEntry): return a.entry_id < b.entry_id)
	var total_weight := 0.0
	for entry in valid: total_weight += entry.weight
	var pick := rng.randf() * total_weight
	for entry in valid:
		pick -= entry.weight
		if pick <= 0.0: return entry
	return valid.back()

func _count_available_unique(pool: VillageObjectPool, used: Dictionary) -> int:
	var count := 0
	for entry in pool.entries:
		if entry != null and entry.is_valid_entry() and entry.unique_per_template and not used.has(entry.entry_id): count += 1
	return count

func _count_required_unique(pool: VillageObjectPool, spawn_count: int) -> int:
	var only_unique := true
	for entry in pool.entries:
		if entry != null and entry.is_valid_entry() and not entry.unique_per_template: only_unique = false
	return spawn_count if only_unique else 0


func _get_search_root() -> Node:
	if search_root_path.is_empty():
		return self
	return get_node_or_null(search_root_path)


func _get_spawn_parent(group: VillageSpawnGroup) -> Node:
	if not spawn_parent_path.is_empty():
		return get_node_or_null(spawn_parent_path)
	return group


func _get_cleanup_root() -> Node:
	if not spawn_parent_path.is_empty():
		return get_node_or_null(spawn_parent_path)
	var search_root := _get_search_root()
	return search_root if search_root != null else self


func _get_spawn_groups(root: Node) -> Array[VillageSpawnGroup]:
	var groups: Array[VillageSpawnGroup] = []
	_collect_spawn_groups(root, groups)
	return groups


func _collect_spawn_groups(node: Node, groups: Array[VillageSpawnGroup]) -> void:
	if node.is_queued_for_deletion() or node.is_in_group(GENERATED_GROUP):
		return
	if node is VillageSpawnGroup:
		groups.append(node as VillageSpawnGroup)
	for child in node.get_children():
		_collect_spawn_groups(child, groups)


func _shuffle_markers(markers: Array[Marker2D], rng: RandomNumberGenerator) -> void:
	for index in range(markers.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var temp := markers[index]
		markers[index] = markers[swap_index]
		markers[swap_index] = temp


func _clear_generated_recursive(node: Node) -> void:
	for child in node.get_children():
		_clear_generated_recursive(child)
		if child.has_meta(GENERATOR_META_KEY) and String(child.get_meta(GENERATOR_META_KEY)) == _generator_id:
			child.queue_free()


func _get_node_label(node: Node) -> String:
	if node == null:
		return "<null>"
	if node.is_inside_tree():
		return String(node.get_path())
	return node.name

func _blocking_error(message: String) -> void:
	last_generation_errors.append(message)
	push_error(message)

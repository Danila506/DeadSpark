class_name LootContainerRestock
extends RefCounted

const MINUTES_PER_DAY := 24 * 60
const INVALID_TIME := -1.0


static func current_total_minutes(node: Node) -> float:
	if node == null or node.get_tree() == null:
		return 0.0
	var clock := node.get_tree().get_first_node_in_group("game_clock")
	if clock != null and clock.has_method("get_game_time_total_minutes"):
		return maxf(float(clock.call("get_game_time_total_minutes")), 0.0)
	return 0.0


static func begin_open_cycle(node: Node, state: Dictionary, items: Array) -> void:
	if node == null or not _is_authority(node):
		return
	# Reopening must not postpone a cycle after something has already been taken.
	if bool(state.get("looted", false)):
		node.add_to_group("loot_restock_pending")
		return
	state["opened_at_total_minutes"] = current_total_minutes(node)
	state["opening_items"] = _item_counts(items)
	state["looted"] = false
	node.add_to_group("loot_restock_pending")


static func restore_cycle(node: Node, raw_state: Variant) -> Dictionary:
	var state: Dictionary = raw_state.duplicate(true) if raw_state is Dictionary else {}
	if not bool(state.get("looted", false)):
		return {}
	state["opened_at_total_minutes"] = maxf(float(state.get("opened_at_total_minutes", INVALID_TIME)), INVALID_TIME)
	if node != null and _is_authority(node):
		node.add_to_group("loot_restock_pending")
	return state


static func serialize_cycle(state: Dictionary, items: Array) -> Dictionary:
	var result := state.duplicate(true)
	if not bool(result.get("looted", false)) and _items_were_taken(result.get("opening_items", {}), items):
		result["looted"] = true
	return result


static func is_restock_due(node: Node, state: Dictionary, items: Array, total_minutes: float) -> bool:
	if node == null or not _is_authority(node):
		return false
	var opened_at := float(state.get("opened_at_total_minutes", INVALID_TIME))
	if opened_at < 0.0:
		node.remove_from_group("loot_restock_pending")
		return false
	if not bool(state.get("looted", false)):
		if not _items_were_taken(state.get("opening_items", {}), items):
			return false
		state["looted"] = true
	return total_minutes >= opened_at + float(MINUTES_PER_DAY)


static func finish_cycle(node: Node, state: Dictionary) -> void:
	state.clear()
	if node != null:
		node.remove_from_group("loot_restock_pending")


static func top_up_empty_slots(node: Node, profile: LootProfile, items: Array, capacity: int, stable_container_id: String, total_minutes: float) -> int:
	if node == null or profile == null:
		return 0
	var game_day := maxi(int(floor(total_minutes / float(MINUTES_PER_DAY))), 0)
	var candidates := LootPopulationPass.roll_daily_items(profile, capacity, world_seed(node), stable_container_id, game_day)
	if items.size() < maxi(capacity, 0):
		items.resize(maxi(capacity, 0))
	return top_up_from_candidates(items, candidates)


static func top_up_from_candidates(items: Array, candidates: Array) -> int:
	var added := 0
	for index in range(mini(items.size(), candidates.size())):
		if items[index] == null and candidates[index] != null:
			items[index] = candidates[index]
			added += 1
	return added


static func roll_legacy_candidates(capacity: int, spawn_min: int, spawn_max: int, pool: Array[ItemData]) -> Array[ItemData]:
	var result: Array[ItemData] = []
	result.resize(maxi(capacity, 0))
	if result.is_empty() or pool.is_empty():
		return result
	var valid_pool: Array[ItemData] = []
	for item in pool:
		if item != null: valid_pool.append(item)
	if valid_pool.is_empty():
		return result
	var free_indices: Array[int] = []
	for index in range(result.size()): free_indices.append(index)
	var count := randi_range(clampi(spawn_min, 0, result.size()), clampi(spawn_max, clampi(spawn_min, 0, result.size()), result.size()))
	for _index in range(count):
		var free_position := randi_range(0, free_indices.size() - 1)
		var slot_index: int = free_indices.pop_at(free_position)
		var template: ItemData = valid_pool.pick_random()
		result[slot_index] = template.create_instance(1)
	return result


static func _item_counts(items: Array) -> Dictionary:
	var result := {}
	for item in items:
		if item == null:
			continue
		var key := String(item.call("get_runtime_id")) if item.has_method("get_runtime_id") else str(item.get_instance_id())
		result[key] = int(result.get(key, 0)) + maxi(int(item.get("stack_count")), 1)
	return result


static func _items_were_taken(raw_opening_items: Variant, current_items: Array) -> bool:
	if not (raw_opening_items is Dictionary):
		return false
	var current := _item_counts(current_items)
	for key in (raw_opening_items as Dictionary):
		if int(current.get(key, 0)) < int((raw_opening_items as Dictionary).get(key, 0)):
			return true
	return false


static func _is_authority(node: Node) -> bool:
	return node.multiplayer.multiplayer_peer == null or NetworkManager.is_server()


static func world_seed(node: Node) -> int:
	if node == null:
		return 0
	var save_manager := node.get_node_or_null("/root/GameSaveManager")
	if save_manager != null and save_manager.has_method("resolve_world_generation_seed"):
		return int(save_manager.call("resolve_world_generation_seed"))
	return 0


static func notify_network_state(node: Node) -> void:
	if node == null or node.get_tree() == null:
		return
	var shared_world := node.get_tree().get_first_node_in_group("network_shared_world")
	if shared_world != null and shared_world.has_method("notify_container_refreshed"):
		shared_world.call("notify_container_refreshed", node)

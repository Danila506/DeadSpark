extends Node
var started := {}
var expected_by_peer := {}
var timer := 0.0
func _process(delta: float) -> void:
	if not NetworkManager.is_server(): return
	timer += delta
	if timer < 1.0: return
	timer = 0.0
	var world = get_parent()
	for peer in NetworkManager.get_active_client_peers():
		if started.has(peer) or world._acked_world_paths.get(peer, {}).is_empty(): continue
		started[peer] = true
		_run(peer)
func _run(peer: int) -> void:
	await get_tree().create_timer(2.0).timeout
	var world = get_parent()
	if not world.players.has(peer): return
	var box = preload("res://World/Boxes/Box1/Box1.tscn").instantiate()
	box.name = "SharedBox_%d" % peer
	add_child(box)
	box.global_position = world.players[1].global_position + Vector2(0, 50)
	box._ensure_loot()
	box.loot_slots[0] = preload("res://Resources/Food/apple.tres").create_instance(3)
	var peer_bag = preload("res://Resources/Clothes/bag.tres").create_instance(1)
	peer_bag.runtime_storage_items.resize(maxi(peer_bag.extra_storage_slots, 1))
	InventoryManager.set_network_peer_equipped(peer, ItemData.ItemType.Bag, peer_bag)
	world.get_node("SharedWorld")._send_inventory_state(peer)
	var clock = get_tree().get_first_node_in_group("game_clock")
	clock.game_minutes_per_real_second = 0.0
	clock.set_game_time_minutes_of_day(1297.0)
	var jacket = preload("res://Resources/Clothes/jacket.tres").create_instance(1)
	jacket.endurance = 37
	InventoryManager.set_equipped(ItemData.ItemType.Jacket, jacket)
	var ui = get_tree().get_first_node_in_group("inventory_root")
	ui.open_loot_slots(box.loot_slots, box)
	expected_by_peer[peer] = {"box": box, "jacket": jacket}
	await get_tree().create_timer(1.0).timeout
	rpc_id(peer, "check_container", String(box.name), box.global_position, world.get_node("SharedWorld")._encode(box.loot_slots))

@rpc("authority", "call_remote", "reliable")
func check_container(box_name: String, position: Vector2, expected: Array) -> void:
	var world = get_parent()
	var box = preload("res://World/Boxes/Box1/Box1.tscn").instantiate()
	box.name = box_name
	add_child(box)
	box.global_position = position
	var actor = world.players[NetworkManager.get_local_peer_id()]
	actor.global_position = position + Vector2(0, 20)
	await get_tree().create_timer(1.0).timeout
	var bag = InventoryManager.get_equipped(ItemData.ItemType.Bag)
	if bag == null:
		print("LAN_SHARED_STATE_PROBE=FAIL authoritative_bag_missing")
		return
	var ui = get_tree().get_first_node_in_group("inventory_root")
	ui.open_loot_slots(box.loot_slots, box)
	await get_tree().create_timer(1.0).timeout
	var same: bool = world.get_node("SharedWorld")._encode(ui.loot_provider.runtime_storage_items) == expected
	var clock = get_tree().get_first_node_in_group("game_clock")
	var time_ok: bool = absf(clock.get_game_time_minutes_of_day() - 1297.0) < 2.0
	var remote = world.players[1]
	var equip_ok: bool = String(remote._net_remote_equipped_paths.get(ItemData.ItemType.Jacket, "")) == "res://Resources/Clothes/jacket.tres"
	if not same:
		print("LAN_SHARED_STATE_PROBE=FAIL initial_loot_mismatch")
		return
	var slot = ui.loot_slots[0]
	var data := {"item": slot.item_data, "source_mode": InventorySlot.SlotMode.CONTAINER, "container_index": slot.container_index, "source_slot": slot}
	var target = ui.storage_slots_by_type[ItemData.ItemType.Bag][0]
	ui._on_slot_drop_requested(target, data)
	ui._on_slot_drop_requested(target, data)
	await get_tree().create_timer(1.0).timeout
	var stored: bool = bag.runtime_storage_items[0] != null and bag.runtime_storage_items[0].stack_count == 3
	var removed: bool = ui.loot_provider.runtime_storage_items[0] == null
	var dropped_runtime_id: String = bag.runtime_storage_items[0].get_runtime_id() if stored else ""
	if stored:
		ui._drop_dragged_item_to_world({"item": target.item_data, "source_mode": InventorySlot.SlotMode.CONTAINER, "container_index": target.container_index, "source_slot": target})
	await get_tree().create_timer(1.0).timeout
	bag = InventoryManager.get_equipped(ItemData.ItemType.Bag)
	var authoritative_drop := bag != null and bag.runtime_storage_items[0] == null
	var dropped_pickup_found := false
	for pickup in get_tree().get_nodes_in_group("world_pickup"):
		if pickup.item_data != null and pickup.item_data.get_runtime_id() == dropped_runtime_id: dropped_pickup_found = true
	var forged_item = preload("res://Resources/Food/tushenka.tres").create_instance(77)
	var forged_runtime_id: String = forged_item.get_runtime_id()
	world.get_node("SharedWorld").rpc_id(1, "rpc_drop", GameSaveManager.serialize_item(forged_item), Vector2.ZERO)
	await get_tree().create_timer(0.4).timeout
	var forged_drop_blocked := true
	for pickup in get_tree().get_nodes_in_group("world_pickup"):
		if pickup.item_data != null and pickup.item_data.get_runtime_id() == forged_runtime_id: forged_drop_blocked = false
	print("SHARED_DETAIL same=%s time=%s equipment=%s stored=%s removed=%s authoritative_drop=%s forged_drop_blocked=%s" % [same, time_ok, equip_ok, stored, removed, authoritative_drop and dropped_pickup_found, forged_drop_blocked])
	rpc_id(1, "container_report", same and time_ok and equip_ok and stored and removed and authoritative_drop and dropped_pickup_found and forged_drop_blocked)

@rpc("any_peer", "call_remote", "reliable")
func container_report(ok: bool) -> void:
	if not NetworkManager.is_server(): return
	var peer := multiplayer.get_remote_sender_id()
	if not expected_by_peer.has(peer): return
	var entry: Dictionary = expected_by_peer[peer]
	var ui = get_tree().get_first_node_in_group("inventory_root")
	print("SHARED_DETAIL client=%s host_container=%s host_ui=%s" % [ok, entry.box.loot_slots[0] == null, ui.loot_provider.runtime_storage_items[0] == null])
	ok = ok and entry.box.loot_slots[0] == null and ui.loot_provider.runtime_storage_items[0] == null
	expected_by_peer[peer].container_ok = ok
	var source: InventorySlot
	for slot in ui.equipment_slots:
		if slot.slot_type == ItemData.ItemType.Jacket: source = slot
	if source == null:
		push_error("LAN_SHARED_STATE_PROBE missing jacket slot")
		return
	var runtime_id: String = entry.jacket.get_runtime_id()
	# Drop beside the client, without bypassing its server movement validation.
	get_parent().players[1].global_position = get_parent().players[peer].global_position + Vector2(24, 0)
	ui._drop_dragged_item_to_world({"item": source.item_data, "source_mode": InventorySlot.SlotMode.EQUIPMENT, "source_slot": source})
	await get_tree().create_timer(1.0).timeout
	rpc_id(peer, "check_drop", runtime_id)

@rpc("authority", "call_remote", "reliable")
func check_drop(runtime_id: String) -> void:
	var world = get_parent()
	var remote = world.players[1]
	var unequipped: bool = String(remote._net_remote_equipped_paths.get(ItemData.ItemType.Jacket, "missing")) == ""
	for slot in remote.equipment_visual_slots:
		if slot.item_type == ItemData.ItemType.Jacket: unequipped = unequipped and not slot.visible
	var pickup: Node2D
	for node in get_tree().get_nodes_in_group("world_pickup"):
		if node.item_data != null and node.item_data.get_runtime_id() == runtime_id: pickup = node
	if pickup == null:
		print("SHARED_DETAIL pickup_missing id=%s unequipped=%s" % [runtime_id, unequipped])
		rpc_id(1, "drop_report", false)
		return
	var actor = world.players[NetworkManager.get_local_peer_id()]
	actor.global_position = pickup.global_position
	await get_tree().create_timer(1.0).timeout
	var ui = get_tree().get_first_node_in_group("inventory_root")
	print("SHARED_DETAIL pickup_request=%s actor=%s item=%s path=%s" % [ui._request_network_pickup(pickup), actor.global_position, pickup.global_position, pickup.get_path()])
	await get_tree().create_timer(1.0).timeout
	var owned: bool = false
	var jacket = InventoryManager.get_equipped(ItemData.ItemType.Jacket)
	if jacket != null and jacket.endurance == 37: owned = true
	var bag = InventoryManager.get_equipped(ItemData.ItemType.Bag)
	for item in bag.runtime_storage_items:
		if item != null and item.item_type == ItemData.ItemType.Jacket and item.endurance == 37: owned = true
	var removed: bool = not is_instance_valid(pickup) or not pickup.is_in_group("world_pickup")
	print("SHARED_DETAIL unequipped=%s owned=%s removed=%s" % [unequipped, owned, removed])
	rpc_id(1, "drop_report", unequipped and owned and removed)

@rpc("any_peer", "call_remote", "reliable")
func drop_report(ok: bool) -> void:
	if not NetworkManager.is_server(): return
	var peer := multiplayer.get_remote_sender_id()
	if not expected_by_peer.has(peer): return
	ok = ok and bool(expected_by_peer[peer].get("container_ok", false)) and InventoryManager.get_equipped(ItemData.ItemType.Jacket) == null
	print("LAN_SHARED_STATE_PROBE=%s peer=%d loot_time_equipment_drop_pickup=%s" % ["PASS" if ok else "FAIL", peer, ok])
	if ok: _run_host_food_probe(peer)


var actions_ok := true
func _run_host_food_probe(peer: int) -> void:
	var actor = get_parent().players[1]
	var food = preload("res://Resources/Food/tushenka.tres").create_instance(1)
	var runtime_id: String = food.get_runtime_id()
	var bag = preload("res://Resources/Clothes/bag.tres").create_instance(1)
	InventoryManager.set_equipped(ItemData.ItemType.Bag, bag)
	get_parent().get_node("SharedWorld").spawn_drop(food, actor, Vector2(16, 0))
	await get_tree().create_timer(0.5).timeout
	var pickup: Node
	for item in get_tree().get_nodes_in_group("world_pickup"):
		if item.item_data.get_runtime_id() == runtime_id: pickup = item
	var ui = get_tree().get_first_node_in_group("inventory_root")
	actions_ok = pickup != null and ui._pickup_world_item(pickup)
	await get_tree().create_timer(0.3).timeout
	var food_slot: InventorySlot
	for slot in ui.storage_slots_by_type[ItemData.ItemType.Bag]:
		if slot.item_data != null and slot.item_data.get_definition().resource_path == "res://Resources/Food/tushenka.tres": food_slot = slot
	actions_ok = actions_ok and food_slot != null
	if food_slot != null: ui._begin_consumable(food_slot, 0.05)
	await get_tree().create_timer(0.3).timeout
	for item in get_tree().get_nodes_in_group("world_pickup"):
		if item.item_data.get_runtime_id() == runtime_id: actions_ok = false
	print("ACTIONS_DETAIL host_food=%s slot=%s" % [actions_ok, food_slot != null])
	rpc_id(peer, "check_food_and_start_using", runtime_id)

@rpc("authority", "call_remote", "reliable")
func check_food_and_start_using(runtime_id: String) -> void:
	var absent := true
	for item in get_tree().get_nodes_in_group("world_pickup"):
		if item.item_data.get_runtime_id() == runtime_id: absent = false
	var actor = get_parent().players[multiplayer.get_unique_id()]
	actor.start_timed_action(5.0, Callable(), "test", true, "Using")
	await get_tree().create_timer(0.5).timeout
	rpc_id(1, "check_using_on_host", absent, false)

@rpc("any_peer", "call_remote", "reliable")
func check_using_on_host(absent: bool, ended: bool) -> void:
	if not NetworkManager.is_server(): return
	var peer := multiplayer.get_remote_sender_id()
	var actor = get_parent().players[peer]
	var using_visible: bool = String(actor.anim.animation).to_lower() == "using"
	print("ACTIONS_DETAIL absent=%s ended=%s animation=%s active=%s revision=%s" % [absent, ended, actor.anim.animation, actor.action_in_progress, actor._net_action_revision])
	actions_ok = actions_ok and absent and (not using_visible if ended else using_visible) and actor.action_in_progress == not ended
	if ended:
		print("LAN_ACTIONS_PROBE=%s host_pickup_and_remote_using=%s" % ["PASS" if actions_ok else "FAIL", actions_ok])
	else:
		rpc_id(peer, "cancel_using_probe")

@rpc("authority", "call_remote", "reliable")
func cancel_using_probe() -> void:
	var actor = get_parent().players[multiplayer.get_unique_id()]
	actor.cancel_timed_action()
	await get_tree().create_timer(0.4).timeout
	rpc_id(1, "check_cancel_on_host")

@rpc("any_peer", "call_remote", "reliable")
func check_cancel_on_host() -> void:
	if not NetworkManager.is_server(): return
	var peer := multiplayer.get_remote_sender_id()
	var actor = get_parent().players[peer]
	print("ACTIONS_DETAIL cancelled animation=%s active=%s" % [actor.anim.animation, actor.action_in_progress])
	actions_ok = actions_ok and not actor.action_in_progress and String(actor.anim.animation).to_lower() != "using"
	rpc_id(peer, "finish_using_probe")

@rpc("authority", "call_remote", "reliable")
func finish_using_probe() -> void:
	var actor = get_parent().players[multiplayer.get_unique_id()]
	actor.start_timed_action(0.2, Callable(), "test", true, "Using")
	await get_tree().create_timer(0.7).timeout
	rpc_id(1, "check_using_on_host", true, true)

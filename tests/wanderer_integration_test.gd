extends Node

const WANDERER_SCENE: PackedScene = preload("res://entities/friends/Wanderer.tscn")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var player := CharacterBody2D.new()
	player.name = "TestPlayer"
	player.add_to_group(&"player")
	add_child(player)

	var wanderer := WANDERER_SCENE.instantiate() as WandererNPC
	add_child(wanderer)
	wanderer.global_position = Vector2(32.0, 16.0)
	player.global_position = Vector2(40.0, 16.0)
	var gui := preload("res://gui/GUI.tscn").instantiate()
	add_child(gui)
	await get_tree().process_frame

	_assert(NPCManager.get_npc(&"wanderer_main") == wanderer, "NPCManager registers the stable npc_id")
	_assert(wanderer.is_in_group(&"friendly_npc"), "Wanderer joins friendly_npc")
	_assert(wanderer.is_in_group(&"primary_interactable"), "Wanderer uses the primary interaction contract")
	_assert(wanderer.get_collision_exceptions().has(player), "Wanderer does not physically stick to players")
	_assert(player.get_collision_exceptions().has(wanderer), "Player collision exception is reciprocal")

	_assert(wanderer.handle_primary_interaction(player), "Primary interaction is accepted in range")
	var dialogue_panel := NPCManager.get_node("NPCDialogueLayer/NPCDialoguePanel") as NPCDialoguePanel
	_assert(dialogue_panel.visible, "NPCManager opens the shared dialogue UI")
	_assert(dialogue_panel.body_label.text == wanderer.config.introduction, "First meeting uses the introduction")
	_assert(dialogue_panel.rumor_button.texture_normal != null, "Dialogue UI uses the supplied button artwork")
	_assert(dialogue_panel.rumor_icon.texture is AtlasTexture, "Dialogue option icon is sliced from the supplied atlas")
	_assert(dialogue_panel.trade_icon.texture is AtlasTexture, "Trade icon is sliced from the supplied atlas")
	_assert(dialogue_panel.close_icon.texture is AtlasTexture, "Exit icon is sliced from the supplied atlas")
	_assert(dialogue_panel.relation_icon.texture is AtlasTexture, "Relationship icon is selected from the supplied atlas")
	_assert(is_equal_approx(dialogue_panel.relation_bar.value, 50.0), "Dialogue UI presents the neutral relationship")
	_assert(dialogue_panel.panel_root.scale.x >= 0.72 and dialogue_panel.panel_root.scale.x <= 1.65, "Dialogue UI applies a safe responsive scale")
	_assert(NPCManager.is_dialogue_open(), "NPCManager exposes the active dialogue state")
	var inventory_root := gui.get_node("InventoryRoot")
	var inventory_toggle := InputEventAction.new()
	inventory_toggle.action = &"inventory_toggle"
	inventory_toggle.pressed = true
	inventory_root._input(inventory_toggle)
	_assert(not inventory_root.is_inventory_open, "Tab cannot open inventory while NPC dialogue is visible")
	dialogue_panel.close_dialogue()
	inventory_root._input(inventory_toggle)
	_assert(inventory_root.is_inventory_open, "Tab opens inventory after NPC dialogue closes")
	inventory_root.close_inventory()
	var familiar_payload := wanderer.build_dialogue_payload(1, &"greeting")
	_assert(String(familiar_payload.get("text", "")) == wanderer.config.familiar_greeting, "Acquaintance persists in runtime state")

	var stock: Array = wanderer.get("_trade_stock") as Array
	_assert(stock.size() == 3, "Configured trade stock is instantiated")
	for item in stock:
		_assert(item is ItemData and (item as ItemData).is_runtime_instance(), "Trade definitions become runtime item instances")

	var health_before := wanderer.health
	wanderer.take_damage_from(15.0, player)
	_assert(is_equal_approx(wanderer.health, health_before - 15.0), "Damage changes NPC health")
	_assert(wanderer.state_machine.current_state == FriendlyNPCStateMachine.State.FLEE, "Attacked neutral NPC enters FLEE")

	var saved := wanderer.get_save_data()
	wanderer.queue_free()
	await get_tree().process_frame

	var restored := WANDERER_SCENE.instantiate() as WandererNPC
	add_child(restored)
	await get_tree().process_frame
	restored.apply_save_data(saved)
	_assert(restored.global_position.is_equal_approx(Vector2(32.0, 16.0)), "Position restores from persistence payload")
	_assert(is_equal_approx(restored.health, health_before - 15.0), "Health restores from persistence payload")
	var restored_payload := restored.build_dialogue_payload(1, &"greeting")
	_assert(String(restored_payload.get("text", "")) == restored.config.familiar_greeting, "Acquaintance restores from persistence payload")

	print("WANDERER_INTEGRATION_TEST=PASS")
	get_tree().quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("Wanderer integration test: " + message)
	get_tree().quit(1)

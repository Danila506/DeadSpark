extends CharacterBody2D

@onready var body_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var danger_zone: Area2D = get_node_or_null("DangeonZone") as Area2D
@onready var health_bar_root: Control = get_node_or_null("ActionBarRoot") as Control
@onready var health_bar_fill: TextureProgressBar = get_node_or_null("ActionBarRoot/ActionBarFill") as TextureProgressBar
@onready var die_outline_sprite: Sprite2D = get_node_or_null("DieDeerOutline") as Sprite2D
@onready var die_sprite: Sprite2D = get_node_or_null("DieDeer") as Sprite2D
@onready var flayed_sprite: Sprite2D = get_node_or_null("FlayedDeer") as Sprite2D
@onready var interact_label: Label = get_node_or_null("InteractLabel") as Label
@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D

@export var max_health: float = 120.0
@export var min_hits_to_kill: int = 3
@export var loot_item_data: ItemData = preload("res://Resources/Food/wolf_meat.tres")
@export var loot_count: int = 2
@export var pickup_scene: PackedScene = preload("res://items/scenes/pickup_item.tscn")
@export var harvest_duration_sec: float = 1.2
@export var required_cleaver_item_names: Array[String] = ["Нож-секач"]
@export var wander_speed: float = 28.0
@export var flee_speed: float = 95.0
@export var wander_radius_px: float = 120.0
@export var wander_retarget_min_sec: float = 1.3
@export var wander_retarget_max_sec: float = 3.0
@export var flee_persist_sec: float = 1.2
@export var flee_speed_multiplier: float = 2.0
@export var flee_animation_speed_multiplier: float = 2.0
@export var death_animation_name: StringName = &"Die"

var health: float = 0.0
var is_dead: bool = false
var is_flayed: bool = false
var _death_animation_playing: bool = false
var _harvest_in_progress: bool = false
var _hits_taken: int = 0
var _spawn_origin: Vector2 = Vector2.ZERO
var _move_target: Vector2 = Vector2.ZERO
var _wander_retarget_left: float = 0.0
var _flee_from_player: Node2D = null
var _flee_left: float = 0.0
var _player_inside_danger_zone: bool = false


func _ready() -> void:
	health = max_health
	add_to_group("enemy")
	_spawn_origin = global_position
	_pick_next_wander_target()
	if body_sprite != null:
		body_sprite.play(&"Idle_down")
	if die_outline_sprite != null:
		die_outline_sprite.visible = false
	if die_sprite != null:
		die_sprite.visible = false
	if flayed_sprite != null:
		flayed_sprite.visible = false
	if interact_label != null:
		interact_label.visible = false
	if danger_zone != null:
		danger_zone.body_entered.connect(_on_danger_zone_body_entered)
		danger_zone.body_exited.connect(_on_danger_zone_body_exited)
	if body_sprite != null and not body_sprite.animation_finished.is_connected(_on_body_sprite_animation_finished):
		body_sprite.animation_finished.connect(_on_body_sprite_animation_finished)
	_update_health_ui()


func _physics_process(delta: float) -> void:
	if is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		_update_dead_visual_state()
		return

	var desired_velocity := Vector2.ZERO
	var is_fleeing := _should_flee()
	if is_fleeing:
		_flee_left = max(_flee_left - delta, 0.0)
		desired_velocity = _get_flee_direction() * flee_speed * max(flee_speed_multiplier, 0.0)
	else:
		_wander_retarget_left -= delta
		if _wander_retarget_left <= 0.0 or global_position.distance_to(_move_target) < 8.0:
			_pick_next_wander_target()
		var to_target := _move_target - global_position
		if to_target.length() > 2.0:
			desired_velocity = to_target.normalized() * wander_speed

	velocity = velocity.move_toward(desired_velocity, 220.0 * delta)
	move_and_slide()
	_update_move_animation(velocity, is_fleeing)


func take_damage_from(amount: float, _source: Node = null, _hit_context: Dictionary = {}) -> void:
	if is_dead:
		return
	_hits_taken += 1
	health = clamp(health - max(amount, 0.0), 0.0, max_health)
	if _hits_taken < max(min_hits_to_kill, 1):
		health = max(health, 1.0)
	_update_health_ui()
	if health <= 0.0:
		_kill()
	elif _source is Node2D:
		_flee_from_player = _source as Node2D
		_flee_left = max(_flee_left, flee_persist_sec)


func handle_secondary_interaction(interactor: Node) -> bool:
	if not is_dead or is_flayed or _harvest_in_progress:
		return false
	if interactor == null or not interactor.is_in_group("player"):
		return false
	if not _has_cleaver_in_inventory():
		return false
	if interactor.has_method("start_timed_action"):
		var started := bool(interactor.start_timed_action(harvest_duration_sec, Callable(self, "_finish_harvest"), "Разделка", true, "Using"))
		if started:
			_harvest_in_progress = true
			remove_from_group("secondary_interactable")
		return started
	return false


func _kill() -> void:
	is_dead = true
	add_to_group("secondary_interactable")
	if danger_zone != null:
		_player_inside_danger_zone = false
		for body in danger_zone.get_overlapping_bodies():
			if body != null and body.is_in_group("player"):
				_player_inside_danger_zone = true
				break
	if health_bar_root != null:
		health_bar_root.visible = false
	_play_death_animation()
	_update_dead_visual_state()
	if flayed_sprite != null:
		flayed_sprite.visible = false
	if collision_shape != null:
		collision_shape.disabled = true
	velocity = Vector2.ZERO
	_update_move_animation(Vector2.ZERO)


func _finish_harvest() -> void:
	if not is_dead or is_flayed:
		return
	if not _has_cleaver_in_inventory():
		_harvest_in_progress = false
		if is_dead and not is_flayed:
			add_to_group("secondary_interactable")
		return
	is_flayed = true
	_harvest_in_progress = false
	remove_from_group("secondary_interactable")
	_drop_loot()
	if die_outline_sprite != null:
		die_outline_sprite.visible = false
	if die_sprite != null:
		die_sprite.visible = false
	if body_sprite != null:
		body_sprite.visible = false
	if flayed_sprite != null:
		flayed_sprite.visible = true
	if interact_label != null:
		interact_label.visible = false


func _drop_loot() -> void:
	if pickup_scene == null or loot_item_data == null:
		return
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_parent()
	if scene_root == null:
		return
	for _i in range(max(loot_count, 1)):
		var pickup: Node = pickup_scene.instantiate()
		if pickup == null:
			continue
		scene_root.add_child(pickup)
		var deer_item_instance: ItemData = loot_item_data.create_instance(1)
		if pickup.has_method("setup_from_item_data"):
			pickup.setup_from_item_data(deer_item_instance)
		elif "item_data" in pickup:
			pickup.item_data = deer_item_instance
		if pickup is Node2D:
			var offset := Vector2(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0))
			(pickup as Node2D).global_position = global_position + offset


func _update_health_ui() -> void:
	if health_bar_fill != null:
		health_bar_fill.max_value = max(max_health, 1.0)
		health_bar_fill.value = clamp(health, 0.0, health_bar_fill.max_value)
	if health_bar_root != null:
		health_bar_root.visible = not is_dead


func _on_danger_zone_body_entered(body: Node) -> void:
	if body == null or not body.is_in_group("player"):
		return
	_player_inside_danger_zone = true
	if is_dead:
		_update_dead_visual_state()
		return
	if body is Node2D:
		_flee_from_player = body as Node2D
		_flee_left = max(_flee_left, flee_persist_sec)


func _on_danger_zone_body_exited(body: Node) -> void:
	if body == null or not body.is_in_group("player"):
		return
	_player_inside_danger_zone = false
	if is_dead:
		_update_dead_visual_state()
		return
	if _flee_from_player == body:
		_flee_left = max(_flee_left, 0.5)


func _should_flee() -> bool:
	return _flee_from_player != null and is_instance_valid(_flee_from_player) and _flee_left > 0.0


func _get_flee_direction() -> Vector2:
	if _flee_from_player == null or not is_instance_valid(_flee_from_player):
		return Vector2.RIGHT
	var away := global_position - _flee_from_player.global_position
	if away.length() < 0.001:
		return Vector2.RIGHT
	return away.normalized()


func _pick_next_wander_target() -> void:
	_wander_retarget_left = randf_range(wander_retarget_min_sec, wander_retarget_max_sec)
	var angle := randf() * TAU
	var distance := randf_range(24.0, wander_radius_px)
	_move_target = _spawn_origin + Vector2.RIGHT.rotated(angle) * distance


func _update_move_animation(move_velocity: Vector2, is_fleeing: bool = false) -> void:
	if body_sprite == null:
		return
	if is_dead:
		return
	if not body_sprite.visible:
		return
	body_sprite.speed_scale = flee_animation_speed_multiplier if is_fleeing else 1.0
	if move_velocity.length() < 4.0:
		body_sprite.play(&"Idle_down")
		return

	if abs(move_velocity.x) > abs(move_velocity.y):
		if move_velocity.x >= 0.0:
			body_sprite.play(&"Right")
			body_sprite.flip_h = true
		else:
			body_sprite.play(&"Left")
			body_sprite.flip_h = false
		return

	if move_velocity.y < 0.0:
		body_sprite.play(&"Up")
		body_sprite.flip_h = false
	else:
		body_sprite.play(&"Down")
		body_sprite.flip_h = false


func _has_cleaver_in_inventory() -> bool:
	if InventoryManager == null or not InventoryManager.has_method("get_equipped"):
		return false

	var slots_to_check := [
		ItemData.ItemType.AR_Weapon,
		ItemData.ItemType.Pistols,
		ItemData.ItemType.MeleeWeapon,
		ItemData.ItemType.Jacket,
		ItemData.ItemType.HeavyArmour,
		ItemData.ItemType.Trousers,
		ItemData.ItemType.Bag,
		ItemData.ItemType.Lefthand
	]
	for slot_type in slots_to_check:
		var equipped_item: ItemData = InventoryManager.get_equipped(int(slot_type))
		if _item_or_children_match_cleaver(equipped_item):
			return true
	return false


func _item_or_children_match_cleaver(item: ItemData) -> bool:
	if item == null:
		return false
	if _is_cleaver_item(item):
		return true
	for stored_item in item.runtime_storage_items:
		if stored_item is ItemData and _item_or_children_match_cleaver(stored_item as ItemData):
			return true
	return false


func _is_cleaver_item(item: ItemData) -> bool:
	if item == null:
		return false
	var item_name := item.item_name.strip_edges()
	for required_name in required_cleaver_item_names:
		if item_name == required_name.strip_edges():
			return true
	return false


func _update_dead_visual_state() -> void:
	if not is_dead or is_flayed:
		return
	var can_skin_now: bool = _player_inside_danger_zone and _has_cleaver_in_inventory()
	if die_sprite != null:
		die_sprite.visible = not _death_animation_playing
	if die_outline_sprite != null:
		die_outline_sprite.visible = can_skin_now
	if interact_label != null:
		interact_label.visible = can_skin_now
		interact_label.text = "[F] - освежевать"


func _play_death_animation() -> void:
	if body_sprite == null or body_sprite.sprite_frames == null:
		_show_static_dead_sprite()
		return
	if not body_sprite.sprite_frames.has_animation(death_animation_name):
		_show_static_dead_sprite()
		return
	if body_sprite.sprite_frames.get_frame_count(death_animation_name) <= 0:
		_show_static_dead_sprite()
		return

	_death_animation_playing = true
	body_sprite.visible = true
	body_sprite.flip_h = false
	body_sprite.speed_scale = 1.0
	body_sprite.sprite_frames.set_animation_loop(death_animation_name, false)
	body_sprite.play(death_animation_name)
	if die_sprite != null:
		die_sprite.visible = false


func _on_body_sprite_animation_finished() -> void:
	if not is_dead or is_flayed:
		return
	if body_sprite == null or body_sprite.animation != death_animation_name:
		return
	_show_static_dead_sprite()


func _show_static_dead_sprite() -> void:
	_death_animation_playing = false
	if body_sprite != null:
		body_sprite.visible = false
	if die_sprite != null and is_dead and not is_flayed:
		die_sprite.visible = true
	_update_dead_visual_state()

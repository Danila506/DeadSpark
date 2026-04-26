extends RefCounted
class_name PlayerBloodEffectsController

const BLEEDING_EFFECT_FRAMES: SpriteFrames = preload("res://Resources/Effects/Bloody.tres")

var player


func _init(owner) -> void:
	player = owner


func update_bleeding_trail(delta: float) -> void:
	if player.is_dead or not player.is_bleeding:
		return

	player.bleeding_trail_timer += delta
	if player.bleeding_trail_timer < max(player.bleeding_trail_interval_sec, 0.01):
		return

	player.bleeding_trail_timer = 0.0
	spawn_bleeding_trail_mark()


func spawn_bleeding_trail_mark() -> void:
	if BLEEDING_EFFECT_FRAMES == null:
		return
	if not BLEEDING_EFFECT_FRAMES.has_animation(player.bleeding_effect_animation_name):
		return

	var frame_count: int = BLEEDING_EFFECT_FRAMES.get_frame_count(player.bleeding_effect_animation_name)
	if frame_count <= 0:
		return

	var random_pool_size: int = min(frame_count, 3)
	var random_frame_index: int = randi() % random_pool_size
	var frame_texture: Texture2D = BLEEDING_EFFECT_FRAMES.get_frame_texture(player.bleeding_effect_animation_name, random_frame_index)
	if frame_texture == null:
		return

	var fx_root: Node = player.get_tree().current_scene
	if fx_root == null:
		fx_root = player.get_parent()
	if fx_root == null:
		return

	var blood_mark: Sprite2D = Sprite2D.new()
	blood_mark.texture = frame_texture
	blood_mark.top_level = true
	blood_mark.scale = player.bleeding_trail_scale
	blood_mark.modulate = Color(1.0, 1.0, 1.0, 0.95)
	blood_mark.z_index = player.bleeding_trail_z_index
	blood_mark.global_position = player.global_position + player.bleeding_trail_offset + Vector2(
		randf_range(-player.bleeding_trail_random_radius, player.bleeding_trail_random_radius),
		randf_range(-player.bleeding_trail_random_radius, player.bleeding_trail_random_radius)
	)
	if player.bleeding_trail_random_rotation:
		blood_mark.rotation = randf_range(-PI, PI)
	fx_root.add_child(blood_mark)

	var fade_tween: Tween = blood_mark.create_tween()
	fade_tween.tween_property(blood_mark, "modulate:a", 0.0, max(player.bleeding_trail_lifetime_sec, 0.1))
	fade_tween.finished.connect(func() -> void:
		if is_instance_valid(blood_mark):
			blood_mark.queue_free()
	)


func spawn_hit_blood(source: Node, hit_context: Dictionary = {}) -> void:
	if BLEEDING_EFFECT_FRAMES == null:
		return

	var animation_name: String = resolve_hit_blood_animation_name()
	if animation_name.is_empty():
		return

	var fx_root: Node = player.get_tree().current_scene
	if fx_root == null:
		fx_root = player.get_parent()
	if fx_root == null:
		return

	var hit_position: Vector2 = player.global_position + player.hit_blood_offset
	if hit_context.has("hit_position") and hit_context.get("hit_position") is Vector2:
		hit_position = hit_context.get("hit_position") + player.hit_blood_offset

	var away_direction: Vector2 = Vector2.RIGHT
	if source is Node2D:
		away_direction = (player.global_position - (source as Node2D).global_position).normalized()
	if away_direction == Vector2.ZERO:
		away_direction = Vector2.RIGHT

	var blood_sprite: AnimatedSprite2D = AnimatedSprite2D.new()
	blood_sprite.top_level = true
	blood_sprite.sprite_frames = BLEEDING_EFFECT_FRAMES
	blood_sprite.animation = animation_name
	blood_sprite.global_position = hit_position
	blood_sprite.scale = player.hit_blood_effect_scale
	blood_sprite.z_index = player.hit_blood_z_index
	blood_sprite.flip_h = away_direction.x < 0.0
	blood_sprite.flip_v = abs(away_direction.y) > abs(away_direction.x) and away_direction.y < 0.0
	fx_root.add_child(blood_sprite)

	BLEEDING_EFFECT_FRAMES.set_animation_loop(animation_name, false)
	BLEEDING_EFFECT_FRAMES.set_animation_speed(animation_name, max(player.hit_blood_anim_fps, 1.0))
	blood_sprite.play(animation_name)

	var fly_target: Vector2 = blood_sprite.global_position + away_direction * max(player.hit_blood_fly_distance, 0.0)
	var fly_tween: Tween = blood_sprite.create_tween()
	fly_tween.tween_property(
		blood_sprite,
		"global_position",
		fly_target,
		max(player.hit_blood_fly_duration_sec, 0.05)
	)

	blood_sprite.animation_finished.connect(func() -> void:
		if is_instance_valid(blood_sprite):
			blood_sprite.queue_free()
	)


func resolve_hit_blood_animation_name() -> String:
	if BLEEDING_EFFECT_FRAMES == null:
		return ""

	var available: Array[String] = []
	for name in player.hit_blood_animation_names:
		var trimmed: String = String(name).strip_edges()
		if trimmed.is_empty():
			continue
		if BLEEDING_EFFECT_FRAMES.has_animation(trimmed):
			available.append(trimmed)

	if available.is_empty():
		var all_names: PackedStringArray = BLEEDING_EFFECT_FRAMES.get_animation_names()
		if all_names.is_empty():
			return ""
		return String(all_names[0])

	return available[randi() % available.size()]

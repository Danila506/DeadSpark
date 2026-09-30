extends CanvasLayer

const DEFAULT_STORM_AUDIO_PATH: String = "res://Assets/AudioWaw/EnvSound/snowstorm.mp3"

@export var enabled: bool = false
@export var snowflake_textures: Array[Texture2D] = [
	preload("res://World/Assets/snowflake.png"),
	preload("res://World/Assets/snowflake2.png")
]
@export var spawn_margin_px: float = 96.0
@export_range(0.1, 1.0, 0.05) var performance_scale: float = 0.75
@export var viewport_spawn_overscan_px: float = 160.0
@export var bounds_update_interval_sec: float = 0.0

# Количество частиц на слой (делится между типами снежинок).
@export_range(16, 8000, 1) var far_snowflake_count: int = 1500
@export_range(16, 8000, 1) var near_snowflake_count: int = 1000

@export var global_wind_speed: float = 0.0
@export var global_wind_strength: float = 0.0

@export_category("Storm Audio")
@export var storm_audio_enabled: bool = true
@export var storm_audio_stream: AudioStream = null
@export_range(0.0, 1.0, 0.01) var storm_intensity: float = 1.0
@export_range(-40.0, 0.0, 0.5) var storm_audio_volume_db: float = -10.0
@export_range(0.05, 10.0, 0.05) var storm_audio_fade_in_sec: float = 2.5
@export_range(0.05, 10.0, 0.05) var storm_audio_fade_out_sec: float = 4.0

@export var far_min_fall_speed: float = 55.0
@export var far_max_fall_speed: float = 110.0
@export var far_min_scale: float = 1.0
@export var far_max_scale: float = 1.8
@export_range(0.05, 1.0, 0.01) var far_min_alpha: float = 0.2
@export_range(0.05, 1.0, 0.01) var far_max_alpha: float = 0.45
@export var far_min_sway_amount: float = 5.0
@export var far_max_sway_amount: float = 20.0
@export_range(0.0, 1.0, 0.01) var far_rotating_ratio: float = 0.20
@export var far_min_rotation_speed_deg: float = 2.0
@export var far_max_rotation_speed_deg: float = 8.0

@export var near_min_fall_speed: float = 130.0
@export var near_max_fall_speed: float = 240.0
@export var near_min_scale: float = 1.9
@export var near_max_scale: float = 3.4
@export_range(0.05, 1.0, 0.01) var near_min_alpha: float = 0.42
@export_range(0.05, 1.0, 0.01) var near_max_alpha: float = 0.72
@export var near_min_sway_amount: float = 14.0
@export var near_max_sway_amount: float = 48.0
@export_range(0.0, 1.0, 0.01) var near_rotating_ratio: float = 0.62
@export var near_min_rotation_speed_deg: float = 6.0
@export var near_max_rotation_speed_deg: float = 20.0

var _world_rect: Rect2 = Rect2(Vector2(-2000.0, -2000.0), Vector2(4000.0, 4000.0))
var _wind_phase: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _particles_root: Node2D = null
var _wind_material_entries: Array[Dictionary] = []
var _particle_entries: Array[Dictionary] = []
var _bounds_update_elapsed: float = 0.0
var _storm_audio_player: AudioStreamPlayer = null
var _storm_audio_gain: float = 0.0


func _ready() -> void:
	# Screen-space snowfall: camera/player movement must not affect particle motion.
	follow_viewport_enabled = false
	follow_viewport_scale = 1.0
	offset = Vector2.ZERO
	_setup_storm_audio()

	if not enabled:
		_clear_gpu_snow()
		visible = false
		_refresh_process_state()
		return

	_rng.randomize()
	visible = true
	layer = 30
	_world_rect = _resolve_world_rect()
	_rebuild_gpu_snow()
	_update_particle_bounds(true)
	_refresh_process_state()


func _process(delta: float) -> void:
	_update_storm_audio(delta)
	if not enabled:
		return
	if _wind_material_entries.is_empty():
		return

	_wind_phase += max(global_wind_speed, 0.0) * delta
	var wind_value: float = sin(_wind_phase) * global_wind_strength
	for entry in _wind_material_entries:
		var mat: ParticleProcessMaterial = entry.get("material") as ParticleProcessMaterial
		if mat == null:
			continue
		var wind_factor: float = float(entry.get("wind_factor", 1.0))
		var wind_x: float = clamp((wind_value * wind_factor) / 220.0, -0.35, 0.35)
		mat.direction = Vector3(wind_x, 1.0, 0.0).normalized()

	if bounds_update_interval_sec <= 0.0:
		return
	_bounds_update_elapsed += delta
	if _bounds_update_elapsed >= max(bounds_update_interval_sec, 0.01):
		_bounds_update_elapsed = 0.0
		_update_particle_bounds(false)


func _exit_tree() -> void:
	if _storm_audio_player != null:
		_storm_audio_player.stop()
		_storm_audio_player.stream = null
	storm_audio_stream = null


## Updates the ambience without restarting the stream. Weather code can call this
## every frame; zero fades out and stops playback, while values above zero fade in.
func set_storm_intensity(value: float) -> void:
	storm_intensity = clampf(value, 0.0, 1.0)
	if is_node_ready():
		_ensure_storm_audio_playing()
		_refresh_process_state()


func _setup_storm_audio() -> void:
	_storm_audio_player = get_node_or_null("StormAmbience") as AudioStreamPlayer
	if _storm_audio_player == null:
		_storm_audio_player = AudioStreamPlayer.new()
		_storm_audio_player.name = "StormAmbience"
		add_child(_storm_audio_player)

	_storm_audio_player.bus = &"Sounds"
	_storm_audio_player.volume_db = -80.0
	if storm_audio_stream == null:
		storm_audio_stream = load(DEFAULT_STORM_AUDIO_PATH) as AudioStream
	if storm_audio_stream != null:
		if storm_audio_stream is AudioStreamMP3:
			(storm_audio_stream as AudioStreamMP3).loop = true
		_storm_audio_player.stream = storm_audio_stream
	_ensure_storm_audio_playing()


func _ensure_storm_audio_playing() -> void:
	if _storm_audio_player == null or _storm_audio_player.stream == null:
		return
	if DisplayServer.get_name() == "headless":
		return
	if not storm_audio_enabled or storm_intensity <= 0.0:
		return
	if not _storm_audio_player.playing:
		_storm_audio_player.play()


func _update_storm_audio(delta: float) -> void:
	if _storm_audio_player == null:
		return

	var target_gain: float = 0.0
	if storm_audio_enabled:
		target_gain = clampf(storm_intensity, 0.0, 1.0) * db_to_linear(storm_audio_volume_db)
	if target_gain > 0.0:
		_ensure_storm_audio_playing()

	var fade_sec: float = storm_audio_fade_in_sec if target_gain > _storm_audio_gain else storm_audio_fade_out_sec
	var fade_speed: float = db_to_linear(storm_audio_volume_db) / maxf(fade_sec, 0.05)
	_storm_audio_gain = move_toward(_storm_audio_gain, target_gain, fade_speed * maxf(delta, 0.0))
	_storm_audio_player.volume_db = linear_to_db(maxf(_storm_audio_gain, 0.0001))

	if target_gain <= 0.0 and _storm_audio_gain <= 0.0001 and _storm_audio_player.playing:
		_storm_audio_player.stop()
		_storm_audio_player.volume_db = -80.0
	_refresh_process_state()


func _refresh_process_state() -> void:
	var wind_needs_process: bool = enabled and global_wind_speed > 0.0 and absf(global_wind_strength) > 0.001
	var audio_needs_process: bool = (
		_storm_audio_player != null
		and (_storm_audio_player.playing or (storm_audio_enabled and storm_intensity > 0.0))
	)
	set_process(wind_needs_process or audio_needs_process)


func _rebuild_gpu_snow() -> void:
	_clear_gpu_snow()
	if snowflake_textures.is_empty():
		return

	_particles_root = Node2D.new()
	_particles_root.name = "SnowParticlesRoot"
	add_child(_particles_root)

	var far_layer: Node2D = Node2D.new()
	far_layer.name = "FarSnow"
	_particles_root.add_child(far_layer)

	var near_layer: Node2D = Node2D.new()
	near_layer.name = "NearSnow"
	near_layer.z_index = 1
	_particles_root.add_child(near_layer)

	var valid_textures: Array[Texture2D] = []
	for tex in snowflake_textures:
		if tex != null:
			valid_textures.append(tex)
	if valid_textures.is_empty():
		return

	var far_amount_total: int = max(int(round(far_snowflake_count * clamp(performance_scale, 0.1, 1.0))), 1)
	var near_amount_total: int = max(int(round(near_snowflake_count * clamp(performance_scale, 0.1, 1.0))), 1)
	var per_tex_far: int = max(int(round(float(far_amount_total) / float(valid_textures.size()))), 1)
	var per_tex_near: int = max(int(round(float(near_amount_total) / float(valid_textures.size()))), 1)

	for tex in valid_textures:
		_create_layer_particles(far_layer, tex, "far", per_tex_far)
		_create_layer_particles(near_layer, tex, "near", per_tex_near)


func _clear_gpu_snow() -> void:
	_wind_material_entries.clear()
	_particle_entries.clear()
	if _particles_root != null and is_instance_valid(_particles_root):
		_particles_root.queue_free()
	_particles_root = null


func _create_layer_particles(parent: Node2D, texture: Texture2D, layer_type: StringName, amount: int) -> void:
	if parent == null or texture == null:
		return

	var is_near: bool = layer_type == &"near"
	var min_speed: float = near_min_fall_speed if is_near else far_min_fall_speed
	var max_speed: float = near_max_fall_speed if is_near else far_max_fall_speed
	var avg_speed: float = max((min_speed + max_speed) * 0.5, 1.0)

	var world_width: float = max(_world_rect.size.x + spawn_margin_px * 2.0, 1.0)
	var world_height: float = max(_world_rect.size.y + spawn_margin_px * 2.0, 1.0)
	var particle_lifetime: float = max(world_height / avg_speed, 0.8)
	var emitter_position: Vector2 = Vector2(_world_rect.position.x + _world_rect.size.x * 0.5, _world_rect.position.y - spawn_margin_px)

	var particles: GPUParticles2D = GPUParticles2D.new()
	particles.name = ("Snow_%s_%s" % [String(layer_type), texture.resource_path.get_file()]).replace(".", "_")
	particles.local_coords = false
	particles.amount = max(amount, 1)
	particles.lifetime = particle_lifetime
	particles.one_shot = false
	particles.preprocess = particle_lifetime
	particles.explosiveness = 0.0
	particles.randomness = 0.8
	particles.texture = texture
	particles.position = emitter_position
	particles.visibility_rect = Rect2(
		Vector2(_world_rect.position.x - spawn_margin_px, _world_rect.position.y - spawn_margin_px * 2.0),
		Vector2(world_width + spawn_margin_px * 2.0, world_height + spawn_margin_px * 3.0)
	)
	particles.modulate.a = _rng.randf_range(
		near_min_alpha if is_near else far_min_alpha,
		near_max_alpha if is_near else far_max_alpha
	)

	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(world_width * 0.5, 6.0, 0.0)
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 0.0
	mat.gravity = Vector3.ZERO
	mat.initial_velocity_min = min_speed
	mat.initial_velocity_max = max_speed
	mat.scale_min = near_min_scale if is_near else far_min_scale
	mat.scale_max = near_max_scale if is_near else far_max_scale
	mat.angular_velocity_min = _roll_angular_velocity_deg(is_near)
	mat.angular_velocity_max = _roll_angular_velocity_deg(is_near)
	mat.damping_min = 0.0
	mat.damping_max = 0.0
	mat.linear_accel_min = 0.0
	mat.linear_accel_max = 0.0
	mat.tangential_accel_min = 0.0
	mat.tangential_accel_max = 0.0
	particles.process_material = mat

	parent.add_child(particles)
	particles.emitting = true

	_wind_material_entries.append({
		"material": mat,
		"wind_factor": 1.0 if is_near else 0.55
	})
	_particle_entries.append({
		"particles": particles,
		"material": mat,
		"avg_speed": avg_speed
	})


func _roll_angular_velocity_deg(is_near: bool) -> float:
	var rotate_ratio: float = near_rotating_ratio if is_near else far_rotating_ratio
	if _rng.randf() > clamp(rotate_ratio, 0.0, 1.0):
		return 0.0

	var min_deg: float = near_min_rotation_speed_deg if is_near else far_min_rotation_speed_deg
	var max_deg: float = near_max_rotation_speed_deg if is_near else far_max_rotation_speed_deg
	var speed_deg: float = _rng.randf_range(min(min_deg, max_deg), max(min_deg, max_deg))
	return speed_deg if _rng.randf() >= 0.5 else -speed_deg


func _resolve_world_rect() -> Rect2:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		var visible_rect: Rect2 = viewport.get_visible_rect()
		return Rect2(Vector2.ZERO, visible_rect.size)

	return Rect2(Vector2.ZERO, Vector2(1920.0, 1080.0))


func _update_particle_bounds(force: bool) -> void:
	if _particle_entries.is_empty():
		return

	var target_rect: Rect2 = _resolve_active_emission_rect()
	if target_rect.size.x <= 0.0 or target_rect.size.y <= 0.0:
		return

	for entry in _particle_entries:
		var particles: GPUParticles2D = entry.get("particles") as GPUParticles2D
		var mat: ParticleProcessMaterial = entry.get("material") as ParticleProcessMaterial
		if particles == null or not is_instance_valid(particles) or mat == null:
			continue
		var avg_speed: float = max(float(entry.get("avg_speed", 40.0)), 1.0)
		_apply_particle_bounds(particles, mat, target_rect, avg_speed, force)


func _resolve_active_emission_rect() -> Rect2:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		var visible_rect: Rect2 = viewport.get_visible_rect()
		return Rect2(Vector2.ZERO, visible_rect.size).grow(max(viewport_spawn_overscan_px, 0.0))

	return _world_rect.grow(max(spawn_margin_px, 0.0))


func _apply_particle_bounds(
	particles: GPUParticles2D,
	mat: ParticleProcessMaterial,
	target_rect: Rect2,
	avg_speed: float,
	force: bool
) -> void:
	var emitter_width: float = max(target_rect.size.x + spawn_margin_px * 2.0, 1.0)
	var emitter_height: float = max(target_rect.size.y + spawn_margin_px * 2.0, 1.0)
	var emitter_position: Vector2 = Vector2(target_rect.position.x + target_rect.size.x * 0.5, target_rect.position.y - spawn_margin_px)
	var target_lifetime: float = max(emitter_height / avg_speed, 0.8)

	if force or not is_equal_approx(particles.lifetime, target_lifetime):
		particles.lifetime = target_lifetime
		particles.preprocess = target_lifetime

	particles.position = emitter_position
	particles.visibility_rect = Rect2(
		Vector2(-emitter_width * 0.5 - spawn_margin_px, -spawn_margin_px * 2.0),
		Vector2(emitter_width + spawn_margin_px * 2.0, emitter_height + spawn_margin_px * 3.0)
	)
	mat.emission_box_extents = Vector3(emitter_width * 0.5, 6.0, 0.0)

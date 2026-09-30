extends AnimatedSprite2D
class_name CampfireLightController

const SMOKE_TEXTURE: Texture2D = preload("res://Assets/Misc/par_iz_rta.png")

enum LightLayer {
	CORE,
	MEDIUM,
	HALO,
}

static var _radial_texture_cache: Dictionary = {}

@export var core_light_path: NodePath
@export var medium_light_path: NodePath
@export var halo_light_path: NodePath
@export var campfire_animation: StringName = &"bonfire"

@export_group("Burn Damage")
@export_range(0.0, 100.0, 0.1) var burn_damage_per_tick: float = 5.0
@export_range(0.1, 10.0, 0.1) var burn_tick_interval_sec: float = 1.0
@export_range(0.0, 100.0, 0.1) var clothing_endurance_loss_percent: float = 1.5
@export_range(4.0, 128.0, 1.0) var burn_radius: float = 22.0
@export_flags_2d_physics var burn_collision_mask: int = 1
@export var burn_area_offset: Vector2 = Vector2(0.0, 4.0)

@export_group("Light Masks")
@export var light_item_cull_mask: int = 1
@export var shadow_item_cull_mask: int = 2

@export_group("Core Light")
@export var core_base_energy: float = 1.22
@export var core_energy_variation: float = 0.08
@export var core_base_scale: float = 1
@export var core_scale_variation: float = 0.11
@export var core_color: Color = Color(1.0, 0.87, 0.64, 1.0)

@export_group("Medium Light")
@export var medium_base_energy: float = 0.48
@export var medium_energy_variation: float = 0.05
@export var medium_base_scale: float = 2.0
@export var medium_scale_variation: float = 0.12
@export var medium_color: Color = Color(1.0, 0.62, 0.35, 0.92)

@export_group("Halo Light")
@export var halo_enabled: bool = false
@export var halo_base_energy: float = 0.14
@export var halo_energy_variation: float = 0.025
@export var halo_base_scale: float = 4.0
@export var halo_scale_variation: float = 0.12
@export var halo_color: Color = Color(1.0, 0.52, 0.29, 0.62)

@export_group("Shadows")
@export var use_pcf13_shadows: bool = true
@export var core_cast_shadows: bool = true
@export var medium_cast_shadows: bool = false
@export_range(1.0, 6.0, 0.1) var core_shadow_filter_smooth: float = 2.2
@export_range(1.0, 6.0, 0.1) var medium_shadow_filter_smooth: float = 2.8
@export var core_shadow_alpha: float = 0.52
@export var medium_shadow_alpha: float = 0.34

@export_group("Texture")
@export_range(128, 768, 1) var radial_texture_size: int = 384
## Keep this at zero for instant engine-side gradient creation. Non-zero values opt in
## to the more expensive one-time CPU texture bake for a noisy outer edge.
@export_range(0.0, 0.35, 0.01) var edge_noise_strength: float = 0.0
@export_range(8.0, 128.0, 1.0) var edge_noise_scale: float = 34.0

@export_group("Flicker")
@export var flicker_speed: float = 3.6
@export var flicker_secondary_speed: float = 6.1
@export var medium_flicker_phase_offset: float = 1.73
@export var halo_flicker_phase_offset: float = 3.91

@export_group("Distance LOD")
@export var distance_lod_enabled: bool = true
@export_range(0.05, 2.0, 0.05) var distance_lod_update_interval_sec: float = 0.1
@export_range(32.0, 512.0, 16.0) var distance_lod_fade_range: float = 160.0
@export_range(64.0, 4096.0, 16.0) var shadow_disable_distance: float = 520.0
@export_range(64.0, 4096.0, 16.0) var halo_disable_distance: float = 560.0
@export_range(64.0, 4096.0, 16.0) var medium_disable_distance: float = 700.0
@export_range(64.0, 4096.0, 16.0) var smoke_disable_distance: float = 700.0
@export_range(64.0, 4096.0, 16.0) var all_lights_disable_distance: float = 900.0

@export_group("Time Of Day")
@export var time_of_day_manager_path: NodePath
@export_range(0.05, 3.0, 0.01) var dawn_energy_multiplier: float = 0.82
@export_range(0.05, 3.0, 0.01) var day_energy_multiplier: float = 0.42
@export_range(0.05, 3.0, 0.01) var dusk_energy_multiplier: float = 0.88
@export_range(0.05, 3.0, 0.01) var night_energy_multiplier: float = 1.2
@export_range(0.05, 3.0, 0.01) var dawn_scale_multiplier: float = 0.96
@export_range(0.05, 3.0, 0.01) var day_scale_multiplier: float = 0.88
@export_range(0.05, 3.0, 0.01) var dusk_scale_multiplier: float = 1.02
@export_range(0.05, 3.0, 0.01) var night_scale_multiplier: float = 1.08
@export_range(0.1, 20.0, 0.1) var time_of_day_response_speed: float = 4.2

@export_group("Smoke")
@export var smoke_enabled: bool = true
@export var smoke_offset: Vector2 = Vector2(0.0, -22.0)
@export var smoke_amount: int = 18
@export var smoke_lifetime_sec: float = 2.0
@export var smoke_scale_min: float = 2.5
@export var smoke_scale_max: float = 4.0

var _core_light: PointLight2D
var _medium_light: PointLight2D
var _halo_light: PointLight2D
var _phase: float = 0.0
var _time_of_day_manager: Node = null
var _time_of_day_energy_multiplier: float = 1.0
var _time_of_day_scale_multiplier: float = 1.0
var _smoke_particles: GPUParticles2D = null
var _distance_lod_elapsed: float = INF
var _smoke_lod_enabled: bool = true
var _all_lights_lod_disabled: bool = false
var _core_lod_strength: float = 1.0
var _medium_lod_strength: float = 1.0
var _halo_lod_strength: float = 1.0
var _burn_area: Area2D = null
var _burn_elapsed_by_player: Dictionary = {}


func _ready() -> void:
	_phase = randf_range(0.0, TAU)
	_core_light = _resolve_light(core_light_path, 0)
	_medium_light = _resolve_light(medium_light_path, 1)
	_halo_light = _resolve_light(halo_light_path, 2)
	_time_of_day_manager = _resolve_time_of_day_manager()

	_setup_light(_core_light, LightLayer.CORE)
	_setup_light(_medium_light, LightLayer.MEDIUM)
	_setup_light(_halo_light, LightLayer.HALO)

	if sprite_frames != null and sprite_frames.has_animation(campfire_animation):
		play(campfire_animation)
	_ensure_smoke_particles()
	_ensure_burn_area()


func _physics_process(delta: float) -> void:
	if not _is_damage_authority() or _burn_area == null:
		return
	var active_player_ids := {}
	for body in _burn_area.get_overlapping_bodies():
		if body == null or not body.is_in_group("player"):
			continue
		if bool(body.get("is_dead")):
			continue
		var player_id := body.get_instance_id()
		active_player_ids[player_id] = true
		var elapsed := float(_burn_elapsed_by_player.get(player_id, 0.0)) + maxf(delta, 0.0)
		var interval := maxf(burn_tick_interval_sec, 0.1)
		while elapsed >= interval:
			elapsed -= interval
			_apply_burn_tick(body)
			if not is_instance_valid(body) or bool(body.get("is_dead")):
				break
		_burn_elapsed_by_player[player_id] = elapsed
	for tracked_id in _burn_elapsed_by_player.keys():
		if not active_player_ids.has(tracked_id):
			_burn_elapsed_by_player.erase(tracked_id)


func _ensure_burn_area() -> void:
	if _burn_area != null:
		return
	_burn_area = Area2D.new()
	_burn_area.name = "BurnArea"
	_burn_area.collision_layer = 0
	_burn_area.collision_mask = burn_collision_mask
	_burn_area.monitoring = true
	_burn_area.monitorable = false
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	collision.position = burn_area_offset
	var shape := CircleShape2D.new()
	shape.radius = maxf(burn_radius, 4.0)
	collision.shape = shape
	_burn_area.add_child(collision)
	add_child(_burn_area)


func _apply_burn_tick(player_node: Node) -> void:
	if player_node == null or not is_instance_valid(player_node):
		return
	if player_node.has_method("take_damage"):
		player_node.call("take_damage", burn_damage_per_tick, ItemData.DamageType.GENERIC, false)
	if player_node.has_method("apply_clothing_endurance_percent_loss"):
		player_node.call("apply_clothing_endurance_percent_loss", clothing_endurance_loss_percent)


func _is_damage_authority() -> bool:
	return multiplayer.multiplayer_peer == null or (NetworkManager != null and NetworkManager.is_server())


func _process(delta: float) -> void:
	_distance_lod_elapsed += delta
	if _distance_lod_elapsed >= maxf(distance_lod_update_interval_sec, 0.05):
		_distance_lod_elapsed = 0.0
		_update_distance_lod()

	_update_smoke(delta)
	if _core_light == null and _medium_light == null and _halo_light == null:
		return
	if _all_lights_lod_disabled:
		return

	_update_time_of_day_response(delta)
	_phase += delta * maxf(flicker_speed, 0.1)
	var core_pulse := _build_flicker_pulse(0.0, 1.0)
	var medium_pulse := _build_flicker_pulse(medium_flicker_phase_offset, 0.91)
	var halo_pulse := _build_flicker_pulse(halo_flicker_phase_offset, 0.73)

	_apply_flicker(_core_light, core_base_energy, core_energy_variation, core_base_scale, core_scale_variation, clampf(0.52 + core_pulse * 0.65, 0.0, 1.0), _core_lod_strength)
	_apply_flicker(_medium_light, medium_base_energy, medium_energy_variation, medium_base_scale, medium_scale_variation, clampf(0.47 + medium_pulse * 0.72, 0.0, 1.0), _medium_lod_strength)
	_apply_flicker(_halo_light, halo_base_energy, halo_energy_variation, halo_base_scale, halo_scale_variation, clampf(0.45 + halo_pulse * 0.56, 0.0, 1.0), _halo_lod_strength)

	_apply_parent_scale_compensation(_core_light)
	_apply_parent_scale_compensation(_medium_light)
	_apply_parent_scale_compensation(_halo_light)


func _ensure_smoke_particles() -> void:
	if _smoke_particles != null or not smoke_enabled:
		return
	if SMOKE_TEXTURE == null:
		return

	_smoke_particles = GPUParticles2D.new()
	_smoke_particles.name = "SmokeParticles"
	_smoke_particles.texture = SMOKE_TEXTURE
	_smoke_particles.amount = max(smoke_amount, 1)
	_smoke_particles.lifetime = maxf(smoke_lifetime_sec, 0.1)
	_smoke_particles.one_shot = false
	_smoke_particles.explosiveness = 0.0
	_smoke_particles.randomness = 0.88
	_smoke_particles.local_coords = true
	_smoke_particles.position = smoke_offset
	_smoke_particles.z_as_relative = true
	_smoke_particles.z_index = 4
	_smoke_particles.material = _create_particle_atlas_material(3, 1)
	_smoke_particles.process_material = _create_smoke_process_material()
	add_child(_smoke_particles)
	_smoke_particles.emitting = true


func _update_smoke(delta: float) -> void:
	if not smoke_enabled or not _smoke_lod_enabled:
		if _smoke_particles != null:
			_smoke_particles.emitting = false
		return
	if _smoke_particles == null:
		_ensure_smoke_particles()
	if _smoke_particles == null:
		return

	_smoke_particles.position = smoke_offset
	_smoke_particles.amount = max(smoke_amount, 1)
	_smoke_particles.lifetime = maxf(smoke_lifetime_sec, 0.1)
	if not _smoke_particles.emitting:
		_smoke_particles.emitting = true


func _build_flicker_pulse(phase_offset: float, speed_multiplier: float) -> float:
	var phase := _phase * speed_multiplier + phase_offset
	var speed_ratio := flicker_secondary_speed / maxf(flicker_speed, 0.1)
	var primary := sin(phase) * 0.62
	var secondary := sin(phase * speed_ratio + 1.17 + phase_offset * 0.37) * 0.38
	return clampf(0.5 + (primary + secondary) * 0.5, 0.0, 1.0)


func _update_distance_lod() -> void:
	if not distance_lod_enabled:
		_set_full_quality_lod()
		_smoke_lod_enabled = true
		_all_lights_lod_disabled = false
		_update_core_shadow_lod(true)
		return

	var camera := get_viewport().get_camera_2d()
	if camera == null:
		_set_full_quality_lod()
		_smoke_lod_enabled = true
		_all_lights_lod_disabled = false
		_update_core_shadow_lod(true)
		return

	var distance_to_camera := global_position.distance_to(camera.get_screen_center_position())
	_core_lod_strength = _calculate_lod_strength(distance_to_camera, all_lights_disable_distance)
	_medium_lod_strength = _calculate_lod_strength(distance_to_camera, minf(medium_disable_distance, all_lights_disable_distance))
	_halo_lod_strength = _calculate_lod_strength(distance_to_camera, minf(halo_disable_distance, all_lights_disable_distance)) if halo_enabled else 0.0
	_set_light_lod_enabled(_core_light, _core_lod_strength > 0.001)
	_set_light_lod_enabled(_medium_light, _medium_lod_strength > 0.001)
	_set_light_lod_enabled(_halo_light, _halo_lod_strength > 0.001)
	_smoke_lod_enabled = distance_to_camera <= smoke_disable_distance
	_all_lights_lod_disabled = _core_lod_strength <= 0.001
	_update_core_shadow_lod(distance_to_camera <= shadow_disable_distance)


func _set_full_quality_lod() -> void:
	_core_lod_strength = 1.0
	_medium_lod_strength = 1.0
	_halo_lod_strength = 1.0 if halo_enabled else 0.0
	_set_light_lod_enabled(_core_light, true)
	_set_light_lod_enabled(_medium_light, true)
	_set_light_lod_enabled(_halo_light, halo_enabled)


func _calculate_lod_strength(distance_to_camera: float, disable_distance: float) -> float:
	var fade_start := maxf(disable_distance - distance_lod_fade_range, 0.0)
	return 1.0 - _smoothstep(fade_start, disable_distance, distance_to_camera)


func _set_light_lod_enabled(light: PointLight2D, should_enable: bool) -> void:
	if light != null and light.enabled != should_enable:
		light.enabled = should_enable


func _update_core_shadow_lod(within_shadow_distance: bool) -> void:
	if _core_light != null:
		_core_light.shadow_enabled = core_cast_shadows and within_shadow_distance


func _create_particle_atlas_material(h_frames: int, v_frames: int) -> CanvasItemMaterial:
	var material := CanvasItemMaterial.new()
	material.particles_animation = true
	material.particles_anim_h_frames = max(h_frames, 1)
	material.particles_anim_v_frames = max(v_frames, 1)
	material.particles_anim_loop = false
	return material


func _create_smoke_process_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 4.0
	material.direction = Vector3(0.0, -1.0, 0.0)
	material.spread = 35.0
	material.initial_velocity_min = 8.0
	material.initial_velocity_max = 22.0
	material.gravity = Vector3(0.0, -7.0, 0.0)
	material.scale_min = smoke_scale_min
	material.scale_max = maxf(smoke_scale_max, smoke_scale_min)
	material.angular_velocity_min = -40.0
	material.angular_velocity_max = 40.0
	material.color = Color(0.75, 0.75, 0.75, 0.42)
	material.anim_speed_min = 0.0
	material.anim_speed_max = 0.18
	material.anim_offset_min = 0.0
	material.anim_offset_max = 1.0
	return material


func _resolve_light(path: NodePath, fallback_index: int) -> PointLight2D:
	if not path.is_empty():
		return get_node_or_null(path) as PointLight2D

	var found: Array[PointLight2D] = []
	for child in get_children():
		if child is PointLight2D:
			found.append(child as PointLight2D)

	if fallback_index >= 0 and fallback_index < found.size():
		return found[fallback_index]
	return null


func _setup_light(light: PointLight2D, layer: int) -> void:
	if light == null:
		return

	light.enabled = true
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.range_item_cull_mask = light_item_cull_mask
	light.shadow_item_cull_mask = shadow_item_cull_mask

	match layer:
		LightLayer.CORE:
			light.color = core_color
			light.texture = _build_radial_texture(
				Color(1.0, 0.96, 0.83, 1.0),
				Color(1.0, 0.77, 0.43, 0.56),
				Color(1.0, 0.57, 0.30, 0.0)
			)
			light.energy = core_base_energy
			light.texture_scale = core_base_scale
			light.shadow_enabled = core_cast_shadows
			light.shadow_filter = Light2D.SHADOW_FILTER_PCF13 if use_pcf13_shadows else Light2D.SHADOW_FILTER_PCF5
			light.shadow_filter_smooth = core_shadow_filter_smooth
			light.shadow_color = Color(0.0, 0.0, 0.0, core_shadow_alpha)
		LightLayer.MEDIUM:
			light.color = medium_color
			light.texture = _build_radial_texture(
				Color(1.0, 0.82, 0.53, 0.82),
				Color(1.0, 0.61, 0.33, 0.34),
				Color(1.0, 0.45, 0.24, 0.0)
			)
			light.energy = medium_base_energy
			light.texture_scale = medium_base_scale
			light.shadow_enabled = medium_cast_shadows
			light.shadow_filter = Light2D.SHADOW_FILTER_PCF13 if use_pcf13_shadows else Light2D.SHADOW_FILTER_PCF5
			light.shadow_filter_smooth = medium_shadow_filter_smooth
			light.shadow_color = Color(0.0, 0.0, 0.0, medium_shadow_alpha)
		LightLayer.HALO:
			light.enabled = halo_enabled
			light.color = halo_color
			light.texture = _build_radial_texture(
				Color(1.0, 0.66, 0.39, 0.42),
				Color(1.0, 0.49, 0.28, 0.14),
				Color(1.0, 0.35, 0.22, 0.0)
			)
			light.energy = halo_base_energy
			light.texture_scale = halo_base_scale
			light.shadow_enabled = false
			light.shadow_filter = Light2D.SHADOW_FILTER_NONE
			light.shadow_filter_smooth = 0.0

	_apply_parent_scale_compensation(light)


func _build_radial_texture(center_color: Color, mid_color: Color, outer_color: Color) -> Texture2D:
	var cache_key := _make_radial_texture_cache_key(center_color, mid_color, outer_color)
	if _radial_texture_cache.has(cache_key):
		return _radial_texture_cache[cache_key] as Texture2D

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.2, 0.58, 1.0])
	gradient.colors = PackedColorArray([
		center_color,
		center_color.lerp(mid_color, 0.5),
		mid_color,
		outer_color,
	])

	var radial := GradientTexture2D.new()
	radial.gradient = gradient
	radial.fill = GradientTexture2D.FILL_RADIAL
	radial.fill_from = Vector2(0.5, 0.5)
	radial.fill_to = Vector2(1.0, 0.5)
	radial.width = radial_texture_size
	radial.height = radial_texture_size

	if edge_noise_strength <= 0.001:
		_radial_texture_cache[cache_key] = radial
		return radial

	var image := radial.get_image()
	if image == null:
		_radial_texture_cache[cache_key] = radial
		return radial

	var image_width := image.get_width()
	var image_height := image.get_height()
	for y in range(image_height):
		for x in range(image_width):
			var uv := Vector2(float(x) / float(image_width), float(y) / float(image_height))
			var dist := uv.distance_to(Vector2(0.5, 0.5)) * 2.0
			if dist < 0.52:
				continue
			var edge_mix := _smoothstep(0.52, 1.0, dist)
			var grain := _value_noise(uv * edge_noise_scale + Vector2(11.3, 19.7))
			var pixel := image.get_pixel(x, y)
			pixel.a = clampf(pixel.a - edge_mix * grain * edge_noise_strength, 0.0, 1.0)
			image.set_pixel(x, y, pixel)
	var texture := ImageTexture.create_from_image(image)
	_radial_texture_cache[cache_key] = texture
	return texture


func _make_radial_texture_cache_key(center_color: Color, mid_color: Color, outer_color: Color) -> String:
	return "%s|%s|%s|%d|%.3f|%.3f" % [
		str(center_color),
		str(mid_color),
		str(outer_color),
		radial_texture_size,
		edge_noise_strength,
		edge_noise_scale
	]


func _apply_flicker(light: PointLight2D, base_energy: float, energy_variation: float, base_scale: float, scale_variation: float, pulse: float, lod_strength: float) -> void:
	if light == null:
		return
	var target_energy := base_energy + (pulse - 0.5) * 2.0 * energy_variation
	var target_scale := base_scale + (pulse - 0.5) * 2.0 * scale_variation
	light.energy = target_energy * _time_of_day_energy_multiplier * lod_strength
	light.texture_scale = target_scale * _time_of_day_scale_multiplier


func _apply_parent_scale_compensation(light: PointLight2D) -> void:
	if light == null:
		return
	var parent := light.get_parent() as Node2D
	if parent == null:
		return

	var parent_scale := parent.global_scale
	var inverse_scale := Vector2(
		1.0 / maxf(absf(parent_scale.x), 0.001),
		1.0 / maxf(absf(parent_scale.y), 0.001)
	)
	light.scale = inverse_scale


func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	var t := clampf((value - edge0) / maxf(edge1 - edge0, 0.00001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _value_noise(point: Vector2) -> float:
	var i := Vector2(floor(point.x), floor(point.y))
	var f := point - i

	var a := _hash(i)
	var b := _hash(i + Vector2(1.0, 0.0))
	var c := _hash(i + Vector2(0.0, 1.0))
	var d := _hash(i + Vector2(1.0, 1.0))

	var ux := f.x * f.x * (3.0 - 2.0 * f.x)
	var uy := f.y * f.y * (3.0 - 2.0 * f.y)

	var x1 := lerpf(a, b, ux)
	var x2 := lerpf(c, d, ux)
	return lerpf(x1, x2, uy)


func _hash(point: Vector2) -> float:
	var value := sin(point.dot(Vector2(127.1, 311.7))) * 43758.5453
	return value - floor(value)


func _resolve_time_of_day_manager() -> Node:
	if not time_of_day_manager_path.is_empty():
		return get_node_or_null(time_of_day_manager_path)
	return get_tree().get_first_node_in_group("time_of_day_manager")


func _update_time_of_day_response(delta: float) -> void:
	if _time_of_day_manager == null or not is_instance_valid(_time_of_day_manager):
		_time_of_day_manager = _resolve_time_of_day_manager()
	if _time_of_day_manager == null:
		_time_of_day_energy_multiplier = _approach_multiplier(_time_of_day_energy_multiplier, 1.0, delta)
		_time_of_day_scale_multiplier = _approach_multiplier(_time_of_day_scale_multiplier, 1.0, delta)
		return

	var target_energy_multiplier := 1.0
	if _time_of_day_manager.has_method("get_phase_weighted_scalar"):
		target_energy_multiplier = float(_time_of_day_manager.call(
			"get_phase_weighted_scalar",
			dawn_energy_multiplier,
			day_energy_multiplier,
			dusk_energy_multiplier,
			night_energy_multiplier
		))

	var target_scale_multiplier := 1.0
	if _time_of_day_manager.has_method("get_phase_weighted_scalar"):
		target_scale_multiplier = float(_time_of_day_manager.call(
			"get_phase_weighted_scalar",
			dawn_scale_multiplier,
			day_scale_multiplier,
			dusk_scale_multiplier,
			night_scale_multiplier
		))

	_time_of_day_energy_multiplier = _approach_multiplier(_time_of_day_energy_multiplier, target_energy_multiplier, delta)
	_time_of_day_scale_multiplier = _approach_multiplier(_time_of_day_scale_multiplier, target_scale_multiplier, delta)


func _approach_multiplier(current_value: float, target_value: float, delta: float) -> float:
	var weight := 1.0 - exp(-maxf(delta, 0.0) * maxf(time_of_day_response_speed, 0.001))
	return lerpf(current_value, target_value, weight)

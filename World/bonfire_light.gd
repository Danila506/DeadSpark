extends AnimatedSprite2D
class_name CampfireLightController

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
@export var medium_base_energy: float = 0.55
@export var medium_energy_variation: float = 0.05
@export var medium_base_scale: float = 5.2
@export var medium_scale_variation: float = 0.22
@export var medium_color: Color = Color(1.0, 0.62, 0.35, 0.92)

@export_group("Halo Light")
@export var halo_base_energy: float = 0.24
@export var halo_energy_variation: float = 0.025
@export var halo_base_scale: float = 6.9
@export var halo_scale_variation: float = 0.16
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
@export_range(0.0, 0.35, 0.01) var edge_noise_strength: float = 0.12
@export_range(8.0, 128.0, 1.0) var edge_noise_scale: float = 34.0

@export_group("Flicker")
@export var flicker_speed: float = 3.6
@export var flicker_secondary_speed: float = 6.1

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

var _core_light: PointLight2D
var _medium_light: PointLight2D
var _halo_light: PointLight2D
var _phase: float = 0.0
var _time_of_day_manager: Node = null
var _time_of_day_energy_multiplier: float = 1.0
var _time_of_day_scale_multiplier: float = 1.0


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


func _process(delta: float) -> void:
	if _core_light == null and _medium_light == null and _halo_light == null:
		return

	_update_time_of_day_response(delta)
	_phase += delta * maxf(flicker_speed, 0.1)
	var speed_ratio := flicker_secondary_speed / maxf(flicker_speed, 0.1)
	var primary := sin(_phase) * 0.62
	var secondary := sin(_phase * speed_ratio + 1.17) * 0.38
	var pulse := clampf(0.5 + (primary + secondary) * 0.5, 0.0, 1.0)

	_apply_flicker(_core_light, core_base_energy, core_energy_variation, core_base_scale, core_scale_variation, clampf(0.52 + pulse * 0.65, 0.0, 1.0))
	_apply_flicker(_medium_light, medium_base_energy, medium_energy_variation, medium_base_scale, medium_scale_variation, clampf(0.47 + pulse * 0.72, 0.0, 1.0))
	_apply_flicker(_halo_light, halo_base_energy, halo_energy_variation, halo_base_scale, halo_scale_variation, clampf(0.45 + pulse * 0.56, 0.0, 1.0))

	_apply_parent_scale_compensation(_core_light)
	_apply_parent_scale_compensation(_medium_light)
	_apply_parent_scale_compensation(_halo_light)


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


func _apply_flicker(light: PointLight2D, base_energy: float, energy_variation: float, base_scale: float, scale_variation: float, pulse: float) -> void:
	if light == null:
		return
	var target_energy := base_energy + (pulse - 0.5) * 2.0 * energy_variation
	var target_scale := base_scale + (pulse - 0.5) * 2.0 * scale_variation
	light.energy = target_energy * _time_of_day_energy_multiplier
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

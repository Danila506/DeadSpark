extends AnimatedSprite2D
class_name CampfireLightController

enum LightLayer {
	CORE,
	MEDIUM,
	HALO,
}

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

var _core_light: PointLight2D
var _medium_light: PointLight2D
var _halo_light: PointLight2D
var _phase: float = 0.0


func _ready() -> void:
	_phase = randf_range(0.0, TAU)
	_core_light = _resolve_light(core_light_path, 0)
	_medium_light = _resolve_light(medium_light_path, 1)
	_halo_light = _resolve_light(halo_light_path, 2)

	_setup_light(_core_light, LightLayer.CORE)
	_setup_light(_medium_light, LightLayer.MEDIUM)
	_setup_light(_halo_light, LightLayer.HALO)

	if sprite_frames != null and sprite_frames.has_animation(campfire_animation):
		play(campfire_animation)


func _process(delta: float) -> void:
	if _core_light == null and _medium_light == null and _halo_light == null:
		return

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
		return radial

	var image := radial.get_image()
	if image == null:
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
	return ImageTexture.create_from_image(image)


func _apply_flicker(light: PointLight2D, base_energy: float, energy_variation: float, base_scale: float, scale_variation: float, pulse: float) -> void:
	if light == null:
		return
	light.energy = base_energy + (pulse - 0.5) * 2.0 * energy_variation
	light.texture_scale = base_scale + (pulse - 0.5) * 2.0 * scale_variation


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

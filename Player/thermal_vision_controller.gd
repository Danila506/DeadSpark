extends Node
class_name ThermalVisionController

const THERMAL_SHADER: Shader = preload("res://Player/thermal_vision.gdshader")
const TARGET_HEAT_SHADER: Shader = preload("res://Player/thermal_target_white_hot.gdshader")

@export_range(0.0, 1.0, 0.01) var target_intensity: float = 0.90
@export_range(0.1, 20.0, 0.1) var fade_speed: float = 8.0
@export var effect_layer: int = 0
@export var target_groups: Array[StringName] = [&"enemy"]
@export var target_refresh_interval_sec: float = 0.08

var _canvas_layer: CanvasLayer = null
var _overlay: ColorRect = null
var _material: ShaderMaterial = null
var _target_material: ShaderMaterial = null
var _enabled: bool = false
var _current_intensity: float = 0.0
var _time_sec: float = 0.0
var _target_refresh_left: float = 0.0
var _original_sprite_materials: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_overlay()
	set_thermal_enabled(_enabled, true)


func _process(delta: float) -> void:
	if _material == null:
		return

	_time_sec += maxf(delta, 0.0)
	_target_refresh_left = maxf(_target_refresh_left - maxf(delta, 0.0), 0.0)
	var desired_intensity: float = target_intensity if _enabled else 0.0
	_current_intensity = move_toward(_current_intensity, desired_intensity, fade_speed * maxf(delta, 0.0))
	_material.set_shader_parameter("intensity", _current_intensity)
	_material.set_shader_parameter("time_sec", _time_sec)
	if _target_material != null:
		_target_material.set_shader_parameter("intensity", clampf(_current_intensity / maxf(target_intensity, 0.001), 0.0, 1.0))
	if _target_refresh_left <= 0.0 or (_current_intensity <= 0.001 and not _enabled):
		_target_refresh_left = maxf(target_refresh_interval_sec, 0.01)
		_update_target_highlight()

	if _canvas_layer != null:
		_canvas_layer.visible = _current_intensity > 0.001 or _enabled


func set_thermal_enabled(enabled: bool, immediate: bool = false) -> void:
	_enabled = enabled
	if immediate:
		_current_intensity = target_intensity if _enabled else 0.0
		if _material != null:
			_material.set_shader_parameter("intensity", _current_intensity)
		if _target_material != null:
			_target_material.set_shader_parameter("intensity", clampf(_current_intensity / maxf(target_intensity, 0.001), 0.0, 1.0))
		_update_target_highlight()
	if _canvas_layer != null:
		_canvas_layer.visible = _current_intensity > 0.001 or _enabled


func is_thermal_enabled() -> bool:
	return _enabled


func _create_overlay() -> void:
	if _canvas_layer != null:
		return

	_canvas_layer = CanvasLayer.new()
	_canvas_layer.name = "ThermalVisionLayer"
	_canvas_layer.layer = effect_layer
	add_child(_canvas_layer)

	_overlay = ColorRect.new()
	_overlay.name = "ThermalVisionOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.offset_left = 0.0
	_overlay.offset_top = 0.0
	_overlay.offset_right = 0.0
	_overlay.offset_bottom = 0.0

	_material = ShaderMaterial.new()
	_material.shader = THERMAL_SHADER
	_material.set_shader_parameter("intensity", _current_intensity)
	_material.set_shader_parameter("pixel_size", 2.0)
	_material.set_shader_parameter("contrast", 1.08)
	_material.set_shader_parameter("brightness_bias", 0.10)
	_material.set_shader_parameter("noise_amount", 0.014)
	_material.set_shader_parameter("scanline_strength", 0.030)
	_material.set_shader_parameter("jitter_strength", 0.00055)
	_material.set_shader_parameter("vignette_strength", 0.08)
	_material.set_shader_parameter("cold_visibility", 0.58)
	_material.set_shader_parameter("white_hot_threshold", 0.88)
	_overlay.material = _material

	_canvas_layer.add_child(_overlay)

	_target_material = ShaderMaterial.new()
	_target_material.shader = TARGET_HEAT_SHADER
	_target_material.set_shader_parameter("intensity", 0.0)


func _update_target_highlight() -> void:
	if _target_material == null:
		return

	if _current_intensity <= 0.001 and not _enabled:
		_restore_all_target_materials()
		return

	var active_sprites: Dictionary = {}
	for target in _collect_living_targets():
		for sprite in _collect_target_sprites(target):
			active_sprites[sprite.get_instance_id()] = true
			if not _original_sprite_materials.has(sprite.get_instance_id()):
				_original_sprite_materials[sprite.get_instance_id()] = sprite.material
			sprite.material = _target_material

	for sprite_id in _original_sprite_materials.keys().duplicate():
		if active_sprites.has(sprite_id):
			continue
		_restore_sprite_material(int(sprite_id))


func _restore_all_target_materials() -> void:
	for sprite_id in _original_sprite_materials.keys().duplicate():
		_restore_sprite_material(int(sprite_id))


func _restore_sprite_material(sprite_id: int) -> void:
	var sprite: CanvasItem = instance_from_id(sprite_id) as CanvasItem
	if sprite != null and is_instance_valid(sprite):
		sprite.material = _original_sprite_materials.get(sprite_id, null)
	_original_sprite_materials.erase(sprite_id)


func _collect_living_targets() -> Array[Node2D]:
	var result: Array[Node2D] = []
	var seen: Dictionary = {}
	var tree: SceneTree = get_tree()
	if tree == null:
		return result

	for group_name in target_groups:
		for node in tree.get_nodes_in_group(group_name):
			if not (node is Node2D):
				continue
			if seen.has(node):
				continue
			if _is_target_dead(node):
				continue
			seen[node] = true
			result.append(node as Node2D)

	return result


func _collect_target_sprites(target: Node) -> Array[CanvasItem]:
	var result: Array[CanvasItem] = []
	_collect_target_sprites_recursive(target, result)
	return result


func _collect_target_sprites_recursive(node: Node, result: Array[CanvasItem]) -> void:
	for child in node.get_children():
		if child is AnimatedSprite2D or child is Sprite2D:
			var canvas_item: CanvasItem = child as CanvasItem
			if canvas_item.visible:
				result.append(canvas_item)
		_collect_target_sprites_recursive(child, result)


func _is_target_dead(target: Node) -> bool:
	if target.has_method("is_dead"):
		var dead_result: Variant = target.call("is_dead")
		if typeof(dead_result) == TYPE_BOOL:
			return bool(dead_result)
	var public_dead_value: Variant = target.get("is_dead")
	if typeof(public_dead_value) == TYPE_BOOL:
		return bool(public_dead_value)
	var private_dead_value: Variant = target.get("_is_dead")
	if typeof(private_dead_value) == TYPE_BOOL:
		return bool(private_dead_value)
	return false

extends RefCounted
class_name PlayerDamageFeedbackController

var player
var overlay_layer: CanvasLayer = null
var flash_rect: ColorRect = null
var time_left: float = 0.0
var peak_alpha: float = 0.0


func _init(owner) -> void:
	player = owner


func play(damage_amount: float) -> void:
	if player == null or damage_amount <= 0.0:
		return
	if player.has_method("_is_local_control_enabled") and not bool(player.call("_is_local_control_enabled")):
		return
	_ensure_overlay()
	if flash_rect == null:
		return
	var damage_ratio: float = clampf(damage_amount / maxf(player.max_health, 1.0), 0.0, 1.0)
	peak_alpha = clampf(
		player.damage_flash_base_alpha + damage_ratio * player.damage_flash_damage_alpha_scale,
		0.0,
		player.damage_flash_max_alpha
	)
	time_left = maxf(player.damage_flash_duration_sec, 0.05)
	overlay_layer.visible = true
	flash_rect.color = player.damage_flash_color
	flash_rect.modulate.a = peak_alpha


func update(delta: float) -> void:
	if flash_rect == null or time_left <= 0.0:
		return
	time_left = maxf(time_left - maxf(delta, 0.0), 0.0)
	var duration: float = maxf(player.damage_flash_duration_sec, 0.05)
	var fade_ratio: float = clampf(time_left / duration, 0.0, 1.0)
	flash_rect.modulate.a = peak_alpha * fade_ratio * fade_ratio
	if time_left <= 0.0:
		flash_rect.modulate.a = 0.0
		overlay_layer.visible = false


func _ensure_overlay() -> void:
	if overlay_layer != null and is_instance_valid(overlay_layer):
		return
	overlay_layer = CanvasLayer.new()
	overlay_layer.name = "DamageFeedbackLayer"
	overlay_layer.layer = 95
	overlay_layer.visible = false
	player.add_child(overlay_layer)

	flash_rect = ColorRect.new()
	flash_rect.name = "DamageFlash"
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.color = player.damage_flash_color
	flash_rect.modulate.a = 0.0
	overlay_layer.add_child(flash_rect)

extends Node2D

const PLAYER_SCENE := preload("res://Player/player.tscn")
const GUI_SCENE := preload("res://gui/GUI.tscn")

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var gui := GUI_SCENE.instantiate()
	gui.name = "UI"
	add_child(gui)
	var players := Node2D.new()
	players.name = "Players"
	add_child(players)
	var player := PLAYER_SCENE.instantiate()
	players.add_child(player)
	player.set_physics_process(false)
	await get_tree().process_frame

	var health_before: float = player.health
	player.take_damage(5.0, ItemData.DamageType.GENERIC, false)
	_check(player.health < health_before, "test hit did not reduce health")
	var feedback_layer := player.get_node_or_null("DamageFeedbackLayer") as CanvasLayer
	var flash := player.get_node_or_null("DamageFeedbackLayer/DamageFlash") as ColorRect
	_check(feedback_layer != null and feedback_layer.visible, "damage feedback layer did not appear")
	_check(flash != null and flash.modulate.a > 0.0, "damage flash is transparent")
	if player.damage_feedback_controller != null:
		player.damage_feedback_controller.update(player.damage_flash_duration_sec + 0.01)
	_check(feedback_layer != null and not feedback_layer.visible, "damage flash did not finish")

	player.health = 100.0
	player._apply_network_vitals_payload({"hp": 9500})
	_check(feedback_layer != null and feedback_layer.visible, "authoritative LAN health loss did not trigger feedback")

	for failure in failures:
		push_error(failure)
	print("PLAYER_DAMAGE_FEEDBACK_TEST=" + ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

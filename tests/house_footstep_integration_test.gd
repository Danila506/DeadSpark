extends Node2D

const PLAYER_SCENE := preload("res://Player/player.tscn")
const GUI_SCENE := preload("res://gui/GUI.tscn")
const HOUSE_SCENE := preload("res://World/Assets/Houses/House1/house_1.tscn")

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var gui := GUI_SCENE.instantiate()
	gui.name = "UI"
	add_child(gui)

	var world := Node2D.new()
	world.name = "Y-Sort_Objects"
	add_child(world)

	var house := HOUSE_SCENE.instantiate()
	house.world_generated_mode = true
	world.add_child(house)

	var actor := PLAYER_SCENE.instantiate()
	var house_shape := house.get_node("HouseArea/CollisionShape2D") as CollisionShape2D
	actor.position = Vector2(300.0, 300.0)
	world.add_child(actor)
	actor.set_physics_process(false)

	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not actor.is_in_group("inside_house"), "player must begin outside the real HouseArea")
	actor.global_position = house_shape.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(actor.is_in_group("inside_house"), "real HouseArea must mark the player as indoors")

	var sounds_bus_index := AudioServer.get_bus_index(&"Sounds")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	var capture_effect_index := AudioServer.get_bus_effect_count(sounds_bus_index)
	AudioServer.add_bus_effect(sounds_bus_index, capture, capture_effect_index)

	actor.velocity = Vector2.RIGHT * actor.base_move_speed
	actor._update_walk_snow_sfx(Vector2.RIGHT, 0.1)
	_check(actor.walk_snow_sfx != null and actor.walk_snow_sfx.playing, "real indoor player must start the footstep player")
	_check(actor.walk_snow_sfx.stream == actor.WALK_HOUSE_STREAM, "real indoor player must replace snow with the house stream")
	_check(actor.walk_snow_sfx.volume_db >= 0.0, "real indoor house stream must be audible")
	var house_wav := actor.walk_snow_sfx.stream as AudioStreamWAV
	_check(house_wav != null and house_wav.loop_end > house_wav.loop_begin, "house WAV must have a valid non-empty loop range")
	for frame_index in range(45):
		actor.velocity = Vector2.RIGHT * actor.base_move_speed
		actor._update_walk_snow_sfx(Vector2.RIGHT, 1.0 / 60.0)
		_check(actor.walk_snow_sfx.stream == actor.WALK_HOUSE_STREAM, "house stream must remain stable instead of restarting every frame")
		await get_tree().process_frame
	var available_frames := capture.get_frames_available()
	var captured_peak := 0.0
	if available_frames > 0:
		for frame in capture.get_buffer(available_frames):
			captured_peak = maxf(captured_peak, maxf(absf(frame.x), absf(frame.y)))
	AudioServer.remove_bus_effect(sounds_bus_index, capture_effect_index)
	_check(available_frames > 0, "Sounds bus must produce captured audio frames")
	_check(captured_peak > 0.001, "indoor footstep stream must produce non-silent samples")
	_check(actor.walk_snow_sfx.playing and actor.walk_snow_sfx.get_playback_position() > 0.0, "house footsteps must remain playing after the audio server advances")

	actor.global_position = Vector2(300.0, 300.0)
	actor.force_update_transform()
	PhysicsServer2D.body_set_state(actor.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, actor.global_transform)
	actor.set_physics_process(true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("HOUSE_EXIT_DIAG actor=%s area=%s overlaps=%s" % [actor.global_position, house.get_node("HouseArea").global_position, house.get_node("HouseArea").get_overlapping_bodies().map(func(body): return body.name)])
	_check(not actor.is_in_group("inside_house"), "real HouseArea must clear the indoor state on exit")
	actor.velocity = Vector2.RIGHT * actor.base_move_speed
	actor._update_walk_snow_sfx(Vector2.RIGHT, 0.1)
	_check(actor.walk_snow_sfx.stream == actor.WALK_SNOW_STREAM and actor.walk_snow_sfx.playing, "snow footsteps must resume after leaving the house")

	for failure in failures:
		push_error(failure)
	print("HOUSE_FOOTSTEP_INTEGRATION_TEST=" + ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)

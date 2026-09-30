extends Node

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var snowfall := get_node("Snowfall")

	var player := snowfall.get_node_or_null("StormAmbience") as AudioStreamPlayer
	_check(player != null, "storm ambience player is created", failures)
	if player != null:
		_check(player.bus == &"Sounds", "storm ambience uses the Sounds bus", failures)
		_check(player.stream is AudioStreamMP3, "snowstorm MP3 is assigned", failures)
		if player.stream is AudioStreamMP3:
			_check((player.stream as AudioStreamMP3).loop, "snowstorm MP3 loops", failures)
		# The dummy headless audio driver retains decoded MP3 playback until exit.
		# Volume/fade behavior does not require starting the decoder.
		player.stream = null

	snowfall.call("set_storm_intensity", 0.5)
	for index in 30:
		snowfall.call("_update_storm_audio", 0.1)
	if player != null:
		var expected_half_volume_db: float = -10.0 + linear_to_db(0.5)
		_check(
			absf(player.volume_db - expected_half_volume_db) < 0.1,
			"storm intensity controls ambience volume",
			failures
		)

	snowfall.call("set_storm_intensity", 0.0)
	for index in 50:
		snowfall.call("_update_storm_audio", 0.1)
	if player != null:
		_check(not player.playing, "storm ambience stops after fade-out", failures)
		_check(float(snowfall.get("_storm_audio_gain")) <= 0.0001, "storm fade reaches silence", failures)

	if player != null:
		player.stop()
		player.stream = null
	await get_tree().process_frame
	await get_tree().process_frame
	if not failures.is_empty():
		for failure in failures:
			push_error("Snowstorm audio: " + failure)
		get_tree().quit(1)
		return
	print("SNOWSTORM_AUDIO_TEST=PASS")
	get_tree().quit(0)


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)

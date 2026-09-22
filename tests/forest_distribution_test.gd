extends "res://tests/forest_preview_capture.gd"

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run_distribution")

func _check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _run_distribution() -> void:
	for seed_value in [1337, 42, 2026]:
		world_seed = seed_value
		generate_full_world()
		_check(_environment.blocking_errors.is_empty(), "generation failed")
		var positions := {}
		var distinct_x := {}
		var distinct_y := {}
		for item in _environment.accepted:
			if item.category != "trees": continue
			var point: Vector2 = item.position
			positions[item.generated_id] = point
			distinct_x[point.x] = true
			distinct_y[point.y] = true
			_check(Vector2i((point / _environment.profile.logical_cell_size).floor()) == item.cell, "tree escaped reserved cell")
		_check(positions.size() > 0, "no trees")
		_check(distinct_x.size() > positions.size() * 0.95, "horizontal grid alignment")
		_check(distinct_y.size() > positions.size() * 0.95, "vertical grid alignment")
		_environment._reverse_chunk_enumeration_for_test = true
		_environment.run_generation_pass()
		for item in _environment.accepted:
			if item.category == "trees": _check(positions.get(item.generated_id) == item.position, "position changed on regeneration")
		# Compare with the previous production spacing and per-chunk limits.
		_environment.profile = _environment.profile.duplicate(true)
		for entry in _environment.profile.entries:
			if entry.category != "trees": continue
			entry.footprint_size = Vector2i(2, 2)
			entry.position_jitter_cells = 0.0
			entry.max_instances_per_chunk = 20 if entry.entry_id == "biom2_tree" else 24
			entry.candidate_budget_per_chunk = 64 if entry.entry_id.begins_with("biom") else 80
		_environment.run_generation_pass()
		var previous_count := 0
		for item in _environment.accepted:
			if item.category == "trees": previous_count += 1
		_check(positions.size() > previous_count * 2, "forest not substantially denser")
		print("FOREST_DENSITY seed=%d old=%d new=%d" % [seed_value, previous_count, positions.size()])
	for failure in failures: push_error(failure)
	print("FOREST_DISTRIBUTION_TEST=" + ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)

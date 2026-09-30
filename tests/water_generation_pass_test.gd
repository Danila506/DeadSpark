extends Node

const PASS_SCRIPT := preload("res://World/Generation/water_generation_pass.gd")
const PROFILE := preload("res://Resources/WorldGen/water_generation_profile.tres")
const BOUNDS := Rect2i(Vector2i(-48, -48), Vector2i(96, 96))
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

var _failed := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var generator := PASS_SCRIPT.new() as WaterGenerationPass
	generator.profile = PROFILE
	var hashes: Array[String] = []
	for seed in [42, 1337, 2026, 7331, 99999]:
		var first: Dictionary = generator.build_cells_for_inputs(BOUNDS, seed)
		var second: Dictionary = generator.build_cells_for_inputs(BOUNDS, seed)
		_assert(GenerationHashes.sha256_of(first) == GenerationHashes.sha256_of(second), "same seed must be deterministic")
		_assert(first.components.size() >= PROFILE.min_lakes and first.components.size() <= PROFILE.max_lakes, "lake count follows profile")
		for component in first.components:
			_assert(component.size() >= PROFILE.minimum_lake_cells, "lake is not a tiny fragment")
			_assert(_is_connected(component), "each lake is cardinally connected")
			for cell in component:
				_assert(BOUNDS.grow(-PROFILE.border_margin_cells).has_point(cell), "lake stays inside safe world margin")
		hashes.append(GenerationHashes.sha256_of(first.cells))
	_assert(_unique_count(hashes) > 1, "different seeds should vary lake geometry")
	var excluded := {}
	for y in range(-8, 9):
		for x in range(-8, 9): excluded[Vector2i(x, y)] = true
	var protected: Dictionary = generator.build_cells_for_inputs(BOUNDS, 1337, excluded)
	for cell in protected.cells: _assert(not excluded.has(cell), "lake respects protected spawn cells")
	generator.free()
	if _failed:
		get_tree().quit(1)
	else:
		print("WATER_GENERATION_PASS_TEST=PASS hashes=%s" % JSON.stringify(hashes))
		get_tree().quit(0)


func _is_connected(cells: Array) -> bool:
	if cells.is_empty(): return false
	var available := {}
	for cell in cells: available[cell] = true
	var queue: Array[Vector2i] = [cells[0] as Vector2i]
	var visited := {queue[0]: true}
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		for direction in DIRECTIONS:
			var next: Vector2i = current + direction
			if available.has(next) and not visited.has(next):
				visited[next] = true
				queue.append(next)
	return visited.size() == available.size()


func _unique_count(values: Array[String]) -> int:
	var unique := {}
	for value in values: unique[value] = true
	return unique.size()


func _assert(condition: bool, message: String) -> void:
	if condition: return
	_failed = true
	push_error("Water generation pass: " + message)

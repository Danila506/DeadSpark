class_name WaterGenerationProfile
extends Resource

@export var stable_id := "water_v1_default"
@export var revision := 1
@export var seed_domain := "water/v1"
@export_range(0, 8, 1) var min_lakes := 1
@export_range(0, 8, 1) var max_lakes := 2
@export_range(2, 32, 1) var border_margin_cells := 8
@export_range(2, 32, 1) var radius_min_cells := 5
@export_range(2, 48, 1) var radius_max_cells := 11
@export_range(0, 6, 1) var extra_lobes_min := 1
@export_range(0, 6, 1) var extra_lobes_max := 3
@export_range(0.0, 0.45, 0.01) var edge_jitter := 0.12
@export_range(0, 32, 1) var lake_spacing_cells := 8
@export_range(0, 32, 1) var player_clearance_cells := 7
@export_range(1, 128, 1) var placement_attempts_per_lake := 24
@export_range(8, 4096, 1) var minimum_lake_cells := 48
@export_range(0, 8, 1) var terrain_set_id := 0
@export_range(0, 32, 1) var terrain_id := 0
@export var terrain_ignore_empty := false


func validate() -> Dictionary:
	var errors: Array[String] = []
	if stable_id.is_empty(): errors.append("EMPTY_STABLE_ID")
	if min_lakes > max_lakes: errors.append("INVALID_LAKE_COUNT_RANGE")
	if radius_min_cells > radius_max_cells: errors.append("INVALID_RADIUS_RANGE")
	if extra_lobes_min > extra_lobes_max: errors.append("INVALID_LOBE_RANGE")
	if border_margin_cells <= radius_max_cells: errors.append("BORDER_MARGIN_MUST_EXCEED_MAX_RADIUS")
	return {"valid": errors.is_empty(), "errors": errors}


func compatibility_profile() -> Dictionary:
	return {
		"id": "water_profile:%s" % stable_id,
		"revision": revision,
		"seed_domain": seed_domain,
		"lake_count": [min_lakes, max_lakes],
		"border_margin_cells": border_margin_cells,
		"radius_cells": [radius_min_cells, radius_max_cells],
		"extra_lobes": [extra_lobes_min, extra_lobes_max],
		"edge_jitter": edge_jitter,
		"lake_spacing_cells": lake_spacing_cells,
		"player_clearance_cells": player_clearance_cells,
		"placement_attempts_per_lake": placement_attempts_per_lake,
		"minimum_lake_cells": minimum_lake_cells,
		"terrain": {
			"set": terrain_set_id,
			"id": terrain_id,
			"ignore_empty": terrain_ignore_empty
		}
	}

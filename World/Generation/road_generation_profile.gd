class_name RoadGenerationProfile
extends Resource

@export var stable_id := "road_v1_default"
@export var revision := 7
@export var road_seed_domain := "roads/v3_irregular_village_loop"
@export_range(0, 4, 1) var water_clearance_cells := 0
@export_range(2, 8, 1) var minimum_village_count := 2
@export_range(2, 16, 1) var village_connector_spacing_cells := 5
@export_range(1, 8, 1) var village_footprint_half_width_cells := 2
@export_range(1, 8, 1) var village_footprint_depth_cells := 5
@export_range(1, 8, 1) var loop_side_inset_cells := 2
@export_range(2, 12, 1) var loop_top_inset_cells := 5
@export_range(6, 64, 1) var loop_min_width_cells := 10
@export_range(4, 64, 1) var loop_min_height_cells := 6
@export_range(2, 4, 1) var primary_anchor_count := 2
@export_range(1, 32, 1) var boundary_margin_cells := 2
@export_range(2, 128, 1) var minimum_anchor_spacing_cells := 6
@export var primary_anchor_pair_modes: Array[String] = ["west:east", "north:south", "west:north", "west:south", "east:north", "east:south", "north:east", "south:west"]
@export_range(0, 8, 1) var min_primary_bends := 2
@export_range(0, 8, 1) var max_primary_bends := 4
@export_range(2, 48, 1) var min_segment_length := 2
@export_range(2, 64, 1) var max_segment_length := 36
@export_range(2, 48, 1) var turn_spacing := 2
@export_range(1, 32, 1) var max_route_attempts := 8
@export_range(0, 12, 1) var min_branches := 1
@export_range(0, 12, 1) var max_branches := 3
@export_range(1, 64, 1) var branch_attempts := 16
@export_range(2, 64, 1) var branch_length_min_cells := 2
@export_range(2, 64, 1) var branch_length_max_cells := 8
@export_range(1, 32, 1) var branch_junction_buffer_cells := 1
@export_range(1, 32, 1) var branch_border_buffer_cells := 1
@export_range(1, 32, 1) var branch_start_spacing_cells := 2
@export_range(64, 100000, 1) var max_route_search_cells := 24000
@export var source_id := 0
@export var vertical_atlas := Vector2i(0, 0)
@export var horizontal_atlas := Vector2i(0, 1)
@export var corner_up_left_atlas := Vector2i(3, 1)
@export var corner_up_right_atlas := Vector2i(2, 1)
@export var corner_down_left_atlas := Vector2i(1, 1)
@export var corner_down_right_atlas := Vector2i(4, 1)
@export var t_missing_up_atlas := Vector2i(5, 0)
@export var t_missing_down_atlas := Vector2i(2, 0)
@export var t_missing_left_atlas := Vector2i(4, 0)
@export var t_missing_right_atlas := Vector2i(3, 0)
@export var cross_atlas := Vector2i(1, 0)

func compatibility_profile() -> Dictionary:
	return {
		"id": "road_profile:%s" % stable_id,
		"revision": revision,
		"road_seed_domain": road_seed_domain,
		"water_clearance_cells": water_clearance_cells,
		"minimum_village_count": minimum_village_count,
		"village_connector_spacing_cells": village_connector_spacing_cells,
		"village_footprint_half_width_cells": village_footprint_half_width_cells,
		"village_footprint_depth_cells": village_footprint_depth_cells,
		"loop_side_inset_cells": loop_side_inset_cells,
		"loop_top_inset_cells": loop_top_inset_cells,
		"loop_min_width_cells": loop_min_width_cells,
		"loop_min_height_cells": loop_min_height_cells,
		"primary_anchor_count": primary_anchor_count,
		"boundary_margin_cells": boundary_margin_cells,
		"minimum_anchor_spacing_cells": minimum_anchor_spacing_cells,
		"primary_anchor_pair_modes": primary_anchor_pair_modes,
		"min_primary_bends": min_primary_bends,
		"max_primary_bends": max_primary_bends,
		"min_segment_length": min_segment_length,
		"max_segment_length": max_segment_length,
		"turn_spacing": turn_spacing,
		"max_route_attempts": max_route_attempts,
		"min_branches": min_branches,
		"max_branches": max_branches,
		"branch_attempts": branch_attempts,
		"branch_length_min_cells": branch_length_min_cells,
		"branch_length_max_cells": branch_length_max_cells,
		"branch_junction_buffer_cells": branch_junction_buffer_cells,
		"branch_border_buffer_cells": branch_border_buffer_cells,
		"branch_start_spacing_cells": branch_start_spacing_cells,
		"max_route_search_cells": max_route_search_cells,
		"raster_palette": {
			"source_id": source_id, "vertical": vertical_atlas, "horizontal": horizontal_atlas,
			"corner_up_left": corner_up_left_atlas, "corner_up_right": corner_up_right_atlas,
			"corner_down_left": corner_down_left_atlas, "corner_down_right": corner_down_right_atlas,
			"t_missing_up": t_missing_up_atlas, "t_missing_down": t_missing_down_atlas,
			"t_missing_left": t_missing_left_atlas, "t_missing_right": t_missing_right_atlas,
			"cross": cross_atlas
		}
	}

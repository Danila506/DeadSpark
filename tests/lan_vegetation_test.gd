extends "res://tools/build_lan_vegetation.gd"

## Rebuild twice through EnvironmentGenerationPass, compare against the saved
## layer, require all four palettes and validate occupancy of every placement.
func _init() -> void:
	verify_only = true
	super._init()

func _validate_generated(pass_node: EnvironmentGenerationPass, layer: TileMapLayer, counts: Dictionary) -> bool:
	var shifted := 0
	var claimed := {}
	for placement in pass_node.accepted:
		var unshifted := layer.local_to_map((Vector2(placement.cell) + Vector2(0.5, 0.5)) * CELL)
		if placement.map_cell != unshifted: shifted += 1
		for cell in placement.footprint:
			if claimed.has(cell):
				push_error("Vegetation footprints overlap")
				return false
			claimed[cell] = true
	if shifted < pass_node.accepted.size() / 2:
		push_error("Vegetation anchors still follow the unshifted grid")
		return false
	if int(counts.get("01_lan_single_trees", 0)) < int(counts.get("00_lan_tree_clusters", 0)) * 2:
		push_error("Single trees should dominate the reference distribution")
		return false
	return true

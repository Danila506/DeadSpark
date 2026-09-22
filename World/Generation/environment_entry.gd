@tool
class_name EnvironmentEntry
extends Resource

enum Kind { SCENE, TILE }
const KNOWN_CATEGORIES := [&"biom1_static_tiles", &"biom2_static_tiles", &"xz_static_tiles", &"trees", &"bushes", &"puddles", &"stones", &"deadwood", &"berry_bushes", &"structures", &"containers", &"pickups"]

@export var entry_id := ""
@export var category := ""
@export var kind: Kind = Kind.SCENE
@export var target_path: NodePath
@export var scene: PackedScene
## Independent axis offset, as a fraction of the cell size. Keep the trunk inside its claim.
@export_range(0.0, 0.45, 0.01) var position_jitter_cells := 0.0
@export var source_id := 0
@export var atlas_coords := Vector2i.ZERO
## Optional authored palette; weights control relative frequency within it.
@export var atlas_variants: Array[Vector2i] = []
@export var atlas_variant_weights: Array[float] = []
@export_range(0.0, 1.0, 0.0001) var density := 0.01
@export_range(0, 512, 1) var max_instances := 16
@export_range(0, 512, 1) var candidate_budget := 64
## Per-finite-chunk limits. A zero value keeps the pre-v3 value as a migration
## fallback, so existing resources remain valid while no longer acting globally.
@export_range(0, 512, 1) var min_instances_per_chunk := 0
@export_range(0, 512, 1) var max_instances_per_chunk := 0
@export_range(0, 512, 1) var candidate_budget_per_chunk := 0
@export_range(0, 16, 1) var minimum_spacing_cells := 1
@export var footprint_size := Vector2i.ONE
@export var blocked_occupancy_mask := WorldOccupancyMap.ROAD | WorldOccupancyMap.ROAD_CLEARANCE | WorldOccupancyMap.WATER | WorldOccupancyMap.POI | WorldOccupancyMap.BUILDING | WorldOccupancyMap.RUIN | WorldOccupancyMap.NO_SPAWN
@export var occupancy_flags := WorldOccupancyMap.STATIC_PROP
@export var enabled := true
## Probability that this entry is considered in a chunk. Zero disables spawning.
@export_range(0.0, 1.0, 0.01) var chunk_spawn_probability := 1.0
## Zero means unlimited. Use Enabled to disable an entry.
@export_range(0, 512, 1) var max_instances_per_world := 0
## Offset of the reserved rectangle relative to the object's origin cell.
@export var footprint_offset := Vector2i.ZERO
## Optional deterministic contents for building providers.
@export var loot_profile: LootProfile
## When positive, restrict this entry to the vicinity of accepted structures.
@export_range(0.0, 64.0, 0.5) var near_structure_radius_cells := 0.0

func validate() -> Dictionary:
	var errors: Array[String] = []
	if entry_id.is_empty() or category.is_empty(): errors.append("MISSING_ENTRY_ID_OR_CATEGORY")
	if not category.is_empty() and not StringName(category) in KNOWN_CATEGORIES: errors.append("UNKNOWN_CATEGORY")
	if target_path.is_empty(): errors.append("MISSING_TARGET")
	if chunk_spawn_probability < 0.0 or chunk_spawn_probability > 1.0 or max_instances_per_world < 0 or near_structure_radius_cells < 0.0: errors.append("INVALID_SPAWN_FREQUENCY")
	if loot_profile != null and not bool(loot_profile.validate().valid): errors.append("INVALID_LOOT_PROFILE")
	if not atlas_variant_weights.is_empty():
		if atlas_variant_weights.size() != atlas_variants.size(): errors.append("INVALID_ATLAS_WEIGHTS")
		var total := 0.0
		for weight in atlas_variant_weights:
			if weight < 0.0 or not is_finite(weight): errors.append("INVALID_ATLAS_WEIGHTS")
			total += weight
		if total <= 0.0: errors.append("INVALID_ATLAS_WEIGHTS")
	var known_occupancy_flags := WorldOccupancyMap.ROAD | WorldOccupancyMap.ROAD_CLEARANCE | WorldOccupancyMap.WATER | WorldOccupancyMap.POI | WorldOccupancyMap.BUILDING | WorldOccupancyMap.RUIN | WorldOccupancyMap.STATIC_PROP | WorldOccupancyMap.INTERACTIVE_OBJECT | WorldOccupancyMap.NO_SPAWN
	if density < 0.0 or density > 1.0 or max_instances < 0 or candidate_budget <= 0 or min_instances_per_chunk < 0 or max_instances_per_chunk < 0 or candidate_budget_per_chunk < 0 or minimum_spacing_cells < 0 or footprint_size.x < 1 or footprint_size.y < 1: errors.append("INVALID_PROFILE")
	if min_instances_per_chunk > max_instances_per_chunk_value(): errors.append("INVALID_CHUNK_QUOTA")
	if min_instances_per_chunk > candidate_budget_per_chunk_value(): errors.append("INVALID_CHUNK_QUOTA")
	if blocked_occupancy_mask < 0 or blocked_occupancy_mask & ~known_occupancy_flags != 0 or occupancy_flags <= 0 or occupancy_flags & ~known_occupancy_flags != 0: errors.append("INVALID_OCCUPANCY_MASK")
	if not is_finite(position_jitter_cells) or position_jitter_cells < 0.0 or position_jitter_cells > 0.45: errors.append("INVALID_POSITION_JITTER")
	if kind == Kind.SCENE and scene == null: errors.append("MISSING_SCENE")
	return {"valid": errors.is_empty(), "errors": errors}

func fingerprint() -> Dictionary:
	return {"entry_id": entry_id, "category": category, "kind": kind, "target": target_path, "scene_uid": GenerationHashes.resource_uid(scene), "position_jitter_cells": position_jitter_cells, "source_id": source_id, "atlas": atlas_coords, "atlas_variants": atlas_variants, "atlas_weights": atlas_variant_weights, "density": density, "min_per_chunk": min_instances_per_chunk, "max_per_chunk": max_instances_per_chunk_value(), "budget_per_chunk": candidate_budget_per_chunk_value(), "spacing": minimum_spacing_cells, "footprint": footprint_size, "blocked": blocked_occupancy_mask, "flags": occupancy_flags, "enabled": enabled, "chunk_probability": chunk_spawn_probability, "near_structure_radius": near_structure_radius_cells, "max_per_world": max_instances_per_world, "footprint_offset": footprint_offset, "loot": loot_profile.canonical_record() if loot_profile != null else {}}

func max_instances_per_chunk_value() -> int:
	return max_instances_per_chunk if max_instances_per_chunk > 0 else max_instances

func candidate_budget_per_chunk_value() -> int:
	return candidate_budget_per_chunk if candidate_budget_per_chunk > 0 else candidate_budget

class_name WorldOccupancyMap
extends RefCounted

const ROAD := 1
const ROAD_CLEARANCE := 2
const WATER := 4
const POI := 8
const BUILDING := 16
const RUIN := 32
const STATIC_PROP := 64
const INTERACTIVE_OBJECT := 128
const NO_SPAWN := 256

var bounds := Rect2i()
var _claims_by_cell := {}
var _owners := {}

func reset(world_bounds: Rect2i) -> void:
	bounds = world_bounds
	_claims_by_cell.clear()
	_owners.clear()

func claim_cells(cells: Array[Vector2i], flags: int, owner_id: String, source: String) -> Dictionary:
	if owner_id.is_empty() or _owners.has(owner_id): return {"valid": false, "reason": "DUPLICATE_OWNER"}
	for cell in cells:
		if not bounds.has_point(cell): return {"valid": false, "reason": "OUT_OF_BOUNDS"}
	var claim := {"flags": flags, "owner_id": owner_id, "source": source, "cells": cells}
	_owners[owner_id] = claim
	for cell in cells:
		var existing: Array = _claims_by_cell.get(cell, [])
		existing.append(claim)
		_claims_by_cell[cell] = existing
	return {"valid": true}

func has_flags(cells: Array[Vector2i], forbidden_flags: int) -> bool:
	for cell in cells:
		for claim in _claims_by_cell.get(cell, []):
			if int((claim as Dictionary).get("flags", 0)) & forbidden_flags != 0: return true
	return false

func release_owner(owner_id: String) -> bool:
	if not _owners.has(owner_id): return false
	var claim: Dictionary = _owners[owner_id]
	for cell in claim.get("cells", []):
		var remaining: Array = []
		for existing in _claims_by_cell.get(cell, []):
			if String((existing as Dictionary).get("owner_id", "")) != owner_id: remaining.append(existing)
		if remaining.is_empty(): _claims_by_cell.erase(cell)
		else: _claims_by_cell[cell] = remaining
	_owners.erase(owner_id)
	return true

func canonical_manifest() -> Dictionary:
	var claims: Array[Dictionary] = []
	var ids: Array[String] = []
	for owner in _owners.keys(): ids.append(String(owner))
	ids.sort()
	for owner in ids: claims.append(_owners[owner] as Dictionary)
	return {"bounds": bounds, "claims": claims}

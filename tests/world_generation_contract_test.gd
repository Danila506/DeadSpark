extends SceneTree

const AUTHORED_GENERATION_VALIDATOR = preload("res://World/Generation/authored_generation_validator.gd")

func _init() -> void:
	var profile := {
		"id": "template:village_a",
		"marker": {
			"stable_id": "m_8f31c2",
			"local_position": Vector2(120.0, -60.0),
			"local_rotation": 0.0,
			"rotation_used": false
		},
		"pool": [{"entry_id": "house_1", "weight": 1.0, "unique": false}]
	}
	var compatibility := WorldGenerationContract.compatibility_hash([profile])
	var compatibility_same_content := WorldGenerationContract.compatibility_hash([profile])
	_assert(compatibility == compatibility_same_content, "compatibility hash must be stable")
	var bounds := {"min_chunk": Vector2i(-3, -3), "max_chunk": Vector2i(2, 2)}
	var manifest_a := WorldGenerationContract.world_manifest_hash(compatibility, 1337, bounds)
	var manifest_b := WorldGenerationContract.world_manifest_hash(compatibility, 7331, bounds)
	_assert(manifest_a != manifest_b, "different seeds must produce different manifest hashes")
	var output_a := WorldGenerationContract.generation_output_hash(manifest_a, [{"id": "terrain", "cells": [Vector2i(0, 0)]}])
	var output_b := WorldGenerationContract.generation_output_hash(manifest_a, [{"id": "terrain", "cells": [Vector2i(1, 0)]}])
	_assert(output_a != output_b, "different immutable outputs must produce different output hashes")
	var moved_profile := profile.duplicate(true)
	moved_profile["marker"]["local_position"] = Vector2(121.0, -60.0)
	_assert(compatibility != WorldGenerationContract.compatibility_hash([moved_profile]), "structural marker position must be compatibility-relevant")
	var invalid_markers: Dictionary = AUTHORED_GENERATION_VALIDATOR.validate_structural_markers([
		{"stable_id": "m_a", "local_position": Vector2.ZERO, "local_rotation": 0.0, "rotation_used": false},
		{"stable_id": "m_a", "local_position": Vector2.ONE, "local_rotation": 0.0, "rotation_used": false}
	])
	_assert(not bool(invalid_markers["valid"]), "duplicate authored IDs must be a blocking validation error")
	var vectors := WorldSeedService.get_test_vectors()
	_assert(vectors.size() == 4, "seed service vectors must be present")
	for vector in vectors:
		_assert(int(vector["derived_seed"]) == WorldSeedService.derive_seed(int(vector["master_seed"]), String(vector["domain"]), vector["coordinates"]), "seed vector must replay")
	print(JSON.stringify({
		"compatibility": compatibility,
		"manifest_1337": manifest_a,
		"manifest_7331": manifest_b,
		"output_a": output_a,
		"output_b": output_b,
		"seed_vectors": vectors
	}))
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)

class_name WorldSeedService
extends RefCounted

const SEED_SERVICE_VERSION := 1

static func derive_seed(master_seed: int, domain_key: String, coordinates: Array = []) -> int:
	var digest := GenerationHashes.sha256_of({
		"seed_service_version": SEED_SERVICE_VERSION,
		"master_seed": master_seed,
		"domain": domain_key,
		"coordinates": coordinates
	})
	# Fifteen hexadecimal digits fit into a signed 64-bit GDScript integer.
	return int("0x%s" % digest.substr(0, 15))


static func get_test_vectors() -> Array[Dictionary]:
	return [
		{"master_seed": 0, "domain": "terrain/base", "coordinates": [], "derived_seed": derive_seed(0, "terrain/base")},
		{"master_seed": 1337, "domain": "terrain/base", "coordinates": [0, 0], "derived_seed": derive_seed(1337, "terrain/base", [0, 0])},
		{"master_seed": 1337, "domain": "poi/village", "coordinates": [2, -1], "derived_seed": derive_seed(1337, "poi/village", [2, -1])},
		{"master_seed": 987654321, "domain": "environment/candidate", "coordinates": [-4, 9, 17], "derived_seed": derive_seed(987654321, "environment/candidate", [-4, 9, 17])}
	]

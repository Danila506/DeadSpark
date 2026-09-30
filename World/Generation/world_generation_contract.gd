class_name WorldGenerationContract
extends RefCounted

const GENERATION_VERSION := 3
const WORLD_PROFILE_ID := "legacy_finite_world"
const WORLD_PROFILE_REVISION := 2

static func compatibility_hash(pass_profiles: Array[Dictionary]) -> String:
	return GenerationHashes.sha256_of({
		"generation_version": GENERATION_VERSION,
		"passes": pass_profiles
	})


static func world_manifest_hash(compatibility: String, master_seed: int, finite_bounds: Dictionary) -> String:
	return GenerationHashes.sha256_of({
		"generation_compatibility_hash": compatibility,
		"master_seed": master_seed,
		"finite_bounds": finite_bounds,
		"world_profile_id": WORLD_PROFILE_ID,
		"world_profile_revision": WORLD_PROFILE_REVISION
	})


static func generation_output_hash(world_manifest: String, output_manifests: Array[Dictionary]) -> String:
	return GenerationHashes.sha256_of({
		"world_manifest_hash": world_manifest,
		"immutable_output": output_manifests
	})

extends Node

const BOX_SCENE = preload("res://World/Boxes/Box1/Box1.tscn")
const MED_SCRIPT = preload("res://World/medicine_kit.gd")
const ProviderContract = preload("res://World/Generation/loot_container_provider_contract.gd")
const BOX_PROFILE = preload("res://Resources/WorldGen/Loot/box_loot_profile.tres")
const MED_PROFILE = preload("res://Resources/WorldGen/Loot/medicine_kit_loot_profile.tres")
const PASS = preload("res://World/Generation/loot_population_pass.gd")

func _ready() -> void: call_deferred("_run")
func _assert(value: bool, message: String) -> void:
	if value: return
	push_error("Loot integration: " + message); get_tree().quit(1)
func _make(scene: PackedScene, id: String, profile: LootProfile) -> Node:
	var node := scene.instantiate(); node.world_generated_loot = true; node.generated_container_id = id; node.loot_profile = profile; add_child(node); return node
func _make_medicine(id: String, profile: LootProfile) -> Node:
	var node: Node = MED_SCRIPT.new(); node.world_generated_loot = true; node.generated_container_id = id; node.loot_profile = profile; return node
func _manifest(seed: int, provider: Node) -> LootContainerManifest:
	var loot_pass: LootPopulationPass = PASS.new(); var output := loot_pass.build_manifests(seed, [provider]); return LootContainerManifest.from_canonical(output.loot_manifests[0])
func _run() -> void:
	var box := _make(BOX_SCENE, "box_a", BOX_PROFILE); var med := _make_medicine("med_a", MED_PROFILE)
	var box_manifest := _manifest(1337, box); var med_manifest := _manifest(1337, med)
	_assert(box.apply_loot_manifest(box_manifest).valid and med.apply_loot_manifest(med_manifest).valid, "world manifests apply")
	_assert(box.apply_loot_manifest(box_manifest).valid and med.apply_loot_manifest(med_manifest).valid, "idempotent apply")
	_assert(box.loot_slots.size() == box.loot_slot_count and med.loot_slots.size() == med.loot_slot_count, "stable slot materialization")
	var changed := _manifest(7331, _make(BOX_SCENE, "box_b", BOX_PROFILE)); _assert(changed.manifest_hash() != box_manifest.manifest_hash(), "different seed variation")
	var med_again := _manifest(1337, _make_medicine("med_a", MED_PROFILE)); _assert(med_again.manifest_hash() == med_manifest.manifest_hash(), "independent container seeds")
	var invalid := _make(BOX_SCENE, "", BOX_PROFILE); _assert(not ProviderContract.validate(invalid).valid, "provider validation")
	var mismatch := LootContainerManifest.from_canonical(box_manifest.canonical_record()); mismatch.container_generated_id = "other"; _assert(not box.apply_loot_manifest(mismatch).valid, "manifest id mismatch")
	var standalone := BOX_SCENE.instantiate(); standalone.world_generated_loot = false; add_child(standalone); standalone._ensure_loot(); _assert(standalone.loot_initialized, "standalone box fallback")
	print("LOOT_CONTAINER_INTEGRATION_TEST=PASS digest=%s" % GenerationHashes.sha256_of([box_manifest.canonical_record(), med_manifest.canonical_record()]))
	get_tree().quit(0)

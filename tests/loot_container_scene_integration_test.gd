extends Node

const BOX_SCENE = preload("res://World/Boxes/Box1/Box1.tscn")
const MEDICINE_SCENE = preload("res://World/medicine_kit.tscn")
const BOX_PROFILE = preload("res://Resources/WorldGen/Loot/box_loot_profile.tres")
const MEDICINE_PROFILE = preload("res://Resources/WorldGen/Loot/medicine_kit_loot_profile.tres")
const PASS = preload("res://World/Generation/loot_population_pass.gd")
const ProviderContract = preload("res://World/Generation/loot_container_provider_contract.gd")

func _ready() -> void: call_deferred("_run")
func _assert(value: bool, message: String) -> void:
	if value: return
	push_error("Loot scene integration: " + message); get_tree().quit(1)
func _instance(scene: PackedScene, id: String, profile: LootProfile) -> Node:
	var node := scene.instantiate(); node.world_generated_loot = true; node.generated_container_id = id; node.loot_profile = profile; add_child(node); return node
func _manifest(seed: int, provider: Node) -> LootContainerManifest:
	var loot_pass: LootPopulationPass = PASS.new(); var output := loot_pass.build_manifests(seed, [provider]); return LootContainerManifest.from_canonical(output.loot_manifests[0])
func _run() -> void:
	_assert(ResourceLoader.load("res://World/Boxes/Box1/Box1.tscn") is PackedScene, "box scene resolves")
	_assert(ResourceLoader.load("res://World/medicine_kit.tscn") is PackedScene, "medicine scene resolves")
	var box := _instance(BOX_SCENE, "scene_box", BOX_PROFILE); var medicine := _instance(MEDICINE_SCENE, "scene_medicine", MEDICINE_PROFILE)
	await get_tree().process_frame
	_assert(ProviderContract.validate(box).valid and ProviderContract.validate(medicine).valid, "scene providers validate")
	var box_manifest := _manifest(1337, box); var medicine_manifest := _manifest(1337, medicine)
	_assert(box.apply_loot_manifest(box_manifest).valid and medicine.apply_loot_manifest(medicine_manifest).valid, "scene manifests apply")
	var before := GenerationHashes.sha256_of([box.loot_slots, medicine.loot_slots]); _assert(box.apply_loot_manifest(box_manifest).valid and medicine.apply_loot_manifest(medicine_manifest).valid, "idempotency"); _assert(before == GenerationHashes.sha256_of([box.loot_slots, medicine.loot_slots]), "no duplicate materialization")
	var conflict := LootContainerManifest.from_canonical(box_manifest.canonical_record()); conflict.slots[0].quantity += 1; _assert(not box.apply_loot_manifest(conflict).valid, "conflicting manifest blocks")
	_assert(box.get_loot_slot_bindings().has("slot_00") and medicine.get_loot_slot_bindings().has("slot_00"), "explicit slot bindings")
	box.queue_free(); medicine.queue_free(); await get_tree().process_frame
	var repeat := _instance(MEDICINE_SCENE, "scene_medicine", MEDICINE_PROFILE); var repeat_manifest := _manifest(1337, repeat); _assert(repeat_manifest.manifest_hash() == medicine_manifest.manifest_hash() and repeat.apply_loot_manifest(repeat_manifest).valid, "scene lifecycle has no stale state")
	var standalone_box := BOX_SCENE.instantiate(); standalone_box.world_generated_loot = false; add_child(standalone_box); await get_tree().process_frame; standalone_box._ensure_loot(); _assert(standalone_box.loot_initialized, "box standalone mode")
	var standalone_med := MEDICINE_SCENE.instantiate(); standalone_med.world_generated_loot = false; add_child(standalone_med); await get_tree().process_frame; standalone_med._ensure_loot(); _assert(standalone_med.loot_initialized, "medicine standalone mode")
	print("LOOT_CONTAINER_SCENE_INTEGRATION_TEST=PASS digest=%s" % GenerationHashes.sha256_of([box_manifest.canonical_record(), medicine_manifest.canonical_record()]))
	get_tree().quit(0)

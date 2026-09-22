extends Node

const PASS = preload("res://World/Generation/loot_population_pass.gd")
const PERSISTENCE = preload("res://World/Generation/loot_container_persistence.gd")
const MEDICINE_SCENE = preload("res://World/medicine_kit.tscn")
const HOUSE1_SCENE = preload("res://World/Assets/Houses/House1/house_1.tscn")
const TWO_SCENE = preload("res://World/Assets/Houses/TwoStoriedHouse/twoStoriedHouse.tscn")
const FORESTER_SCENE = preload("res://World/Assets/Houses/ForesterHouse/forester_house.tscn")
const BUNKER_SCENE = preload("res://World/Assets/Bunker/Bunker.tscn")
const MEDICINE_PROFILE = preload("res://Resources/WorldGen/Loot/medicine_kit_loot_profile.tres")
const HOUSE1_PROFILE = preload("res://Resources/WorldGen/Loot/house1_wardrobe_loot_profile.tres")
const TWO_PROFILE = preload("res://Resources/WorldGen/Loot/two_storied_bedside_loot_profile.tres")
const FORESTER_PROFILE = preload("res://Resources/WorldGen/Loot/forester_wardrobe_loot_profile.tres")
const BUNKER_PROFILE = preload("res://Resources/WorldGen/bunker_empty_loot_profile.tres")

var _records: Array[Dictionary] = []

func _ready() -> void: call_deferred("_run")
func _assert(value: bool, message: String) -> void:
	if value: return
	push_error("All providers persistence: " + message); get_tree().quit(1)

func _make(entry: Dictionary, changed_profile := false) -> Node:
	var node := (entry.scene as PackedScene).instantiate()
	var profile: LootProfile = entry.profile
	if changed_profile:
		profile = profile.duplicate(true); profile.profile_id = "changed_after_save_%s" % entry.name
	if entry.kind == "medicine":
		node.world_generated_loot = true; node.generated_container_id = entry.id; node.loot_profile = profile
	else:
		node.world_generated_mode = true; node.building_generated_object_id = entry.id; node.loot_profile = profile
	add_child(node)
	return node

func _manifest(node: Node, seed: int) -> LootContainerManifest:
	var population_pass: LootPopulationPass = PASS.new()
	var output := population_pass.build_manifests(seed, [node])
	_assert(output.blocking_errors.is_empty(), "manifest %s" % node.get_loot_container_id())
	return LootContainerManifest.from_canonical(output.loot_manifests[0])

func _json_roundtrip(data: Dictionary, id: String) -> Dictionary:
	var path := "user://loot_persistence_%s.json" % id.replace("/", "_")
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_string(JSON.stringify(data)); file.close()
	file = FileAccess.open(path, FileAccess.READ); var json := JSON.new(); _assert(json.parse(file.get_as_text()) == OK, "JSON %s" % id); file.close()
	return json.data as Dictionary

func _assert_invalid(node: Node, state: Dictionary, label: String) -> void:
	var corrupt := state.duplicate(true); corrupt.manifest_hash = "corrupt"; _assert(not node.restore_loot_state(corrupt).valid, label + " corrupt")
	var mismatch := state.duplicate(true); mismatch.container_id = "other"; _assert(not node.restore_loot_state(mismatch).valid, label + " mismatch")
	if not (state.manifest as Dictionary).slots.is_empty():
		var unknown_slot := state.duplicate(true); unknown_slot.manifest.slots[0].slot_id = "unknown"; unknown_slot.manifest_hash = LootContainerManifest.from_canonical(unknown_slot.manifest).manifest_hash(); _assert(not node.restore_loot_state(unknown_slot).valid, label + " unknown slot")
		var unknown_resource := state.duplicate(true); unknown_resource.manifest.slots[0].item_resource_key = "res://missing_item.tres"; unknown_resource.manifest_hash = LootContainerManifest.from_canonical(unknown_resource.manifest).manifest_hash(); _assert(not node.restore_loot_state(unknown_resource).valid, label + " unknown resource")

func _exercise(entry: Dictionary) -> void:
	var original := _make(entry); var manifest := _manifest(original, 1337); _assert(original.apply_loot_manifest(manifest).valid, entry.name + " apply")
	var unopened := _json_roundtrip(original.serialize_loot_state(), entry.name); _assert(unopened.state == PERSISTENCE.STATE_UNOPENED, entry.name + " unopened")
	_assert(original.get_loot_persistence_key() == "loot_container/%s" % original.get_loot_container_id(), entry.name + " key")
	original.queue_free(); await get_tree().process_frame
	var restored := _make(entry, true); _assert(restored.restore_loot_state(unopened).valid, entry.name + " unopened restore")
	_assert(restored.get_existing_loot_manifest().manifest_hash() == manifest.manifest_hash(), entry.name + " profile protected")
	_assert(restored.mark_loot_opened().valid, entry.name + " opened")
	var opened := _json_roundtrip(restored.serialize_loot_state(), entry.name + "_opened"); _assert(restored.restore_loot_state(opened).valid, entry.name + " opened restore")
	var changed_seed := _make(entry); var changed_manifest := _manifest(changed_seed, 7331); _assert(restored.get_existing_loot_manifest().manifest_hash() == manifest.manifest_hash(), entry.name + " seed protected")
	if not manifest.slots.is_empty():
		var slot_id := manifest.slots[0].slot_id; _assert(restored.record_loot_slot_removed(slot_id).valid, entry.name + " remove")
		var partial := _json_roundtrip(restored.serialize_loot_state(), entry.name + "_partial"); _assert(partial.state == PERSISTENCE.STATE_PARTIALLY_EMPTIED, entry.name + " partial")
		_assert(restored.restore_loot_state(partial).valid and restored.get_removed_loot_slot_ids().has(slot_id), entry.name + " partial restore")
		_assert(restored.restore_loot_state(partial).valid, entry.name + " repeated restore")
		_assert_invalid(restored, partial, entry.name)
	else:
		_assert(restored.loot_slots.filter(func(item): return item != null).is_empty(), "bunker empty")
		_assert(not restored.record_loot_slot_removed("slot_00").valid, "bunker partial blocked")
		_assert_invalid(restored, opened, entry.name)
	_records.append({"name":entry.name,"state":restored.serialize_loot_state()})
	changed_seed.queue_free(); restored.queue_free(); await get_tree().process_frame

func _standalone(entry: Dictionary) -> void:
	var node := (entry.scene as PackedScene).instantiate(); add_child(node)
	if entry.kind == "medicine": node.world_generated_loot = false
	else: node.world_generated_mode = false
	if node.has_method("_ensure_loot"): node.call("_ensure_loot")
	elif node.has_method("_ensure_wardrobe_loot"): node.call("_ensure_wardrobe_loot")
	else: node.call("_ensure_bedside_loot")
	_assert(node.has_materialized_loot(), entry.name + " standalone")
	node.queue_free()

func _run() -> void:
	var entries: Array[Dictionary] = [
		{"name":"medicine","scene":MEDICINE_SCENE,"profile":MEDICINE_PROFILE,"id":"medicine_a","kind":"medicine"},
		{"name":"house1","scene":HOUSE1_SCENE,"profile":HOUSE1_PROFILE,"id":"house_a","kind":"building"},
		{"name":"two_storied","scene":TWO_SCENE,"profile":TWO_PROFILE,"id":"two_a","kind":"building"},
		{"name":"forester","scene":FORESTER_SCENE,"profile":FORESTER_PROFILE,"id":"forester_a","kind":"building"},
		{"name":"bunker","scene":BUNKER_SCENE,"profile":BUNKER_PROFILE,"id":"bunker_a","kind":"building"},
	]
	for entry in entries: await _exercise(entry); _standalone(entry)
	print("LOOT_ALL_PROVIDERS_PERSISTENCE_RELOAD_TEST=PASS digest=%s" % PERSISTENCE.compute_saved_state_hash({"providers":_records}))
	get_tree().quit(0)

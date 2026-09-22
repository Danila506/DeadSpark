extends Node

const BOX_SCENE = preload("res://World/Boxes/Box1/Box1.tscn")
const BOX_PROFILE = preload("res://Resources/WorldGen/Loot/box_loot_profile.tres")
const LOOT_PASS = preload("res://World/Generation/loot_population_pass.gd")
const PERSISTENCE = preload("res://World/Generation/loot_container_persistence.gd")

func _ready() -> void:
	call_deferred("_run")


func _assert(value: bool, message: String) -> void:
	if value:
		return
	push_error("Loot Box persistence reload test: " + message)
	get_tree().quit(1)


func _make_box(id := "world_box_a", profile: LootProfile = BOX_PROFILE) -> Node:
	var box := BOX_SCENE.instantiate()
	box.world_generated_loot = true
	box.generated_container_id = id
	box.loot_profile = profile
	add_child(box)
	return box


func _manifest(box: Node, seed := 1337) -> LootContainerManifest:
	var population_pass: LootPopulationPass = LOOT_PASS.new()
	var output := population_pass.build_manifests(seed, [box])
	_assert(output.blocking_errors.is_empty(), "manifest generation")
	return LootContainerManifest.from_canonical(output.loot_manifests[0])


func _json_roundtrip(source: Dictionary) -> Dictionary:
	var path := "user://loot_box_persistence_roundtrip.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(source))
	file.close()
	file = FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	_assert(json.parse(file.get_as_text()) == OK, "JSON roundtrip parse")
	file.close()
	return json.data as Dictionary


func _first_manifest_slot(state: Dictionary) -> String:
	return String((state.manifest as Dictionary).slots[0].slot_id)


func _run() -> void:
	var original := _make_box()
	var manifest := _manifest(original)
	_assert(original.apply_loot_manifest(manifest).valid, "initial deterministic manifest")
	var unopened := _json_roundtrip(original.serialize_loot_state())
	_assert(unopened.state == PERSISTENCE.STATE_UNOPENED, "unopened snapshot")
	_assert(unopened.manifest_hash == manifest.manifest_hash(), "unopened manifest hash")
	_assert(original.get_loot_persistence_key() == "loot_container/world_box_a", "persistence key")
	original.queue_free()
	await get_tree().process_frame

	var reopened := _make_box()
	_assert(reopened.restore_loot_state(unopened).valid, "unopened reload")
	_assert(reopened.get_existing_loot_manifest().manifest_hash() == manifest.manifest_hash(), "unopened manifest retained")
	_assert(not reopened.box_opened, "unopened remains closed after restore")
	_assert(reopened.mark_loot_opened().valid, "mark opened")
	var opened := _json_roundtrip(reopened.serialize_loot_state())
	_assert(opened.state == PERSISTENCE.STATE_OPENED, "opened snapshot")

	var changed_seed_box := _make_box("world_box_a")
	var changed_seed_manifest := _manifest(changed_seed_box, 7331)
	_assert(changed_seed_manifest.manifest_hash() != manifest.manifest_hash(), "seed variation exists")
	_assert(reopened.restore_loot_state(opened).valid, "opened repeated reload")
	_assert(reopened.get_existing_loot_manifest().manifest_hash() == manifest.manifest_hash(), "seed cannot reroll saved loot")

	var removed_slot := _first_manifest_slot(opened)
	_assert(reopened.record_loot_slot_removed(removed_slot).valid, "record removed slot")
	var partial := _json_roundtrip(reopened.serialize_loot_state())
	_assert(partial.state == PERSISTENCE.STATE_PARTIALLY_EMPTIED, "partial snapshot")
	reopened.queue_free()
	changed_seed_box.queue_free()
	await get_tree().process_frame

	var changed_profile: LootProfile = BOX_PROFILE.duplicate(true)
	changed_profile.profile_id = "changed_profile_after_save"
	var restored := _make_box("world_box_a", changed_profile)
	_assert(restored.restore_loot_state(partial).valid, "profile cannot reroll saved loot")
	var bindings: Dictionary = restored.get_loot_slot_bindings()
	_assert(restored.loot_slots[int(bindings[removed_slot])] == null, "removed slot stays empty")
	var first_restore_hash := PERSISTENCE.compute_saved_state_hash(restored.serialize_loot_state())
	_assert(restored.restore_loot_state(partial).valid, "partial repeated reload")
	_assert(restored.loot_slots[int(bindings[removed_slot])] == null, "repeated reload has no duplicate")
	_assert(first_restore_hash == PERSISTENCE.compute_saved_state_hash(restored.serialize_loot_state()), "repeated reload idempotency")

	var corrupt := partial.duplicate(true)
	corrupt.manifest_hash = "broken"
	_assert(not restored.restore_loot_state(corrupt).valid, "corrupted manifest hash rejected")
	var mismatch := partial.duplicate(true)
	mismatch.container_id = "other_box"
	_assert(not restored.restore_loot_state(mismatch).valid, "container mismatch rejected")
	var unknown_slot := partial.duplicate(true)
	unknown_slot.manifest.slots[0].slot_id = "unknown_slot"
	unknown_slot.manifest_hash = LootContainerManifest.from_canonical(unknown_slot.manifest).manifest_hash()
	_assert(not restored.restore_loot_state(unknown_slot).valid, "unknown slot rejected")
	var unknown_resource := partial.duplicate(true)
	unknown_resource.manifest.slots[0].item_resource_key = "res://missing_item.tres"
	unknown_resource.manifest_hash = LootContainerManifest.from_canonical(unknown_resource.manifest).manifest_hash()
	_assert(not restored.restore_loot_state(unknown_resource).valid, "unknown resource rejected")
	var duplicate_slot := partial.duplicate(true)
	duplicate_slot.manifest.slots.append(duplicate_slot.manifest.slots[0].duplicate(true))
	duplicate_slot.manifest_hash = LootContainerManifest.from_canonical(duplicate_slot.manifest).manifest_hash()
	_assert(not restored.restore_loot_state(duplicate_slot).valid, "duplicate slot rejected")
	var invalid_state := partial.duplicate(true)
	invalid_state.state = "invalid"
	_assert(not restored.restore_loot_state(invalid_state).valid, "invalid state rejected")
	var invalid_removed := partial.duplicate(true)
	invalid_removed.removed_slot_ids = [removed_slot, removed_slot]
	_assert(not restored.restore_loot_state(invalid_removed).valid, "invalid removed slots rejected")

	var conflicting := LootContainerManifest.from_canonical(partial.manifest)
	conflicting.container_generated_id = "world_box_a"
	conflicting.slots[0].quantity += 1
	var incompatible := partial.duplicate(true)
	incompatible.manifest = conflicting.canonical_record()
	incompatible.manifest_hash = conflicting.manifest_hash()
	_assert(not restored.restore_loot_state(incompatible).valid, "incompatible materialized state rejected")

	var standalone := BOX_SCENE.instantiate()
	standalone.world_generated_loot = false
	add_child(standalone)
	standalone._ensure_loot()
	_assert(standalone.loot_initialized, "standalone Box remains functional")
	_assert(restored.loot_initialized and restored.get_existing_loot_manifest() != null, "restore never uses legacy random")
	var digest := PERSISTENCE.compute_saved_state_hash(partial)
	print("LOOT_BOX_PERSISTENCE_RELOAD_TEST=PASS digest=%s" % digest)
	get_tree().quit(0)

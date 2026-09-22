class_name LootPopulationPass
extends Node

const LootSlot = preload("res://World/Generation/loot_slot_record.gd")
const LootManifest = preload("res://World/Generation/loot_container_manifest.gd")

var blocking_errors: Array[String] = []
var _output: Dictionary = {"id": "loot_population_v1", "loot_manifests": [], "loot_manifest_hash": ""}

## Providers implement get_loot_container_id() -> String and get_loot_profile() -> LootProfile.
## This duck-typed boundary keeps legacy container integration out of this slice.
func build_manifests(master_seed: int, providers: Array[Node]) -> Dictionary:
	blocking_errors.clear()
	var ordered: Array[Node] = providers.duplicate()
	ordered.sort_custom(func(a: Node, b: Node): return _provider_id(a) < _provider_id(b))
	var seen := {}
	var manifests: Array[Dictionary] = []
	for provider in ordered:
		var container_id := _provider_id(provider)
		if container_id.is_empty():
			blocking_errors.append("loot: MISSING_CONTAINER_ID")
			continue
		if seen.has(container_id):
			blocking_errors.append("loot: DUPLICATE_CONTAINER_ID:%s" % container_id)
			continue
		seen[container_id] = true
		var profile := _provider_profile(provider)
		if profile == null:
			blocking_errors.append("loot: MISSING_PROFILE:%s" % container_id)
			continue
		var validation := profile.validate()
		if not bool(validation.valid):
			for error in validation.errors: blocking_errors.append("loot: %s container=%s profile=%s" % [String(error), container_id, profile.profile_id])
			continue
		manifests.append(_build_container_manifest(master_seed, container_id, profile).canonical_record())
	manifests.sort_custom(func(a: Dictionary, b: Dictionary): return String(a.container_generated_id) < String(b.container_generated_id))
	_output = {"id": "loot_population_v1", "loot_manifests": manifests, "loot_manifest_hash": GenerationHashes.sha256_of(manifests), "blocking_errors": blocking_errors.duplicate()}
	return _output.duplicate(true)

func get_generation_output_manifest() -> Dictionary:
	return _output.duplicate(true)

func _build_container_manifest(master_seed: int, container_id: String, profile: LootProfile) -> LootContainerManifest:
	var manifest: LootContainerManifest = LootManifest.new()
	manifest.container_generated_id = container_id; manifest.profile_id = profile.profile_id
	if profile.explicit_empty or not profile.enabled: return manifest
	var entries := profile._valid_enabled_entries()
	entries.sort_custom(func(a: LootEntry, b: LootEntry): return a.entry_id < b.entry_id)
	var used := {}
	var slots: Array[String] = profile.slot_ids.duplicate(); slots.sort()
	for ordinal in range(slots.size()):
		var slot_id := slots[ordinal]
		var eligible: Array[LootEntry] = []
		for entry in entries:
			if not entry.unique or not used.has(entry.entry_id): eligible.append(entry)
		if eligible.is_empty():
			if profile.allow_empty: continue
			break
		var slot_seed := WorldSeedService.derive_seed(master_seed, "loot/container/%s/slot/%s" % [container_id, slot_id])
		var chosen := _choose_weighted(eligible, slot_seed)
		if chosen == null: continue
		var record: LootSlotRecord = LootSlot.new()
		record.container_generated_id = container_id; record.profile_id = profile.profile_id; record.slot_id = slot_id
		record.item_resource_key = chosen.item_resource_key(); record.deterministic_ordinal = ordinal
		var range_size := chosen.max_quantity - chosen.min_quantity + 1
		record.quantity = chosen.min_quantity + posmod(WorldSeedService.derive_seed(master_seed, "loot/container/%s/slot/%s/quantity" % [container_id, slot_id]), range_size)
		manifest.slots.append(record)
		if chosen.unique: used[chosen.entry_id] = true
	return manifest

func _choose_weighted(entries: Array[LootEntry], seed: int) -> LootEntry:
	var total := 0
	for entry in entries: total += maxi(0, int(round(entry.weight * 1000.0)))
	if total <= 0: return null
	var roll := posmod(seed, total)
	var cursor := 0
	for entry in entries:
		cursor += maxi(0, int(round(entry.weight * 1000.0)))
		if roll < cursor: return entry
	return entries.back()

func _provider_id(provider: Node) -> String:
	return String(provider.call("get_loot_container_id")) if provider != null and provider.has_method("get_loot_container_id") else ""

func _provider_profile(provider: Node) -> LootProfile:
	return provider.call("get_loot_profile") as LootProfile if provider != null and provider.has_method("get_loot_profile") else null

## Hand-placed containers roll once when first opened, using the same authored pools.
static func roll_standalone_items(profile: LootProfile, capacity: int) -> Array[ItemData]:
	var items: Array[ItemData] = []
	items.resize(maxi(capacity, 0))
	if profile == null or not profile.validate().valid: return items
	var pass_node := LootPopulationPass.new()
	var manifest := pass_node._build_container_manifest(randi(), "standalone", profile)
	pass_node.free()
	var slots := profile.slot_ids.duplicate()
	slots.sort()
	for record in manifest.slots:
		var index := slots.find(record.slot_id)
		if index >= 0 and index < items.size():
			items[index] = (load(record.item_resource_key) as ItemData).create_instance(record.quantity)
	return items

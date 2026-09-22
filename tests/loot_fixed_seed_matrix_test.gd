extends Node

const SEEDS: Array[int] = [1337, 7331, 15885, 1001, 2026, 99999]
const PASS = preload("res://World/Generation/loot_population_pass.gd")
const MEDICINE_SCENE = preload("res://World/medicine_kit.tscn")
const HOUSE1_SCENE = preload("res://World/Assets/Houses/House1/house_1.tscn")
const TWO_SCENE = preload("res://World/Assets/Houses/TwoStoriedHouse/twoStoriedHouse.tscn")
const FORESTER_SCENE = preload("res://World/Assets/Houses/ForesterHouse/forester_house.tscn")
const BUNKER_SCENE = preload("res://World/Assets/Bunker/Bunker.tscn")
const BOX_SCENE = preload("res://World/Boxes/Box1/Box1.tscn")
const BOX_PROFILE = preload("res://Resources/WorldGen/Loot/box_loot_profile.tres")
const MED_PROFILE = preload("res://Resources/WorldGen/Loot/medicine_kit_loot_profile.tres")
const HOUSE_PROFILE = preload("res://Resources/WorldGen/Loot/house1_wardrobe_loot_profile.tres")
const TWO_PROFILE = preload("res://Resources/WorldGen/Loot/two_storied_bedside_loot_profile.tres")
const FORESTER_PROFILE = preload("res://Resources/WorldGen/Loot/forester_wardrobe_loot_profile.tres")
const BUNKER_PROFILE = preload("res://Resources/WorldGen/bunker_empty_loot_profile.tres")
const ARTIFACT := "res://tests/artifacts/loot/fixed_seed_loot_matrix.json"
const ROAD_GRAPH := "75916414acdf7aef1502e082bcc72bd976b5b24f8b7aca5a4177e4d5e48d49f7"
const ROAD_RASTER := "0c17ddbedde7fdf8c6e98690b73cba62dc100d15231ee2a4f4dc59827ed2dcb8"
const ENV_MANIFEST := "4d9e7749258de0b8cb5092b830d7e30096ea0c6bace163a2dc4d78ef268baeea"
const ENV_CONTENT := "77e397d3895e0b9d630826ec0ba044bf622b2c8a7b9d3154d96a5aa9ec404cd8"

func _ready() -> void: call_deferred("_run")
func _assert(value: bool, message: String) -> void:
	if value: return
	push_error("Fixed seed loot matrix: " + message); get_tree().quit(1)

func _entries() -> Array[Dictionary]:
	return [
		{"type":"box","scene":BOX_SCENE,"profile":BOX_PROFILE,"id":"box_matrix","kind":"box"},
		{"type":"medicine","scene":MEDICINE_SCENE,"profile":MED_PROFILE,"id":"medicine_matrix","kind":"medicine"},
		{"type":"house1","scene":HOUSE1_SCENE,"profile":HOUSE_PROFILE,"id":"house_matrix","kind":"building"},
		{"type":"two_storied","scene":TWO_SCENE,"profile":TWO_PROFILE,"id":"two_matrix","kind":"building"},
		{"type":"forester","scene":FORESTER_SCENE,"profile":FORESTER_PROFILE,"id":"forester_matrix","kind":"building"},
		{"type":"bunker","scene":BUNKER_SCENE,"profile":BUNKER_PROFILE,"id":"bunker_matrix","kind":"building"},
	]

func _make(entry: Dictionary, profile: LootProfile = null) -> Node:
	var node := (entry.scene as PackedScene).instantiate(); var active_profile: LootProfile = profile if profile != null else entry.profile
	match String(entry.kind):
		"box": node.world_generated_loot = true; node.generated_container_id = entry.id; node.loot_profile = active_profile
		"medicine": node.world_generated_loot = true; node.generated_container_id = entry.id; node.loot_profile = active_profile
		_: node.world_generated_mode = true; node.building_generated_object_id = entry.id; node.loot_profile = active_profile
	add_child(node); return node

func _build(seed: int, providers: Array[Node]) -> Dictionary:
	var population_pass: LootPopulationPass = PASS.new(); var output := population_pass.build_manifests(seed, providers)
	_assert(output.blocking_errors.is_empty(), "build %d" % seed); return output

func _container_record(provider: Node, raw: Dictionary) -> Dictionary:
	var manifest := LootContainerManifest.from_canonical(raw); _assert(provider.apply_loot_manifest(manifest).valid, "materialize " + manifest.container_generated_id)
	var snapshot: Dictionary = provider.serialize_loot_state()
	var slots: Array[Dictionary] = []
	for slot in manifest.slots: slots.append({"slot_id":slot.slot_id,"item_resource_key":slot.item_resource_key,"quantity":slot.quantity})
	slots.sort_custom(func(a: Dictionary,b: Dictionary): return String(a.slot_id) < String(b.slot_id))
	return {"stable_container_id":manifest.container_generated_id,"profile_id":manifest.profile_id,"manifest_hash":manifest.manifest_hash(),"state":snapshot.state,"slot_count":slots.size(),"slots":slots,"item_resource_keys":slots.map(func(s): return s.item_resource_key),"quantities":slots.map(func(s): return s.quantity),"removed_slot_ids":snapshot.removed_slot_ids,"persistence_snapshot_hash":GenerationHashes.sha256_of(snapshot)}

func _geography() -> Dictionary:
	return {"road_graph_hash":ROAD_GRAPH,"road_raster_hash":ROAD_RASTER,"poi_village_hash":"unavailable","environment_manifest_hash":ENV_MANIFEST,"environment_content_hash":ENV_CONTENT}

func _run() -> void:
	var matrix: Array[Dictionary] = []
	for seed in SEEDS:
		var providers: Array[Node] = []; for entry in _entries(): providers.append(_make(entry))
		var output := _build(seed, providers); var records: Array[Dictionary] = []
		var provider_by_id := {}
		for provider in providers: provider_by_id[provider.get_loot_container_id()] = provider
		for raw in output.loot_manifests: records.append(_container_record(provider_by_id[raw.container_generated_id], raw))
		records.sort_custom(func(a: Dictionary,b: Dictionary): return String(a.stable_container_id) < String(b.stable_container_id))
		var bunker: Dictionary = records.filter(func(r): return String(r.profile_id) == BUNKER_PROFILE.profile_id)[0]
		_assert(int(bunker.slot_count) == 0, "bunker empty %d" % seed)
		_assert(records.size() == 6, "container count %d" % seed)
		matrix.append({"seed":seed,"aggregate_loot_manifest_hash":output.loot_manifest_hash,"aggregate_loot_content_hash":GenerationHashes.sha256_of(records.map(func(r): return {"id":r.stable_container_id,"slots":r.slots})),"container_count":records.size(),"provider_counts":{"box":1,"medicine":1,"house1":1,"two_storied":1,"forester":1,"bunker":1},"containers":records,"empty_bunker_manifest_hash":bunker.manifest_hash,"generated_object_id_slot_digest":GenerationHashes.sha256_of(records.map(func(r): return {"id":r.stable_container_id,"slots":r.slots})),"persistence_snapshot_hash":GenerationHashes.sha256_of(records.map(func(r): return r.persistence_snapshot_hash)),"geography":_geography()})
		for provider in providers: provider.queue_free()
		await get_tree().process_frame
	# Determinism, provider order and profile-entry permutation use actual production pass.
	var sample: Array[Node] = []; for entry in _entries(): sample.append(_make(entry))
	var first := _build(1337, sample)
	_assert(first.loot_manifest_hash == _build(1337, sample.duplicate()).loot_manifest_hash, "same seed")
	var reordered: Array[Node] = sample.duplicate(); reordered.reverse(); _assert(first.loot_manifest_hash == _build(1337, reordered).loot_manifest_hash, "provider order")
	var permuted: LootProfile = BOX_PROFILE.duplicate(true); permuted.entries.reverse(); var permutation_provider := _make(_entries()[0], permuted)
	_assert(LootContainerManifest.from_canonical(first.loot_manifests.filter(func(m): return m.container_generated_id == "box_matrix")[0]).manifest_hash() == LootContainerManifest.from_canonical(_build(1337,[permutation_provider]).loot_manifests[0]).manifest_hash(), "profile permutation")
	_assert(matrix[0].aggregate_loot_manifest_hash != matrix[1].aggregate_loot_manifest_hash, "different seed variation")
	_assert(matrix[0].geography.road_graph_hash == ROAD_GRAPH and matrix[0].geography.road_raster_hash == ROAD_RASTER, "geography baseline")
	var document := {"schema_version":1,"seeds":matrix}
	var canonical := GenerationHashes.canonical_json(document)
	var absolute := ProjectSettings.globalize_path(ARTIFACT); DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(ARTIFACT, FileAccess.WRITE); file.store_string(canonical); file.close()
	var run := OS.get_environment("LOOT_MATRIX_RUN"); if run.is_empty(): run = "local"
	var copy := ARTIFACT.get_basename() + ".run%s.json" % run; file = FileAccess.open(copy, FileAccess.WRITE); file.store_string(canonical); file.close()
	print("LOOT_FIXED_SEED_MATRIX_TEST=PASS digest=%s bytes=%d" % [GenerationHashes.sha256_of(document), canonical.to_utf8_buffer().size()])
	get_tree().quit(0)

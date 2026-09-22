extends Node

const PASS = preload("res://World/Generation/loot_population_pass.gd")
const ENTRY = preload("res://World/Generation/loot_entry.gd")
const PROFILE = preload("res://World/Generation/loot_profile.gd")
const APPLE = preload("res://Resources/Food/apple.tres")
const TUSHENKA = preload("res://Resources/Food/tushenka.tres")
const EMPTY_BUNKER = preload("res://Resources/WorldGen/bunker_empty_loot_profile.tres")

class TestProvider extends Node:
	var container_id := ""
	var profile: LootProfile
	func get_loot_container_id() -> String: return container_id
	func get_loot_profile() -> LootProfile: return profile

func _ready() -> void: call_deferred("_run")

func _run() -> void:
	_test_same_seed_variation_and_independence()
	_test_entry_permutation_and_empty_profile()
	_test_validation()
	print("LOOT_POPULATION_CONTRACT_TEST=PASS digest=%s" % _digest())
	get_tree().quit(0)

func _entry(id: String, item: Resource, weight := 1.0) -> LootEntry:
	var entry: LootEntry = ENTRY.new(); entry.entry_id = id; entry.item = item; entry.weight = weight; entry.min_quantity = 1; entry.max_quantity = 3
	return entry

func _profile(entries: Array[LootEntry]) -> LootProfile:
	var profile: LootProfile = PROFILE.new(); profile.profile_id = "house_food"; profile.slot_ids = ["slot_b", "slot_a"]; profile.entries = entries
	return profile

func _provider(id: String, profile: LootProfile) -> TestProvider:
	var provider := TestProvider.new(); provider.container_id = id; provider.profile = profile; return provider

func _generate(seed: int, providers: Array[Node]) -> Dictionary:
	var loot_pass: LootPopulationPass = PASS.new(); add_child(loot_pass); var output := loot_pass.build_manifests(seed, providers); loot_pass.queue_free(); return output

func _assert(value: bool, message: String) -> void:
	if value: return
	push_error("Loot population contract test: " + message); get_tree().quit(1)

func _test_same_seed_variation_and_independence() -> void:
	var first_profile := _profile([_entry("apple", APPLE, 1.0), _entry("stew", TUSHENKA, 3.0)])
	var one := _generate(1337, [_provider("container_b", first_profile), _provider("container_a", first_profile)])
	var two := _generate(1337, [_provider("container_a", first_profile), _provider("container_b", first_profile)])
	_assert(one.loot_manifest_hash == two.loot_manifest_hash and GenerationHashes.sha256_of(one.loot_manifests) == GenerationHashes.sha256_of(two.loot_manifests), "same seed canonical output")
	var varied := _generate(7331, [_provider("container_a", first_profile), _provider("container_b", first_profile)])
	_assert(one.loot_manifest_hash != varied.loot_manifest_hash, "different seed variation")
	var changed_profile := _profile([_entry("apple", APPLE, 5.0), _entry("stew", TUSHENKA, 1.0)])
	var changed := _generate(1337, [_provider("container_a", changed_profile), _provider("container_b", first_profile)])
	_assert(GenerationHashes.sha256_of(one.loot_manifests[1]) == GenerationHashes.sha256_of(changed.loot_manifests[1]), "container seeds independent")

func _test_entry_permutation_and_empty_profile() -> void:
	var a := _entry("apple", APPLE, 1.0); var b := _entry("stew", TUSHENKA, 3.0)
	var original := _generate(2026, [_provider("container", _profile([a, b]))])
	var reversed := _generate(2026, [_provider("container", _profile([b, a]))])
	_assert(original.loot_manifest_hash == reversed.loot_manifest_hash, "entry order permutation")
	var empty := _generate(1337, [_provider("bunker", EMPTY_BUNKER)])
	_assert(empty.blocking_errors.is_empty() and (empty.loot_manifests[0].slots as Array).is_empty(), "explicit empty bunker profile")

func _test_validation() -> void:
	var missing: LootEntry = _entry("missing", null); var missing_output := _generate(1, [_provider("bad", _profile([missing]))])
	_assert(not missing_output.blocking_errors.is_empty(), "missing resource blocks")
	var first := _entry("same", APPLE); var second := _entry("same", TUSHENKA); var duplicate_output := _generate(1, [_provider("bad", _profile([first, second]))])
	_assert(not duplicate_output.blocking_errors.is_empty(), "duplicate entry id blocks")
	var invalid_profile := _profile([_entry("apple", APPLE)]); invalid_profile.slot_ids = ["slot", "slot"]
	var slots_output := _generate(1, [_provider("bad", invalid_profile)])
	_assert(not slots_output.blocking_errors.is_empty(), "duplicate slot id blocks")
	var no_id_output := _generate(1, [_provider("", _profile([_entry("apple", APPLE)]))])
	_assert(not no_id_output.blocking_errors.is_empty(), "missing container id blocks")
	var missing_profile_id := _profile([_entry("apple", APPLE)]); missing_profile_id.profile_id = ""
	var profile_id_output := _generate(1, [_provider("bad", missing_profile_id)])
	_assert(not profile_id_output.blocking_errors.is_empty(), "missing profile id blocks")
	var missing_entry_id := _profile([_entry("", APPLE)])
	var entry_id_output := _generate(1, [_provider("bad", missing_entry_id)])
	_assert(not entry_id_output.blocking_errors.is_empty(), "missing entry id blocks")

func _digest() -> String:
	var output := _generate(1337, [_provider("container_a", _profile([_entry("apple", APPLE), _entry("stew", TUSHENKA, 3.0)])), _provider("container_b", _profile([_entry("apple", APPLE), _entry("stew", TUSHENKA, 3.0)]))])
	return GenerationHashes.sha256_of(output)

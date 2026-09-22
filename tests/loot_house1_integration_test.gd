extends Node
const SCENE = preload("res://World/Assets/Houses/House1/house_1.tscn")
const PROFILE = preload("res://Resources/WorldGen/Loot/house1_wardrobe_loot_profile.tres")
const PASS = preload("res://World/Generation/loot_population_pass.gd")
func _ready(): call_deferred("_run")
func _assert(ok, text): if not ok: push_error(text); get_tree().quit(1)
func _house(id): var h=SCENE.instantiate();h.world_generated_mode=true;h.building_generated_object_id=id;h.loot_profile=PROFILE;add_child(h);return h
func _manifest(h, seed): var p=PASS.new();return LootContainerManifest.from_canonical(p.build_manifests(seed,[h]).loot_manifests[0])
func _run():
	var a=_house("building_a");await get_tree().process_frame;_assert(a.get_loot_container_id()=="building_a/loot/wardrobe_main","derived id");var m=_manifest(a,1337);_assert(a.apply_loot_manifest(m).valid and a.apply_loot_manifest(m).valid,"apply/idempotence");_assert(not a.legacy_random_path_used,"no legacy random");var b=_house("building_b");var mb=_manifest(b,1337);_assert(m.manifest_hash()!=mb.manifest_hash(),"building independent");print("LOOT_HOUSE1_INTEGRATION_TEST=PASS digest="+GenerationHashes.sha256_of([m.canonical_record(),mb.canonical_record()]));get_tree().quit(0)

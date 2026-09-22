extends Node
const SCENE=preload("res://World/Assets/Houses/TwoStoriedHouse/twoStoriedHouse.tscn")
const PROFILE=preload("res://Resources/WorldGen/Loot/two_storied_bedside_loot_profile.tres")
const PASS=preload("res://World/Generation/loot_population_pass.gd")
func _ready():call_deferred("_run")
func _assert(v,m):if not v:push_error(m);get_tree().quit(1)
func _h(id):var h=SCENE.instantiate();h.world_generated_mode=true;h.building_generated_object_id=id;h.loot_profile=PROFILE;add_child(h);return h
func _m(h,s):var p=PASS.new();return LootContainerManifest.from_canonical(p.build_manifests(s,[h]).loot_manifests[0])
func _run():var a=_h("tower_a");await get_tree().process_frame;_assert(a.get_loot_container_id()=="tower_a/loot/bedside_main","id");var m=_m(a,1337);_assert(a.apply_loot_manifest(m).valid and a.apply_loot_manifest(m).valid,"apply");_assert(not a.legacy_random_path_used,"random");var b=_h("tower_b");var mb=_m(b,1337);_assert(m.manifest_hash()!=mb.manifest_hash(),"independent");print("LOOT_TWO_STORIED_TEST=PASS digest="+GenerationHashes.sha256_of([m.canonical_record(),mb.canonical_record()]));get_tree().quit(0)

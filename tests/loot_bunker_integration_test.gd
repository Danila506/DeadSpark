extends Node
const SCENE=preload("res://World/Assets/Bunker/Bunker.tscn")
const EMPTY=preload("res://Resources/WorldGen/bunker_empty_loot_profile.tres")
const PASS=preload("res://World/Generation/loot_population_pass.gd")
func _ready():call_deferred("_run")
func _assert(v,m):if not v:push_error(m);get_tree().quit(1)
func _b(id):var b=SCENE.instantiate();b.world_generated_mode=true;b.building_generated_object_id=id;b.loot_profile=EMPTY;add_child(b);return b
func _m(b,s):var p=PASS.new();return LootContainerManifest.from_canonical(p.build_manifests(s,[b]).loot_manifests[0])
func _run():var a=_b("bunker_a");await get_tree().process_frame;_assert(a.get_loot_container_id()=="bunker_a/loot/bunker_box_main","id");var m=_m(a,1337);_assert(m.slots.is_empty() and a.apply_loot_manifest(m).valid and a.loot_slots.filter(func(i):return i!=null).is_empty(),"empty");_assert(a.apply_loot_manifest(m).valid and not a.legacy_random_path_used,"idempotent/random");var b=_b("bunker_b");var mb=_m(b,7331);_assert(m.slots.is_empty() and mb.slots.is_empty() and m.manifest_hash()!=mb.manifest_hash(),"empty ids");print("LOOT_BUNKER_TEST=PASS digest="+GenerationHashes.sha256_of([m.canonical_record(),mb.canonical_record()]));get_tree().quit(0)

extends Node
const PASS=preload("res://World/Generation/enemy_population_pass.gd")
const PROFILE_SCRIPT=preload("res://World/Generation/enemy_population_profile.gd")
const ENTRY_SCRIPT=preload("res://World/Generation/enemy_population_entry.gd")
const MARKER=preload("res://World/Generation/enemy_spawn_marker_record.gd")
const BANDIT=preload("res://Enemies/Bandits/Bandit_1/Bandit.tscn")
class Provider extends Node:
	var owner_id="";var profile:EnemyPopulationProfile;var markers:Array=[]
	func get_enemy_population_owner_id()->String:return owner_id
	func get_enemy_population_profile()->EnemyPopulationProfile:return profile
	func get_enemy_spawn_markers()->Array:return markers
func _ready():call_deferred("_run")
func _assert(v,m):if not v:push_error("Enemy population: "+m);get_tree().quit(1)
func _profile()->EnemyPopulationProfile:
	var p:EnemyPopulationProfile=PROFILE_SCRIPT.new();p.profile_id="bandit_population";p.min_total_count=0;p.max_total_count=10;p.per_marker_cap=2
	for id in ["bandit_a","bandit_b"]:
		var e:EnemyPopulationEntry=ENTRY_SCRIPT.new();e.entry_id=id;e.enemy_scene=BANDIT;e.weight=1.0;e.min_count=0;e.max_count=2;e.allowed_marker_tags=["guard"];p.entries.append(e)
	return p
func _marker(id:String,pos:Vector2)->EnemySpawnMarkerRecord:
	var m:EnemySpawnMarkerRecord=MARKER.new();m.marker_id=id;m.position=pos;m.tags=["guard"];m.capacity=2;return m
func _provider(owner:String,markers:Array,profile:EnemyPopulationProfile)->Provider:
	var p:=Provider.new();p.owner_id=owner;p.markers=markers;p.profile=profile;return p
func _build(seed:int,providers:Array)->Dictionary:return (PASS.new() as EnemyPopulationPass).build_manifests(seed,providers)
func _run():
	var p:=_profile();var a:=_provider("camp_a",[_marker("m_a",Vector2(1,2)),_marker("m_b",Vector2(3,4))],p);var b:=_provider("camp_b",[_marker("m_c",Vector2(5,6))],p)
	var one:=_build(1337,[a,b]);var two:=_build(1337,[b,a]);_assert(one.blocking_errors.is_empty() and one.population_manifest_hash==two.population_manifest_hash,"same seed/provider order")
	var marker_reordered:=_build(1337,[_provider("camp_a",[_marker("m_b",Vector2(3,4)),_marker("m_a",Vector2(1,2))],p),b]);_assert(one.population_manifest_hash==marker_reordered.population_manifest_hash,"marker order")
	var permuted:=_profile();permuted.entries.reverse();_assert(_build(1337,[_provider("camp_a",a.markers,permuted),b]).population_manifest_hash==one.population_manifest_hash,"entry order")
	var varied:=_build(7331,[a,b]);_assert(varied.population_manifest_hash!=one.population_manifest_hash,"seed variation")
	var changed:=_build(1337,[_provider("camp_a",[_marker("changed",Vector2(9,9)),_marker("m_b",Vector2(3,4))],p),b]);_assert(String(one.population_manifests[1].owner_generated_object_id)==String(changed.population_manifests[1].owner_generated_object_id),"independent owner")
	var dup:=_provider("bad",[_marker("same",Vector2.ZERO),_marker("same",Vector2.ONE)],p);_assert(not _build(1,[dup]).blocking_errors.is_empty(),"duplicate marker")
	var bad:=_profile();bad.entries[1].entry_id="bandit_a";_assert(not _build(1,[_provider("bad2",[_marker("m",Vector2.ZERO)],bad)]).blocking_errors.is_empty(),"duplicate entry")
	var missing:=_profile();missing.entries[0].enemy_scene=null;_assert(not _build(1,[_provider("bad3",[_marker("m",Vector2.ZERO)],missing)]).blocking_errors.is_empty(),"missing resource")
	var count:=_profile();count.min_total_count=99;_assert(not _build(1,[_provider("bad4",[_marker("m",Vector2.ZERO)],count)]).blocking_errors.is_empty(),"budget")
	print("ENEMY_POPULATION_CONTRACT_TEST=PASS digest=%s"%one.population_manifest_hash);get_tree().quit(0)

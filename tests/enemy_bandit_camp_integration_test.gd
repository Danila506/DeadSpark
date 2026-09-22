extends Node
const CAMP1=preload("res://Enemies/Bandits/bandit_base.tscn")
const CAMP2=preload("res://Enemies/Bandits/BanditBase2.tscn")
const PASS=preload("res://World/Generation/enemy_population_pass.gd")
func _ready():call_deferred("_run")
func _assert(v,m):if not v:push_error("Bandit camp: "+m);get_tree().quit(1)
func _camp(scene:PackedScene,id:String)->Node:
	var c:=scene.instantiate();c.world_generated_mode=true;c.generated_object_id=id;add_child(c);return c
func _manifest(seed:int,camps:Array)->Dictionary:return (PASS.new() as EnemyPopulationPass).build_manifests(seed,camps)
func _run():
	var a:=_camp(CAMP1,"poi/camp_a");var b:=_camp(CAMP2,"poi/camp_b");await get_tree().process_frame
	_assert(EnemySpawnMarkerProviderContract.validate(a).valid and EnemySpawnMarkerProviderContract.validate(b).valid,"provider")
	_assert(a.get_enemy_spawn_markers().size()==4 and b.get_enemy_spawn_markers().size()==4,"markers")
	var one:=_manifest(1337,[a,b]);var two:=_manifest(1337,[b,a]);_assert(one.blocking_errors.is_empty() and one.population_manifest_hash==two.population_manifest_hash,"determinism/order")
	var varied:=_manifest(7331,[a,b]);_assert(one.population_manifest_hash!=varied.population_manifest_hash,"variation")
	var raw: Dictionary=one.population_manifests.filter(func(m):return m.owner_generated_object_id=="poi/camp_a")[0];var manifest:=EnemyPopulationManifest.new();manifest.owner_generated_object_id=raw.owner_generated_object_id;manifest.profile_id=raw.profile_id
	for value in raw.records:
		var r:=EnemyPopulationRecord.new();r.population_id=value.population_id;r.owner_generated_object_id=value.owner_generated_object_id;r.marker_id=value.marker_id;r.profile_id=value.profile_id;r.enemy_entry_id=value.enemy_entry_id;r.enemy_resource_key=value.enemy_resource_key;r.position=Vector2(value.position.x,value.position.y);r.ordinal=value.ordinal;r.initial_state=value.initial_state;manifest.records.append(r)
	_assert(a.apply_enemy_population_manifest(manifest).valid,"materialize");var count:=a.get_children().filter(func(n):return n.is_in_group("camp_generated_population")).size();_assert(count==manifest.records.size(),"count")
	_assert(a.apply_enemy_population_manifest(manifest).valid,"idempotent");_assert(a.get_children().filter(func(n):return n.is_in_group("camp_generated_population")).size()==count,"no duplicates")
	for actor in a.get_children():if actor.is_in_group("camp_generated_population"):_assert(actor.has_meta("population_id") and actor.has_meta("population_manifest_hash"),"metadata")
	a.clear_enemy_population();await get_tree().process_frame;_assert(a.get_children().filter(func(n):return n.is_in_group("camp_generated_population")).is_empty(),"cleanup")
	var standalone:=CAMP1.instantiate();standalone.world_generated_mode=false;add_child(standalone);for frame in range(8): await get_tree().process_frame
	_assert(standalone.get_children().filter(func(n):return n is Node2D and not n is EnemySpawnMarker).size()>3,"standalone legacy")
	print("ENEMY_BANDIT_CAMP_INTEGRATION_TEST=PASS digest=%s"%one.population_manifest_hash);get_tree().quit(0)

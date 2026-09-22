extends Control

const PASS = preload("res://World/Generation/loot_population_pass.gd")
const BOX_SCENE = preload("res://World/Boxes/Box1/Box1.tscn")
const MED_SCENE = preload("res://World/medicine_kit.tscn")
const HOUSE_SCENE = preload("res://World/Assets/Houses/House1/house_1.tscn")
const TWO_SCENE = preload("res://World/Assets/Houses/TwoStoriedHouse/twoStoriedHouse.tscn")
const FORESTER_SCENE = preload("res://World/Assets/Houses/ForesterHouse/forester_house.tscn")
const BUNKER_SCENE = preload("res://World/Assets/Bunker/Bunker.tscn")
const BOX_PROFILE = preload("res://Resources/WorldGen/Loot/box_loot_profile.tres")
const MED_PROFILE = preload("res://Resources/WorldGen/Loot/medicine_kit_loot_profile.tres")
const HOUSE_PROFILE = preload("res://Resources/WorldGen/Loot/house1_wardrobe_loot_profile.tres")
const TWO_PROFILE = preload("res://Resources/WorldGen/Loot/two_storied_bedside_loot_profile.tres")
const FORESTER_PROFILE = preload("res://Resources/WorldGen/Loot/forester_wardrobe_loot_profile.tres")
const BUNKER_PROFILE = preload("res://Resources/WorldGen/bunker_empty_loot_profile.tres")

@export var world_seed := 1337
var _provider: Node
var _snapshot: Dictionary = {}
var _profile_changed := false
var _selector: OptionButton
var _seed_input: SpinBox
var _status: TextEdit

func _ready() -> void:
	_build_ui(); _select_provider(0)
	if "--manual-loot-smoke" in OS.get_cmdline_user_args(): call_deferred("_smoke")

func _catalog() -> Array[Dictionary]:
	return [{"name":"Box","scene":BOX_SCENE,"profile":BOX_PROFILE,"kind":"direct","id":"manual_box"},{"name":"Medicine kit","scene":MED_SCENE,"profile":MED_PROFILE,"kind":"direct","id":"manual_medicine"},{"name":"House1","scene":HOUSE_SCENE,"profile":HOUSE_PROFILE,"kind":"building","id":"manual_house"},{"name":"Two-Storied House","scene":TWO_SCENE,"profile":TWO_PROFILE,"kind":"building","id":"manual_two"},{"name":"Forester House","scene":FORESTER_SCENE,"profile":FORESTER_PROFILE,"kind":"building","id":"manual_forester"},{"name":"Bunker","scene":BUNKER_SCENE,"profile":BUNKER_PROFILE,"kind":"building","id":"manual_bunker"}]

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); var panel := VBoxContainer.new(); panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); panel.offset_left=16; panel.offset_top=16; panel.offset_right=-16; panel.offset_bottom=-16; add_child(panel)
	var controls := HBoxContainer.new(); panel.add_child(controls); _selector=OptionButton.new()
	for entry in _catalog():
		_selector.add_item(entry.name)
	_selector.item_selected.connect(_select_provider); controls.add_child(_selector)
	_seed_input=SpinBox.new(); _seed_input.min_value=0; _seed_input.max_value=999999999; _seed_input.value=world_seed; _seed_input.value_changed.connect(func(v): world_seed=int(v)); controls.add_child(_seed_input)
	for pair in [["Generate","generate_manifest"],["Materialize","materialize"],["Opened","mark_opened"],["Remove slot","remove_selected_slot"],["Serialize","serialize_state"],["Clear / restore","restore_new_instance"],["Change seed","change_seed"],["Change profile","change_profile"],["Reset","reset_provider"],["Regenerate unopened","regenerate_unopened"]]:
		var button:=Button.new(); button.text=pair[0]; button.pressed.connect(Callable(self, String(pair[1]))); controls.add_child(button)
	_status=TextEdit.new(); _status.editable=false; _status.custom_minimum_size=Vector2(1200,720); panel.add_child(_status)

func _select_provider(index: int, preserve_snapshot := false) -> void:
	reset_provider(); var entry:=_catalog()[index]; _provider=(entry.scene as PackedScene).instantiate();
	if entry.kind == "direct": _provider.world_generated_loot=true; _provider.generated_container_id=entry.id
	else: _provider.world_generated_mode=true; _provider.building_generated_object_id=entry.id
	_provider.loot_profile=entry.profile; add_child(_provider); if not preserve_snapshot: _snapshot={}; _profile_changed=false; _show("Provider selected. Generate a manifest.")

func generate_manifest() -> void:
	if _provider.get_existing_loot_manifest()!=null: _show("Already generated; use Reset or Regenerate unopened."); return
	var population_pass: LootPopulationPass=PASS.new(); var output:=population_pass.build_manifests(world_seed,[_provider]); if not output.blocking_errors.is_empty(): _show("BLOCKING: "+str(output.blocking_errors)); return
	_provider.apply_loot_manifest(LootContainerManifest.from_canonical(output.loot_manifests[0])); _show("Manifest generated.")
func materialize() -> void: if _provider.get_existing_loot_manifest()==null: generate_manifest(); _show("Manifest materialized into production provider.")
func mark_opened() -> void: _provider.mark_loot_opened(); _show("Marked opened.")
func remove_selected_slot() -> void:
	var manifest: LootContainerManifest=_provider.get_existing_loot_manifest(); if manifest==null or manifest.slots.is_empty(): _show("No removable slot (Bunker is intentionally empty)."); return
	_provider.record_loot_slot_removed(manifest.slots[0].slot_id); _show("First slot removed.")
func serialize_state() -> void: _snapshot=_provider.serialize_loot_state(); _show("State serialized.")
func restore_new_instance() -> void:
	if _snapshot.is_empty(): serialize_state()
	var index:=_selector.selected; _provider.queue_free(); await get_tree().process_frame; _provider=null; _select_provider(index, true); var result: Dictionary=_provider.restore_loot_state(_snapshot); _show("Restore: "+str(result))
func change_seed() -> void: world_seed+=1; _seed_input.value=world_seed; _show("Seed changed; saved state remains authoritative.")
func change_profile() -> void:
	if _provider.loot_profile==BUNKER_PROFILE: _show("Bunker keeps explicit empty profile."); return
	var profile: LootProfile=_provider.loot_profile.duplicate(true); profile.profile_id+="_changed"; _provider.loot_profile=profile; _profile_changed=true; _show("Profile changed; restore will retain saved manifest.")
func reset_provider() -> void: if is_instance_valid(_provider): _provider.queue_free(); _provider=null
func regenerate_unopened() -> void: var index:=_selector.selected; _select_provider(index); generate_manifest()
func _show(prefix: String) -> void:
	if _provider==null: return
	var manifest: LootContainerManifest=_provider.get_existing_loot_manifest(); var lines=[prefix,"seed=%d provider=%s"%[world_seed,_selector.get_item_text(_selector.selected)],"container_id=%s"%_provider.get_loot_container_id(),"profile_id=%s"%(_provider.loot_profile.profile_id),"persistence_key=%s"%_provider.get_loot_persistence_key()]
	if manifest!=null:
		lines.append("manifest_hash="+manifest.manifest_hash()); lines.append("state="+_provider.get_loot_persistence_state()); lines.append("slots:")
		for slot in manifest.slots: lines.append("  %s | %s x%d"%[slot.slot_id,slot.item_resource_key,slot.quantity])
		lines.append("removed="+str(_provider.get_removed_loot_slot_ids())); lines.append("aggregate_loot_hash="+GenerationHashes.sha256_of(manifest.canonical_record())); lines.append("snapshot_hash="+GenerationHashes.sha256_of(_provider.serialize_loot_state()))
		var count=0; for item in _provider.get("loot_slots") if "loot_slots" in _provider else []: if item!=null: count+=1
		lines.append("materialized_item_count=%d"%count)
	_status.text="\n".join(lines)
func _smoke() -> void:
	generate_manifest(); _assert(_provider.get_existing_loot_manifest()!=null,"box manifest"); serialize_state(); await restore_new_instance(); _assert(_provider.get_existing_loot_manifest()!=null,"box restore"); _select_provider(5); generate_manifest(); _assert((_provider.get_existing_loot_manifest() as LootContainerManifest).slots.is_empty(),"bunker empty"); print("MANUAL_LOOT_VALIDATION_SMOKE=PASS seed=1337"); get_tree().quit(0)
func _assert(ok: bool, message: String) -> void: if not ok: push_error("Manual loot smoke: "+message); get_tree().quit(1)

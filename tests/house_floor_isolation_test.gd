extends Node

const TWO_STORIED_HOUSE_SCENE := preload("res://World/Assets/Houses/TwoStoriedHouse/twoStoriedHouse.tscn")
const HOUSE_ONE_SCENE := preload("res://World/Assets/Houses/House1/house_1.tscn")
const FORESTER_HOUSE_SCENE := preload("res://World/Assets/Houses/ForesterHouse/forester_house.tscn")
const FORESTER_HOUSE_TWO_SCENE := preload("res://World/Assets/Houses/ForesterHouse2/forester_house2.tscn")
const BUNKER_SCENE := preload("res://World/Assets/Bunker/Bunker.tscn")
const PICKUP_SCENE := preload("res://items/scenes/pickup_item.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var single_house := HOUSE_ONE_SCENE.instantiate()
	add_child(single_house)
	_check(single_house.get_node("HouseInside").visible, "single-storey floor remains visible below the facade outside")
	_check(single_house.get_node("HouseInside").z_index < single_house.get_node("HouseOutside").z_index, "single-storey floor is below the facade")
	single_house.free()
	_check_outside_floor_underlay(FORESTER_HOUSE_SCENE, "forester house one")
	_check_outside_floor_underlay(FORESTER_HOUSE_TWO_SCENE, "forester house two")
	_check_outside_floor_underlay(BUNKER_SCENE, "bunker")

	var house := TWO_STORIED_HOUSE_SCENE.instantiate()
	add_child(house)
	var player := CharacterBody2D.new()
	player.add_to_group(&"player")
	add_child(player)

	var floor_one_pickup := _create_scoped_pickup(house.global_position, 1)
	var floor_two_pickup := _create_scoped_pickup(house.global_position, 2)
	await get_tree().process_frame

	_check(house.floor1_root.visible and not house.floor2_root.visible, "floor one remains as the doorway underlay outside")
	_check(house.floor1_sprite.z_index < house.outside_sprite.z_index, "floor-one underlay is below the facade")
	house._on_shadow_body_entered(player)
	_check(house.outside_sprite.z_index == house.OUTSIDE_HOUSE_OCCLUSION_Z, "facade occludes a player behind the house")
	_check(is_equal_approx(house.outside_sprite.modulate.a, 1.0), "facade remains opaque while occluding the player")
	house._on_shadow_body_exited(player)
	_check(house.outside_sprite.z_index == house.OUTSIDE_HOUSE_Z, "facade returns to normal Y-sort after the player leaves the rear zone")
	_check(house.collision_outside.process_mode == Node.PROCESS_MODE_INHERIT, "outside collision is active outside")
	_check(house.collision_floor1.process_mode == Node.PROCESS_MODE_DISABLED, "floor-one collision is inactive outside")
	_check(house.collision_floor2.process_mode == Node.PROCESS_MODE_DISABLED, "floor-two collision is inactive outside")
	_check(not floor_one_pickup.visible and not floor_two_pickup.visible, "indoor pickups are hidden outside")

	house._on_house_body_entered(player)
	_check(house.floor1_root.visible and not house.floor2_root.visible, "only floor one is rendered after entering")
	_check(house.collision_outside.process_mode == Node.PROCESS_MODE_DISABLED, "outside collision is disabled inside")
	_check(house.collision_floor1.process_mode == Node.PROCESS_MODE_INHERIT, "floor-one collision is active on floor one")
	_check(floor_one_pickup.visible and not floor_two_pickup.visible, "only floor-one pickup is visible on floor one")
	floor_one_pickup._on_body_entered(player)
	_check(NearbyItemsManager.get_items().has(floor_one_pickup), "floor-one pickup becomes available nearby")
	var other_player := CharacterBody2D.new()
	other_player.set_meta(house.INSIDE_HOUSE_ANCHOR_META, house.global_position)
	other_player.set_meta(house.INSIDE_HOUSE_FLOOR_META, house.FLOOR_ONE)
	add_child(other_player)

	house.current_floor = house.FLOOR_TWO
	house._sync_inside_player_floor_state()
	house._update_floor_visual()
	_check(int(other_player.get_meta(house.INSIDE_HOUSE_FLOOR_META)) == house.FLOOR_ONE, "one player's floor transition changed another player's floor")
	_check(not house.floor1_root.visible and house.floor2_root.visible, "only floor two is rendered after transition")
	_check(house.collision_floor1.process_mode == Node.PROCESS_MODE_DISABLED, "floor-one collision is inactive on floor two")
	_check(house.collision_floor2.process_mode == Node.PROCESS_MODE_INHERIT, "floor-two collision is active on floor two")
	_check(house.collision_floor2.get_node_or_null("ExitBoundaryTop") != null, "floor two has a top exit boundary")
	_check(house.collision_floor2.get_node_or_null("ExitBoundaryBottom") != null, "floor two has a bottom exit boundary")
	_check(house.collision_floor2.get_node_or_null("ExitBoundaryLeft") != null, "floor two has a left exit boundary")
	_check(house.collision_floor2.get_node_or_null("ExitBoundaryRight") != null, "floor two has a right exit boundary")
	_check(not floor_one_pickup.visible and floor_two_pickup.visible, "floor-one pickup is hidden on floor two")
	_check(not NearbyItemsManager.get_items().has(floor_one_pickup), "floor-one pickup cannot remain available on floor two")

	house._on_house_body_exited(player)
	_check(house.player_in_house, "player cannot leave the house directly from floor two")
	_check(player.is_in_group(house.INSIDE_HOUSE_GROUP), "floor-two exit attempt preserves inside-house state")
	house.current_floor = house.FLOOR_ONE
	house._sync_inside_player_floor_state()
	house._update_floor_visual()
	house._on_house_body_exited(player)
	_check(not floor_one_pickup.visible and not floor_two_pickup.visible, "indoor pickups are hidden again after exit")
	_check(house.collision_outside.process_mode == Node.PROCESS_MODE_INHERIT, "outside collision is restored after exit")
	_check(house.collision_floor1.process_mode == Node.PROCESS_MODE_DISABLED, "interior collision is disabled after exit")
	other_player.queue_free()

	if not _failures.is_empty():
		for failure in _failures:
			push_error("House floor isolation: " + failure)
		get_tree().quit(1)
		return
	print("HOUSE_FLOOR_ISOLATION_TEST=PASS")
	get_tree().quit(0)


func _check_outside_floor_underlay(scene: PackedScene, label: String) -> void:
	var building := scene.instantiate()
	add_child(building)
	var inside := building.get_node("BunkerInside" if label == "bunker" else "ForesterHouseInside") as Sprite2D
	var outside := building.get_node("BunkerOutside" if label == "bunker" else "ForesterHouseOutside") as Sprite2D
	_check(inside.visible, "%s interior remains visible below the facade outside" % label)
	_check(inside.z_index < outside.z_index, "%s interior is below the facade" % label)
	building.free()


func _create_scoped_pickup(anchor: Vector2, floor_number: int) -> Node:
	var pickup := PICKUP_SCENE.instantiate()
	pickup.configure_visibility_scope({
		"anchor": {"x": anchor.x, "y": anchor.y},
		"floor": floor_number
	})
	add_child(pickup)
	return pickup


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

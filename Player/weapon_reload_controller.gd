extends RefCounted
class_name WeaponReloadController

const MIN_RELOAD_TIME_SEC: float = 0.35

var controller
var is_reloading: bool = false
var reload_timer: float = 0.0
var reload_uses_action_bar: bool = false


func _init(owner) -> void:
	controller = owner


func update(delta: float) -> void:
	if not is_reloading:
		return
	if reload_uses_action_bar:
		return

	reload_timer -= delta
	if reload_timer <= 0.0:
		finish_reload()


func try_reload() -> void:
	if controller.current_weapon == null:
		return
	if is_reloading:
		return
	if not InputMap.has_action("reload"):
		return
	if not Input.is_action_just_pressed("reload"):
		return

	start_reload()


func start_reload() -> void:
	if controller.current_weapon == null:
		return
	if is_reloading:
		return
	if controller._get_ammo_in_mag() >= controller.current_weapon.magazine_size:
		return
	if controller._get_reserve_ammo() <= 0:
		return

	is_reloading = true
	reload_timer = max(controller.current_weapon.reload_time_sec, MIN_RELOAD_TIME_SEC)
	reload_uses_action_bar = false
	controller.cursor_heat_ratio = 0.0
	play_reload_sfx()

	if reload_timer <= 0.0:
		finish_reload()
		return

	if controller.player != null and controller.player.has_method("start_timed_action"):
		if controller.player.start_timed_action(reload_timer, Callable(controller, "_finish_reload"), "Перезарядка", false):
			reload_uses_action_bar = true
			return


func cancel_reload() -> void:
	if not is_reloading and reload_timer <= 0.0 and not reload_uses_action_bar:
		return

	if controller.player != null and reload_uses_action_bar and controller.player.has_method("cancel_timed_action"):
		controller.player.call("cancel_timed_action", Callable(controller, "_finish_reload"))

	is_reloading = false
	reload_timer = 0.0
	reload_uses_action_bar = false

	if controller.weapon_reload_sfx != null and controller.weapon_reload_sfx.playing:
		controller.weapon_reload_sfx.stop()


func finish_reload() -> void:
	if not is_reloading:
		return

	if controller.current_weapon == null:
		is_reloading = false
		reload_timer = 0.0
		reload_uses_action_bar = false
		return

	var ammo_in_mag: int = controller._get_ammo_in_mag()
	var reserve_ammo: int = controller._get_reserve_ammo()
	var needed_ammo: int = max(controller.current_weapon.magazine_size - ammo_in_mag, 0)
	var ammo_to_load: int = min(needed_ammo, reserve_ammo)

	controller._set_ammo_state(ammo_in_mag + ammo_to_load, reserve_ammo - ammo_to_load)
	is_reloading = false
	reload_timer = 0.0
	reload_uses_action_bar = false
	controller.cursor_heat_ratio = 0.0
	controller._reset_aim_settle()


func play_reload_sfx() -> void:
	if controller.current_weapon == null:
		return
	if controller.current_weapon.reload_sound == null:
		return
	if controller.weapon_reload_sfx == null or not controller.weapon_reload_sfx.is_inside_tree():
		return

	controller.weapon_reload_sfx.stream = controller.current_weapon.reload_sound
	controller.weapon_reload_sfx.volume_db = controller.current_weapon.reload_sound_volume_db
	if controller.weapon_reload_sfx.playing:
		controller.weapon_reload_sfx.stop()
	controller.weapon_reload_sfx.play()

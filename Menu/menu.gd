extends Node2D

const SAVE_FILE_PATH: String = "user://savegame.json"
const DEFAULT_LEVEL_PATH: String = "res://level.tscn"
const NETWORK_WORLD_PATH: String = "res://World/network_test_world.tscn"
const DONATE_URL: String = "https://boosty.to/deadspark/donate"
const LAN_CONNECT_TIMEOUT_SEC: float = 10.0

@onready var continue_button: Button = $CenterContainer/MenuPanel/VBox/Continue
@onready var soundtrack_player: AudioStreamPlayer = $SoundTrack
@onready var background_rect: ColorRect = $Background
@onready var glow_top_rect: ColorRect = $GlowTop
@onready var center_container: CenterContainer = $CenterContainer
@onready var debug_status_label: Label = $DebugStatusLabel
@onready var main_menu_panel: PanelContainer = $CenterContainer/MenuPanel
@onready var lan_panel: PanelContainer = $CenterContainer/LanPanel
@onready var lan_status_label: Label = $CenterContainer/LanPanel/VBoxLan/LanStatusLabel
@onready var lan_ip_input: LineEdit = $CenterContainer/LanPanel/VBoxLan/IPInput
@onready var lan_port_input: LineEdit = $CenterContainer/LanPanel/VBoxLan/PortInput

var _is_connecting_lan: bool = false
var _lan_reconnect_attempted: bool = false
var _lan_smoke_mode: String = ""
var _lan_smoke_host: String = "127.0.0.1"
var _lan_smoke_port: int = 2456


func _ready() -> void:
	_parse_cli_lan_smoke_args()
	_disable_soundtrack_for_headless()
	_fit_menu_to_viewport()
	if not get_viewport().size_changed.is_connected(_fit_menu_to_viewport):
		get_viewport().size_changed.connect(_fit_menu_to_viewport)
	_update_continue_button_state()
	_set_debug_status("Status: menu ready")
	if NetworkManager != null:
		if not NetworkManager.server_started.is_connected(_on_network_server_started):
			NetworkManager.server_started.connect(_on_network_server_started)
		if not NetworkManager.connected_to_server.is_connected(_on_network_connected_to_server):
			NetworkManager.connected_to_server.connect(_on_network_connected_to_server)
		if not NetworkManager.connection_failed.is_connected(_on_network_connection_failed):
			NetworkManager.connection_failed.connect(_on_network_connection_failed)
		if not NetworkManager.connection_rejected.is_connected(_on_network_connection_rejected):
			NetworkManager.connection_rejected.connect(_on_network_connection_rejected)
	if not _lan_smoke_mode.is_empty():
		call_deferred("_run_lan_smoke_mode")


func _fit_menu_to_viewport() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	if viewport_size == Vector2.ZERO:
		return

	if background_rect != null:
		background_rect.position = Vector2.ZERO
		background_rect.size = viewport_size

	if glow_top_rect != null:
		glow_top_rect.position = Vector2.ZERO
		glow_top_rect.size = Vector2(viewport_size.x, maxf(viewport_size.y * 0.46, 1.0))

	if center_container != null:
		center_container.position = Vector2.ZERO
		center_container.size = viewport_size


func _on_new_game_pressed() -> void:
	if InventoryManager != null and InventoryManager.has_method("reset_state"):
		InventoryManager.reset_state()

	if GameSaveManager != null and GameSaveManager.has_method("start_new_game"):
		GameSaveManager.start_new_game(DEFAULT_LEVEL_PATH, SAVE_FILE_PATH)
	else:
		_write_save(DEFAULT_LEVEL_PATH)
	get_tree().change_scene_to_file(DEFAULT_LEVEL_PATH)


func _on_continue_pressed() -> void:
	if GameSaveManager != null and GameSaveManager.has_method("load_game"):
		var load_result: int = int(GameSaveManager.load_game())
		if load_result == OK:
			return

	var save_data: Dictionary = _read_save()
	if save_data.is_empty():
		_update_continue_button_state()
		return

	var scene_path: String = String(save_data.get("scene_path", DEFAULT_LEVEL_PATH))
	if scene_path.is_empty():
		scene_path = DEFAULT_LEVEL_PATH

	if not ResourceLoader.exists(scene_path):
		scene_path = DEFAULT_LEVEL_PATH

	get_tree().change_scene_to_file(scene_path)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_donate_pressed() -> void:
	OS.shell_open(DONATE_URL)


func _on_lan_mvp_pressed() -> void:
	print("LAN MVP button pressed")
	_set_debug_status("LAN MVP button pressed")
	_show_lan_panel()
	var ips: PackedStringArray = NetworkManager.get_local_ipv4_candidates() if NetworkManager != null else PackedStringArray()
	if ips.is_empty():
		_set_lan_status("Status: LAN menu ready. Local IPv4 not found")
	else:
		_set_lan_status("Status: LAN menu ready. Local IPv4: %s" % ", ".join(ips))


func _disable_soundtrack_for_headless() -> void:
	if soundtrack_player == null:
		return
	if DisplayServer.get_name() != "headless":
		return
	if soundtrack_player.playing:
		soundtrack_player.stop()
	soundtrack_player.autoplay = false
	soundtrack_player.stream = null


func _exit_tree() -> void:
	if NetworkManager != null:
		if NetworkManager.server_started.is_connected(_on_network_server_started):
			NetworkManager.server_started.disconnect(_on_network_server_started)
		if NetworkManager.connected_to_server.is_connected(_on_network_connected_to_server):
			NetworkManager.connected_to_server.disconnect(_on_network_connected_to_server)
		if NetworkManager.connection_failed.is_connected(_on_network_connection_failed):
			NetworkManager.connection_failed.disconnect(_on_network_connection_failed)
		if NetworkManager.connection_rejected.is_connected(_on_network_connection_rejected):
			NetworkManager.connection_rejected.disconnect(_on_network_connection_rejected)

	if soundtrack_player == null:
		return
	if soundtrack_player.playing:
		soundtrack_player.stop()
	# Release stream reference to avoid playback resources lingering on shutdown.
	soundtrack_player.stream = null


func _update_continue_button_state() -> void:
	if continue_button == null:
		return

	continue_button.disabled = not FileAccess.file_exists(SAVE_FILE_PATH)


func _write_save(scene_path: String) -> void:
	var file: FileAccess = FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if file == null:
		return

	var data: Dictionary = {
		"scene_path": scene_path,
		"saved_at_unix": Time.get_unix_time_from_system()
	}
	file.store_string(JSON.stringify(data))
	file.flush()


func _read_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_FILE_PATH):
		return {}

	var file: FileAccess = FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	if file == null:
		return {}

	var raw_json: String = file.get_as_text()
	if raw_json.is_empty():
		return {}

	var parsed: Variant = JSON.parse_string(raw_json)
	if parsed is Dictionary:
		return parsed

	return {}


func _set_debug_status(message: String) -> void:
	if debug_status_label == null:
		return
	debug_status_label.text = message


func _on_host_lan_pressed() -> void:
	print("Host button pressed")
	_is_connecting_lan = false
	_lan_reconnect_attempted = false
	var port: int = _parse_port_or_default()
	_set_lan_status("Starting LAN host on port %d..." % port)
	var host_result: int = NetworkManager.host_lan_game(port)
	if host_result != OK:
		_set_lan_status("Host failed (error %d)" % host_result)
		return
	_set_lan_status("LAN host created. Waiting for server start...")


func _on_join_lan_pressed() -> void:
	print("Join button pressed")
	var ip: String = lan_ip_input.text.strip_edges()
	if ip.is_empty():
		_set_lan_status("Enter host IP first")
		return
	var port: int = _parse_port_or_default()
	_is_connecting_lan = true
	_lan_reconnect_attempted = false
	_set_lan_status("Connecting to %s:%d ..." % [ip, port])
	var join_result: int = NetworkManager.join_lan_game(ip, port)
	if join_result != OK:
		_is_connecting_lan = false
		_set_lan_status("Join failed (error %d)" % join_result)
		return
	_watch_lan_connect_timeout(ip, port)


func _on_join_localhost_pressed() -> void:
	var port: int = _parse_port_or_default()
	var ip: String = "127.0.0.1"
	_is_connecting_lan = true
	_lan_reconnect_attempted = false
	_set_lan_status("Connecting to %s:%d ..." % [ip, port])
	var join_result: int = NetworkManager.join_lan_game(ip, port)
	if join_result != OK:
		_is_connecting_lan = false
		_set_lan_status("Join failed (error %d)" % join_result)
		return
	_watch_lan_connect_timeout(ip, port)


func _on_back_to_menu_pressed() -> void:
	if NetworkManager != null and NetworkManager.get_state() != NetworkManager.NetworkState.IDLE:
		NetworkManager.reset_session_state(false)
	_is_connecting_lan = false
	_lan_reconnect_attempted = false
	_hide_lan_panel()
	_set_lan_status("Status: idle")


func _show_lan_panel() -> void:
	main_menu_panel.visible = false
	lan_panel.visible = true


func _hide_lan_panel() -> void:
	lan_panel.visible = false
	main_menu_panel.visible = true


func _set_lan_status(message: String) -> void:
	lan_status_label.text = message
	_set_debug_status(message)


func _parse_port_or_default() -> int:
	var port_text: String = lan_port_input.text.strip_edges()
	if port_text.is_empty() or not port_text.is_valid_int():
		return 2456
	var port: int = int(port_text)
	if port <= 0 or port > 65535:
		return 2456
	return port


func _on_network_server_started() -> void:
	_is_connecting_lan = false
	_lan_reconnect_attempted = false
	_set_lan_status("LAN server started. Loading world...")
	get_tree().change_scene_to_file.bind(NETWORK_WORLD_PATH).call_deferred()


func _on_network_connected_to_server() -> void:
	_is_connecting_lan = false
	_lan_reconnect_attempted = false
	_set_lan_status("Connected to server. Loading world...")
	get_tree().change_scene_to_file.bind(NETWORK_WORLD_PATH).call_deferred()


func _on_network_connection_failed() -> void:
	if _try_lan_reconnect():
		return
	_is_connecting_lan = false
	var reason: String = NetworkManager.get_last_error() if NetworkManager != null else ""
	if reason.is_empty():
		_set_lan_status("Connection failed")
	else:
		_set_lan_status("Connection failed: %s" % reason)


func _on_network_connection_rejected(reason: String) -> void:
	if _try_lan_reconnect():
		return
	_is_connecting_lan = false
	_set_lan_status("Connection rejected: %s" % reason)


func _watch_lan_connect_timeout(ip: String, port: int) -> void:
	_connect_timeout_impl(ip, port)


func _connect_timeout_impl(ip: String, port: int) -> void:
	await get_tree().create_timer(LAN_CONNECT_TIMEOUT_SEC).timeout
	if not _is_connecting_lan:
		return
	print("Connection failed")
	NetworkManager.disconnect_from_network()
	if _try_lan_reconnect():
		return
	_is_connecting_lan = false
	_set_lan_status("Connection timeout to %s:%d" % [ip, port])


func _try_lan_reconnect() -> bool:
	if not _is_connecting_lan:
		return false
	if _lan_reconnect_attempted:
		return false
	if NetworkManager == null or not NetworkManager.can_reconnect_last_join():
		return false
	_lan_reconnect_attempted = true
	_set_lan_status("Retrying LAN connection...")
	var reconnect_result: int = NetworkManager.reconnect_last_join()
	if reconnect_result != OK:
		return false
	return true


func _parse_cli_lan_smoke_args() -> void:
	for raw_arg_variant: Variant in OS.get_cmdline_user_args():
		var raw_arg: String = String(raw_arg_variant)
		if not raw_arg.begins_with("--"):
			continue
		var parts: PackedStringArray = raw_arg.substr(2).split("=", false, 1)
		if parts.size() != 2:
			continue
		var key: String = parts[0]
		var value: String = parts[1]
		match key:
			"lan-smoke-mode":
				_lan_smoke_mode = value.to_lower()
			"lan-host":
				if not value.strip_edges().is_empty():
					_lan_smoke_host = value.strip_edges()
			"lan-port":
				if value.is_valid_int():
					var parsed_port: int = int(value)
					if parsed_port > 0 and parsed_port <= 65535:
						_lan_smoke_port = parsed_port


func _run_lan_smoke_mode() -> void:
	_show_lan_panel()
	lan_port_input.text = str(_lan_smoke_port)
	lan_ip_input.text = _lan_smoke_host
	if _lan_smoke_mode == "host":
		_on_host_lan_pressed()
		return
	if _lan_smoke_mode == "client":
		_on_join_lan_pressed()

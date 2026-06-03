extends Node2D

@export_file("*.tscn") var new_game_scene_path: String = "res://level.tscn"
@export_file("*.tscn") var settings_scene_path: String = ""
@export var save_file_path: String = "user://savegame.json"
@export var legacy_save_file_path: String = "user://savegame.save"
@export var soundtrack_stream_path: String = "res://Assets/AudioWaw/SoundTracks/DeadSparkMainTheme.wav"
@export var desktop_panel_width_ratio: float = 0.33
@export var mobile_panel_width_ratio: float = 0.88
@export var min_panel_width: float = 340.0
@export var max_panel_width: float = 520.0
@export var panel_vertical_margin: float = 34.0
@export var panel_side_margin: float = 42.0
@export var title_font: Font
@export var button_font: Font

const NETWORK_WORLD_PATH: String = "res://World/network_test_world.tscn"
const DONATE_URL: String = "https://boosty.to/deadspark/donate"
const BUTTON_ARROW_SUFFIX: String = "    >"
const LAN_CONNECT_TIMEOUT_SEC: float = 10.0
const DEFAULT_LAN_PORT: int = 2456

@onready var soundtrack_player: AudioStreamPlayer = $SoundTrack
@onready var main_menu_root: Control = %MainMenuRoot
@onready var main_panel: PanelContainer = %MainPanel
@onready var content_vbox: VBoxContainer = %MenuContent
@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var continue_button: Button = %ContinueButton
@onready var new_game_button: Button = %NewGameButton
@onready var lan_button: Button = %LanButton
@onready var settings_button: Button = %SettingsButton
@onready var language_button: Button = %LanguageButton
@onready var support_button: Button = %SupportButton
@onready var exit_button: Button = %ExitButton
@onready var status_label: Label = %StatusLabel
@onready var lan_overlay: PanelContainer = %LanOverlay
@onready var lan_status_label: Label = %LanStatusLabel
@onready var lan_ip_input: LineEdit = %LanIpInput
@onready var lan_port_input: LineEdit = %LanPortInput
@onready var lan_hosts_select: OptionButton = %LanHostsSelect

var _button_base_text: Dictionary = {}
var _is_connecting_lan: bool = false
var _lan_reconnect_attempted: bool = false
var _lan_discovery_hosts: Dictionary = {}
var _lan_discovery_host_keys: Array[String] = []


func _ready() -> void:
	_disable_soundtrack_for_headless()
	_setup_soundtrack_for_runtime()
	_apply_optional_fonts()
	_setup_buttons()
	_update_continue_button_state()
	update_layout_for_screen_size()
	if not get_viewport().size_changed.is_connected(update_layout_for_screen_size):
		get_viewport().size_changed.connect(update_layout_for_screen_size)
	_setup_network_signals()
	_setup_localization_signals()
	_apply_menu_texts()
	_hide_lan_overlay()
	_set_status("")


func _exit_tree() -> void:
	if get_viewport() != null and get_viewport().size_changed.is_connected(update_layout_for_screen_size):
		get_viewport().size_changed.disconnect(update_layout_for_screen_size)
	_disconnect_localization_signals()
	_disconnect_network_signals()
	if soundtrack_player != null and soundtrack_player.playing:
		soundtrack_player.stop()
	if soundtrack_player != null:
		soundtrack_player.stream = null


func update_layout_for_screen_size() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size == Vector2.ZERO or main_menu_root == null or main_panel == null:
		return

	var is_mobile_layout := viewport_size.x < 900.0 or viewport_size.y > viewport_size.x
	var panel_width: float
	if is_mobile_layout:
		var max_mobile_width := viewport_size.x * 0.92
		var min_mobile_width := minf(min_panel_width, max_mobile_width)
		panel_width = clampf(viewport_size.x * mobile_panel_width_ratio, min_mobile_width, max_mobile_width)
	else:
		panel_width = clampf(viewport_size.x * desktop_panel_width_ratio, min_panel_width, max_panel_width)

	var top_margin := maxf(18.0, minf(panel_vertical_margin, viewport_size.y * 0.05))
	var panel_height := maxf(viewport_size.y - top_margin * 2.0, 420.0)
	panel_height = minf(panel_height, viewport_size.y - top_margin * 2.0)
	var panel_x := (viewport_size.x - panel_width) * 0.5 if is_mobile_layout else panel_side_margin
	main_panel.position = Vector2(panel_x, top_margin)
	main_panel.size = Vector2(panel_width, panel_height)
	main_panel.custom_minimum_size = Vector2(panel_width, panel_height)

	var button_height := clampf(viewport_size.y * 0.07, 56.0, 72.0)
	for button in _get_menu_buttons():
		button.custom_minimum_size = Vector2(0.0, button_height)

	var compact := viewport_size.y < 760.0
	content_vbox.add_theme_constant_override("separation", 10 if compact else 13)
	title_label.add_theme_font_size_override("font_size", 48 if compact else 64)
	subtitle_label.add_theme_font_size_override("font_size", 15 if compact else 18)
	status_label.add_theme_font_size_override("font_size", 14 if compact else 16)


func _setup_buttons() -> void:
	var button_configs: Array[Dictionary] = [
		{"button": continue_button, "text": "Продолжить", "action": Callable(self, "_on_continue_pressed")},
		{"button": new_game_button, "text": "Новая игра", "action": Callable(self, "_on_new_game_pressed")},
		{"button": lan_button, "text": "LAN", "action": Callable(self, "_on_lan_pressed")},
		{"button": settings_button, "text": "Настройки", "action": Callable(self, "_on_settings_pressed")},
		{"button": language_button, "text": "Язык: Русский", "action": Callable(self, "_on_language_pressed")},
		{"button": support_button, "text": "Поддержать проект", "action": Callable(self, "_on_support_pressed")},
		{"button": exit_button, "text": "Выход", "action": Callable(self, "handle_exit")},
	]

	for config in button_configs:
		var button := config["button"] as Button
		var base_text := String(config["text"])
		button.text = base_text
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_button_base_text[button] = base_text
		button.pressed.connect(config["action"])
		button.mouse_entered.connect(_set_button_active.bind(button, true))
		button.mouse_exited.connect(_set_button_active.bind(button, false))
		button.focus_entered.connect(_set_button_active.bind(button, true))
		button.focus_exited.connect(_set_button_active.bind(button, false))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _get_menu_buttons() -> Array[Button]:
	return [
		continue_button,
		new_game_button,
		lan_button,
		settings_button,
		language_button,
		support_button,
		exit_button,
	]


func _set_button_active(button: Button, active: bool) -> void:
	if button == null or button.disabled:
		return
	var base_text := String(_button_base_text.get(button, button.text))
	button.text = base_text + BUTTON_ARROW_SUFFIX if active else base_text


func _apply_optional_fonts() -> void:
	if title_font != null:
		title_label.add_theme_font_override("font", title_font)
	if button_font != null:
		for button in _get_menu_buttons():
			button.add_theme_font_override("font", button_font)


func _setup_localization_signals() -> void:
	if LocalizationManager == null:
		return
	if not LocalizationManager.language_changed.is_connected(_on_language_changed):
		LocalizationManager.language_changed.connect(_on_language_changed)


func _disconnect_localization_signals() -> void:
	if LocalizationManager == null:
		return
	if LocalizationManager.language_changed.is_connected(_on_language_changed):
		LocalizationManager.language_changed.disconnect(_on_language_changed)


func _on_language_changed(_locale: String) -> void:
	_apply_menu_texts()


func _apply_menu_texts() -> void:
	subtitle_label.text = tr("Выживание в зоне отчуждения")
	_set_button_base_text(continue_button, tr("Продолжить"))
	_set_button_base_text(new_game_button, tr("Новая игра"))
	_set_button_base_text(lan_button, "LAN")
	_set_button_base_text(settings_button, tr("Настройки"))
	_set_button_base_text(support_button, tr("Поддержать проект"))
	_set_button_base_text(exit_button, tr("Выход"))
	_update_language_button_label()
	_update_lan_ui_texts()


func _update_language_button_label() -> void:
	var language_name := "Русский"
	if LocalizationManager != null and LocalizationManager.has_method("get_language") and LocalizationManager.has_method("get_display_name"):
		var current_locale := String(LocalizationManager.get_language())
		language_name = String(LocalizationManager.get_display_name(current_locale))
	_set_button_base_text(language_button, "%s %s" % [tr("Язык:"), language_name])


func _set_button_base_text(button: Button, text: String) -> void:
	if button == null:
		return
	_button_base_text[button] = text
	button.text = text


func _update_continue_button_state() -> void:
	if continue_button == null:
		return
	continue_button.disabled = not _has_valid_save()
	if continue_button.disabled:
		_set_button_base_text(continue_button, tr("Продолжить"))


func _has_valid_save() -> bool:
	if FileAccess.file_exists(save_file_path):
		var save_data := _read_save(save_file_path)
		if save_data.is_empty():
			return true
		var scene_path := _sanitize_scene_path(String(save_data.get("scene_path", new_game_scene_path)))
		return ResourceLoader.exists(scene_path)
	return FileAccess.file_exists(legacy_save_file_path)


func _on_continue_pressed() -> void:
	if GameSaveManager != null and GameSaveManager.has_method("load_game"):
		var load_result := int(GameSaveManager.load_game())
		if load_result == OK:
			return

	var save_data := _read_save(save_file_path)
	var scene_path := _sanitize_scene_path(String(save_data.get("scene_path", new_game_scene_path)))
	_change_scene_if_exists(scene_path, "continue")


func _on_new_game_pressed() -> void:
	if InventoryManager != null and InventoryManager.has_method("reset_state"):
		InventoryManager.reset_state()
	if GameSaveManager != null and GameSaveManager.has_method("start_new_game"):
		GameSaveManager.start_new_game(new_game_scene_path, save_file_path)
	else:
		_write_save(new_game_scene_path)
	_change_scene_if_exists(new_game_scene_path, "new game")


func _on_lan_pressed() -> void:
	_show_lan_overlay()
	_lan_discovery_hosts.clear()
	_lan_discovery_host_keys.clear()
	_reset_found_hosts_select()
	if NetworkManager != null and NetworkManager.has_method("get_local_ipv4_candidates"):
		var ips: PackedStringArray = NetworkManager.get_local_ipv4_candidates()
		if ips.is_empty():
			_set_lan_status("LAN: локальный IPv4 не найден")
		else:
			_set_lan_status("LAN: IP %s" % ", ".join(ips))
	_on_find_lan_hosts_pressed()


func _on_settings_pressed() -> void:
	if settings_scene_path.strip_edges().is_empty() or not ResourceLoader.exists(settings_scene_path):
		push_warning("MainMenu: settings_scene_path is not configured.")
		_set_status("Настройки пока недоступны")
		return
	get_tree().change_scene_to_file(settings_scene_path)


func _on_language_pressed() -> void:
	if LocalizationManager == null:
		return
	var locales: Array[String] = ["ru", "en", "id", "es", "pt"]
	if LocalizationManager.has_method("get_supported_locales"):
		locales = LocalizationManager.get_supported_locales()
	if locales.is_empty():
		return
	var current_locale := "ru"
	if LocalizationManager.has_method("get_language"):
		current_locale = String(LocalizationManager.get_language())
	var current_index := locales.find(current_locale)
	if current_index < 0:
		current_index = 0
	var next_locale: String = locales[(current_index + 1) % locales.size()]
	if LocalizationManager.has_method("set_language"):
		LocalizationManager.set_language(next_locale, true)


func _on_support_pressed() -> void:
	OS.shell_open(DONATE_URL)


func handle_exit() -> void:
	var os_name := OS.get_name()
	if os_name == "Android" or os_name == "iOS":
		push_warning("MainMenu: exit requested on mobile; ignoring hard quit.")
		_set_status("Используйте системную кнопку Назад")
		return
	get_tree().quit()


func _change_scene_if_exists(scene_path: String, action_name: String) -> void:
	var sanitized := _sanitize_scene_path(scene_path)
	if sanitized.is_empty() or not ResourceLoader.exists(sanitized):
		push_warning("MainMenu: cannot start %s, scene is missing: %s" % [action_name, scene_path])
		_set_status("Сцена не настроена")
		return
	get_tree().change_scene_to_file(sanitized)


func _sanitize_scene_path(scene_path: String) -> String:
	if scene_path.strip_edges().is_empty():
		return new_game_scene_path
	if scene_path == NETWORK_WORLD_PATH:
		return new_game_scene_path
	return scene_path


func _write_save(scene_path: String) -> void:
	var file := FileAccess.open(save_file_path, FileAccess.WRITE)
	if file == null:
		return
	var data := {
		"scene_path": scene_path,
		"saved_at_unix": Time.get_unix_time_from_system(),
	}
	file.store_string(JSON.stringify(data))
	file.flush()


func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var raw_json := file.get_as_text()
	if raw_json.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw_json)
	return parsed if parsed is Dictionary else {}


func _set_status(message: String) -> void:
	if status_label == null:
		return
	status_label.text = message
	status_label.visible = not message.strip_edges().is_empty()


func _disable_soundtrack_for_headless() -> void:
	if soundtrack_player == null or DisplayServer.get_name() != "headless":
		return
	if soundtrack_player.playing:
		soundtrack_player.stop()
	soundtrack_player.autoplay = false
	soundtrack_player.stream = null


func _setup_soundtrack_for_runtime() -> void:
	if soundtrack_player == null or DisplayServer.get_name() == "headless" or soundtrack_player.stream != null:
		return
	var stream := load(soundtrack_stream_path) as AudioStream
	if stream == null:
		return
	soundtrack_player.stream = stream
	if soundtrack_player.autoplay and not soundtrack_player.playing:
		soundtrack_player.play()


func _setup_network_signals() -> void:
	if NetworkManager == null:
		return
	if not NetworkManager.server_started.is_connected(_on_network_server_started):
		NetworkManager.server_started.connect(_on_network_server_started)
	if not NetworkManager.connected_to_server.is_connected(_on_network_connected_to_server):
		NetworkManager.connected_to_server.connect(_on_network_connected_to_server)
	if not NetworkManager.connection_failed.is_connected(_on_network_connection_failed):
		NetworkManager.connection_failed.connect(_on_network_connection_failed)
	if not NetworkManager.connection_rejected.is_connected(_on_network_connection_rejected):
		NetworkManager.connection_rejected.connect(_on_network_connection_rejected)
	if not NetworkManager.lan_host_discovered.is_connected(_on_lan_host_discovered):
		NetworkManager.lan_host_discovered.connect(_on_lan_host_discovered)


func _disconnect_network_signals() -> void:
	if NetworkManager == null:
		return
	if NetworkManager.server_started.is_connected(_on_network_server_started):
		NetworkManager.server_started.disconnect(_on_network_server_started)
	if NetworkManager.connected_to_server.is_connected(_on_network_connected_to_server):
		NetworkManager.connected_to_server.disconnect(_on_network_connected_to_server)
	if NetworkManager.connection_failed.is_connected(_on_network_connection_failed):
		NetworkManager.connection_failed.disconnect(_on_network_connection_failed)
	if NetworkManager.connection_rejected.is_connected(_on_network_connection_rejected):
		NetworkManager.connection_rejected.disconnect(_on_network_connection_rejected)
	if NetworkManager.lan_host_discovered.is_connected(_on_lan_host_discovered):
		NetworkManager.lan_host_discovered.disconnect(_on_lan_host_discovered)


func _show_lan_overlay() -> void:
	lan_overlay.visible = true
	_set_status("")
	lan_port_input.text = str(_parse_port_or_default())
	lan_ip_input.grab_focus()


func _hide_lan_overlay() -> void:
	lan_overlay.visible = false
	_set_lan_status("")


func _update_lan_ui_texts() -> void:
	if lan_overlay == null:
		return
	var lan_title := get_node_or_null("%LanTitle") as Label
	var host_button := get_node_or_null("%HostLanButton") as Button
	var find_button := get_node_or_null("%FindLanHostsButton") as Button
	var join_button := get_node_or_null("%JoinLanButton") as Button
	var back_button := get_node_or_null("%LanBackButton") as Button
	if lan_title != null:
		lan_title.text = "LAN Multiplayer"
	if host_button != null:
		host_button.text = "Host LAN"
	if find_button != null:
		find_button.text = "Find LAN Hosts"
	if join_button != null:
		join_button.text = "Join LAN"
	if back_button != null:
		back_button.text = tr("Назад")
	if lan_ip_input != null:
		lan_ip_input.placeholder_text = "Host IPv4 (example: 192.168.1.34)"
	if lan_port_input != null:
		lan_port_input.placeholder_text = "Port"
	_reset_found_hosts_select()


func _set_lan_status(message: String) -> void:
	if lan_status_label == null:
		return
	lan_status_label.text = message
	lan_status_label.visible = not message.strip_edges().is_empty()


func _on_host_lan_pressed() -> void:
	if NetworkManager == null:
		return
	_is_connecting_lan = false
	_lan_reconnect_attempted = false
	var port := _parse_port_or_default()
	_set_lan_status("Starting LAN host on port %d..." % port)
	var host_result: int = NetworkManager.host_lan_game(port)
	if host_result != OK:
		_set_lan_status(_format_network_error("Host failed", host_result))
		return
	_set_lan_status("LAN host created. Waiting for server start...")


func _on_join_lan_pressed() -> void:
	if NetworkManager == null:
		return
	var ip := lan_ip_input.text.strip_edges()
	if ip.is_empty():
		_set_lan_status("Enter host IP first")
		return
	var port := _parse_port_or_default()
	_is_connecting_lan = true
	_lan_reconnect_attempted = false
	_set_lan_status("Connecting to %s:%d ..." % [ip, port])
	var join_result: int = NetworkManager.join_lan_game(ip, port)
	if join_result != OK:
		_is_connecting_lan = false
		_set_lan_status(_format_network_error("Join failed", join_result))
		return
	_watch_lan_connect_timeout(ip, port)


func _on_find_lan_hosts_pressed() -> void:
	if NetworkManager == null:
		return
	var port := _parse_port_or_default()
	_lan_discovery_hosts.clear()
	_lan_discovery_host_keys.clear()
	_reset_found_hosts_select()
	var result: int = NetworkManager.request_lan_discovery(port)
	if result != OK:
		_set_lan_status(_format_network_error("LAN discovery failed", result))
		return
	_set_lan_status("Searching LAN hosts...")
	_finalize_lan_discovery_status_later()


func _on_lan_host_discovered(ip: String, port: int, host_name: String) -> void:
	var key := "%s:%d" % [ip, port]
	_lan_discovery_hosts[key] = {"ip": ip, "port": port, "host_name": host_name}
	if not _lan_discovery_host_keys.has(key):
		_lan_discovery_host_keys.append(key)
		_append_found_host_option(key, ip, port, host_name)
	if lan_ip_input.text.strip_edges().is_empty():
		lan_ip_input.text = ip
	lan_port_input.text = str(port)
	_set_lan_status("Found host: %s (%s:%d)" % [host_name, ip, port])


func _on_lan_host_selected(index: int) -> void:
	if index < 0 or index >= _lan_discovery_host_keys.size():
		return
	var key := _lan_discovery_host_keys[index]
	var entry := _lan_discovery_hosts.get(key, {}) as Dictionary
	var ip := String(entry.get("ip", ""))
	var port := int(entry.get("port", _parse_port_or_default()))
	if ip.is_empty():
		return
	lan_ip_input.text = ip
	lan_port_input.text = str(port)
	_set_lan_status("Selected host: %s (%s:%d)" % [String(entry.get("host_name", "LAN Host")), ip, port])


func _on_lan_back_pressed() -> void:
	_is_connecting_lan = false
	_lan_reconnect_attempted = false
	if NetworkManager != null and NetworkManager.get_state() != NetworkManager.NetworkState.IDLE:
		NetworkManager.reset_session_state(false)
	_hide_lan_overlay()


func _parse_port_or_default() -> int:
	var port_text := lan_port_input.text.strip_edges()
	if port_text.is_empty() or not port_text.is_valid_int():
		return DEFAULT_LAN_PORT
	var port := int(port_text)
	if port <= 0 or port > 65535:
		return DEFAULT_LAN_PORT
	return port


func _reset_found_hosts_select() -> void:
	if lan_hosts_select == null:
		return
	lan_hosts_select.clear()
	lan_hosts_select.add_item(tr("Хосты пока не найдены"))
	lan_hosts_select.disabled = true


func _append_found_host_option(key: String, ip: String, port: int, host_name: String) -> void:
	if lan_hosts_select == null:
		return
	if lan_hosts_select.disabled:
		lan_hosts_select.clear()
		lan_hosts_select.disabled = false
	var label := "%s (%s:%d)" % [host_name, ip, port]
	lan_hosts_select.add_item(label)
	lan_hosts_select.set_item_metadata(lan_hosts_select.item_count - 1, key)


func _finalize_lan_discovery_status_later() -> void:
	var status_at_start: String = lan_status_label.text if lan_status_label != null else ""
	await get_tree().create_timer(1.6).timeout
	if lan_status_label == null:
		return
	if lan_status_label.text != status_at_start:
		return
	if not _lan_discovery_hosts.is_empty():
		return
	_reset_found_hosts_select()
	_set_lan_status(tr("Хосты не найдены"))


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
	_set_lan_status(_format_network_error("Connection failed", FAILED))


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
	if NetworkManager != null:
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
		_set_lan_status(_format_network_error("Reconnect failed", reconnect_result))
		return false
	return true


func _format_network_error(prefix: String, error_code: int) -> String:
	var details := ""
	var last_error: String = NetworkManager.get_last_error() if NetworkManager != null else ""
	match error_code:
		OK:
			details = "ok"
		ERR_BUSY:
			details = "network busy (another host/join is in progress)"
		ERR_CANT_CREATE:
			details = "cannot create socket (port in use or blocked)"
		ERR_CANT_CONNECT:
			details = "cannot connect to host"
		ERR_TIMEOUT:
			details = "timeout"
		ERR_INVALID_PARAMETER:
			details = "invalid host/port"
		FAILED:
			details = "generic failure"
		_:
			details = "error %d" % error_code
	if not last_error.is_empty():
		details = "%s; %s" % [details, last_error]
	return "%s: %s" % [prefix, details]

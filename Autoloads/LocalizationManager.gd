extends Node

signal language_changed(locale: String)

const SETTINGS_FILE_PATH: String = "user://settings.cfg"
const SETTINGS_SECTION: String = "localization"
const SETTINGS_KEY_LANGUAGE: String = "language"
const DEFAULT_LOCALE: String = "ru"
const SUPPORTED_LOCALES: Array[String] = ["ru", "en", "id", "es", "pt"]
const TRANSLATION_PATHS: Dictionary = {
	"en": "res://i18n/en.tres",
	"id": "res://i18n/id.tres",
	"es": "res://i18n/es.tres",
	"pt": "res://i18n/pt.tres"
}

var _current_locale: String = DEFAULT_LOCALE
var _loaded_translations: Dictionary = {}
var _active_translation: Translation = null


func _ready() -> void:
	_load_translations()
	var saved_locale: String = _read_saved_locale()
	set_language(saved_locale, false)


func set_language(locale: String, persist: bool = true) -> void:
	var normalized_locale: String = _normalize_locale(locale)
	_current_locale = normalized_locale
	_apply_active_translation_for_locale(_current_locale)
	TranslationServer.set_locale(_current_locale)
	if persist:
		_save_locale(_current_locale)
	language_changed.emit(_current_locale)


func get_language() -> String:
	return _current_locale


func get_supported_locales() -> Array[String]:
	return SUPPORTED_LOCALES.duplicate()


func get_display_name(locale: String) -> String:
	match _normalize_locale(locale):
		"ru":
			return "Русский"
		"en":
			return "English"
		"id":
			return "Bahasa Indonesia"
		"es":
			return "Espanol"
		"pt":
			return "Portugues"
		_:
			return locale


func _load_translations() -> void:
	for locale_key in TRANSLATION_PATHS.keys():
		var locale: String = String(locale_key)
		var path: String = String(TRANSLATION_PATHS.get(locale, ""))
		if path.is_empty():
			continue
		var translation_resource := load(path) as Translation
		if translation_resource == null:
			push_warning("LocalizationManager: failed to load translation '%s' from %s" % [locale, path])
			continue
		translation_resource.set_locale(locale)
		_loaded_translations[locale] = translation_resource


func _apply_active_translation_for_locale(locale: String) -> void:
	if _active_translation != null:
		TranslationServer.remove_translation(_active_translation)
		_active_translation = null

	if not _loaded_translations.has(locale):
		return

	var translation_resource := _loaded_translations.get(locale, null) as Translation
	if translation_resource == null:
		return
	TranslationServer.add_translation(translation_resource)
	_active_translation = translation_resource


func _normalize_locale(locale: String) -> String:
	var trimmed: String = locale.strip_edges().to_lower()
	if trimmed.is_empty():
		return DEFAULT_LOCALE
	if trimmed.length() >= 2:
		trimmed = trimmed.substr(0, 2)
	if trimmed in SUPPORTED_LOCALES:
		return trimmed
	return DEFAULT_LOCALE


func _read_saved_locale() -> String:
	var config := ConfigFile.new()
	var err: int = config.load(SETTINGS_FILE_PATH)
	if err != OK:
		return DEFAULT_LOCALE
	return String(config.get_value(SETTINGS_SECTION, SETTINGS_KEY_LANGUAGE, DEFAULT_LOCALE))


func _save_locale(locale: String) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_FILE_PATH)
	config.set_value(SETTINGS_SECTION, SETTINGS_KEY_LANGUAGE, locale)
	var save_result: int = config.save(SETTINGS_FILE_PATH)
	if save_result != OK:
		push_warning("LocalizationManager: failed to save language setting (%d)" % save_result)

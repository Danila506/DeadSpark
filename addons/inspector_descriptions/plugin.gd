@tool
extends EditorPlugin

const InspectorDescriptionsPlugin = preload("res://addons/inspector_descriptions/inspector_descriptions_plugin.gd")

var _inspector_plugin: EditorInspectorPlugin


func _enter_tree() -> void:
	_inspector_plugin = InspectorDescriptionsPlugin.new()
	add_inspector_plugin(_inspector_plugin)


func _exit_tree() -> void:
	if _inspector_plugin != null:
		remove_inspector_plugin(_inspector_plugin)
	_inspector_plugin = null

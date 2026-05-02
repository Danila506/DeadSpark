extends Node

@export var max_animated_sprites: int = 64
@export var max_sprites: int = 96

var _animated_sprites: Array[AnimatedSprite2D] = []
var _sprites: Array[Sprite2D] = []


func acquire_animated_sprite(parent: Node) -> AnimatedSprite2D:
	if parent == null:
		return null

	while not _animated_sprites.is_empty():
		var sprite: AnimatedSprite2D = _animated_sprites.pop_back()
		if not is_instance_valid(sprite):
			continue
		if sprite.get_parent() != null:
			sprite.get_parent().remove_child(sprite)
		parent.add_child(sprite)
		sprite.visible = true
		return sprite

	var new_sprite := AnimatedSprite2D.new()
	parent.add_child(new_sprite)
	return new_sprite


func release_animated_sprite(sprite: AnimatedSprite2D) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	if _animated_sprites.size() >= max(max_animated_sprites, 0):
		sprite.queue_free()
		return

	sprite.stop()
	sprite.sprite_frames = null
	sprite.visible = false
	sprite.top_level = false
	sprite.flip_h = false
	sprite.flip_v = false
	sprite.rotation = 0.0
	sprite.scale = Vector2.ONE
	sprite.modulate = Color.WHITE
	if sprite.get_parent() != null:
		sprite.get_parent().remove_child(sprite)
	add_child(sprite)
	_animated_sprites.append(sprite)


func acquire_sprite(parent: Node) -> Sprite2D:
	if parent == null:
		return null

	while not _sprites.is_empty():
		var sprite: Sprite2D = _sprites.pop_back()
		if not is_instance_valid(sprite):
			continue
		if sprite.get_parent() != null:
			sprite.get_parent().remove_child(sprite)
		parent.add_child(sprite)
		sprite.visible = true
		return sprite

	var new_sprite := Sprite2D.new()
	parent.add_child(new_sprite)
	return new_sprite


func release_sprite(sprite: Sprite2D) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	if _sprites.size() >= max(max_sprites, 0):
		sprite.queue_free()
		return

	sprite.texture = null
	sprite.visible = false
	sprite.top_level = false
	sprite.rotation = 0.0
	sprite.scale = Vector2.ONE
	sprite.modulate = Color.WHITE
	if sprite.get_parent() != null:
		sprite.get_parent().remove_child(sprite)
	add_child(sprite)
	_sprites.append(sprite)

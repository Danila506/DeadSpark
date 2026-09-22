extends Node2D

@export var sprite_path: NodePath = NodePath("Sprite2D")
@export var textures: Array[Texture2D] = []
@export var use_position_as_seed: bool = true

const STONE_TEXTURE_PATHS: Array[String] = [
	"res://Assets/World/Biom2/stone1.png",
	"res://Assets/World/Biom2/stone2.png",
	"res://Assets/World/Biom2/stone3.png",
	"res://Assets/World/Biom2/stone4.png",
	"res://Assets/World/Biom2/stone5.png",
	"res://Assets/World/Biom2/stone6.png"
]

const PUDDLE_TEXTURE_PATHS: Array[String] = [
	"res://Assets/World/Biom2/puddle1.png",
	"res://Assets/World/Biom2/puddle2.png"
]


func _ready() -> void:
	var sprite := get_node_or_null(sprite_path) as Sprite2D
	if sprite == null:
		return

	var variants: Array[Texture2D] = _resolve_variants()
	if variants.is_empty():
		return

	var idx: int
	if use_position_as_seed:
		var px := int(round(global_position.x))
		var py := int(round(global_position.y))
		# Grid positions are even multiples: a raw XOR preserves parity and can
		# make half the variants unreachable. Mix coordinates before selection.
		var h := WorldSeedService.derive_seed(0, "environment/visual", [px, py])
		idx = posmod(h, variants.size())
	else:
		idx = randi() % variants.size()

	sprite.texture = variants[idx]


func _resolve_variants() -> Array[Texture2D]:
	if not textures.is_empty():
		return textures

	var paths := STONE_TEXTURE_PATHS
	var lower_name := name.to_lower()
	if lower_name.contains("puddle"):
		paths = PUDDLE_TEXTURE_PATHS

	var loaded: Array[Texture2D] = []
	for p in paths:
		var tex := load(p) as Texture2D
		if tex != null:
			loaded.append(tex)
	return loaded

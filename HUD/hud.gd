extends CanvasLayer

@export var player_path: NodePath
@onready var player = get_node("../Player2")

@onready var health_bar: TextureProgressBar = $HealthBar
@onready var water_bar: TextureProgressBar = $WaterBar
@onready var food_bar: TextureProgressBar = $FoodBar
@onready var stamina_bar: TextureProgressBar = $StaminaBar
@onready var bleeding_icon: Sprite2D = $HUDTexture/Stats/Bleeding
@onready var fracture_icon: Sprite2D = $HUDTexture/Stats/Fracture
@onready var disease_icon: Sprite2D = $HUDTexture/Stats/Disease
@onready var regeneration_icon: Sprite2D = $HUDTexture/Stats/Regeneration

var bleeding_blink_timer: float = 0.0
var bleeding_blink_visible: bool = false
var fracture_blink_timer: float = 0.0
var fracture_blink_visible: bool = false


func _ready() -> void:
	player.stats_changed.connect(update_stats)
	if player.has_signal("status_effects_changed"):
		player.status_effects_changed.connect(update_status_effects)
	bleeding_icon.visible = false
	fracture_icon.visible = false
	disease_icon.visible = false
	regeneration_icon.visible = false
	update_stats()
	update_status_effects()


func _process(delta: float) -> void:
	_update_bleeding_blink(delta)
	_update_fracture_blink(delta)


func update_stats() -> void:
	update_health()
	update_water()
	update_food()
	update_stamina()
	update_status_effects()


func update_health() -> void:
	health_bar.max_value = player.max_health
	health_bar.value = player.health


func update_water() -> void:
	water_bar.max_value = player.max_water
	water_bar.value = player.water


func update_food() -> void:
	food_bar.max_value = player.max_food
	food_bar.value = player.food


func update_stamina() -> void:
	stamina_bar.max_value = player.max_stamina
	stamina_bar.value = player.stamina


func update_status_effects() -> void:
	if player == null:
		return

	if not player.is_bleeding:
		bleeding_icon.visible = false
		bleeding_blink_timer = 0.0
		bleeding_blink_visible = false

	if not ("is_fractured" in player and player.is_fractured):
		fracture_icon.visible = false
		fracture_blink_timer = 0.0
		fracture_blink_visible = false

	regeneration_icon.visible = player.has_method("has_passive_regeneration") and player.has_passive_regeneration()
	disease_icon.visible = "is_diseased" in player and player.is_diseased


func _update_bleeding_blink(delta: float) -> void:
	if player == null or not player.is_bleeding:
		return

	bleeding_blink_timer += delta
	if bleeding_blink_timer >= 1.0:
		bleeding_blink_timer = 0.0
		bleeding_blink_visible = not bleeding_blink_visible

	bleeding_icon.visible = bleeding_blink_visible


func _update_fracture_blink(delta: float) -> void:
	if player == null or not ("is_fractured" in player and player.is_fractured):
		return

	fracture_blink_timer += delta
	if fracture_blink_timer >= 1.0:
		fracture_blink_timer = 0.0
		fracture_blink_visible = not fracture_blink_visible

	fracture_icon.visible = fracture_blink_visible

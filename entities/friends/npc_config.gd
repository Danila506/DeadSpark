@tool
extends Resource
class_name NPCConfig

@export_category("Identity")
@export var display_name: String = "Странник"

@export_category("Vitals")
@export_range(1.0, 1000.0, 1.0) var max_health: float = 100.0

@export_category("Movement")
@export_range(0.0, 1000.0, 1.0) var wander_speed: float = 70.0
@export_range(0.0, 1000.0, 1.0) var flee_speed: float = 115.0
@export_range(0.0, 5000.0, 1.0) var wander_radius: float = 280.0
@export_range(0.1, 60.0, 0.1) var idle_time_min: float = 2.0
@export_range(0.1, 60.0, 0.1) var idle_time_max: float = 5.0
@export_range(0.1, 30.0, 0.1) var flee_time: float = 6.0
@export_range(1.0, 5000.0, 1.0) var flee_distance: float = 320.0
@export_range(1.0, 1000.0, 1.0) var notice_player_distance: float = 110.0
@export_range(1.0, 1000.0, 1.0) var interaction_distance: float = 96.0

@export_category("Dialogue")
@export_multiline var introduction: String = "Я Марк. Хожу между укрытиями и меняю то, что удаётся найти."
@export_multiline var familiar_greeting: String = "Снова встретились. Береги себя."
@export_multiline var rumor_lines: Array[String] = [
	"Говорят, у дороги видели дом с нетронутыми припасами.",
	"Ночью в лесу лучше не шуметь: волки подходят ближе, чем кажется.",
	"Медикаменты чаще остаются в домах, чем в случайных тайниках."
]

@export_category("Trade stock")
@export var trade_item_definitions: Array[ItemData] = []
@export_range(1, 99, 1) var trade_stack_min: int = 1
@export_range(1, 99, 1) var trade_stack_max: int = 3

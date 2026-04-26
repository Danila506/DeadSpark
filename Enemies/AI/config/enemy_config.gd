extends Resource
class_name EnemyConfig

@export var max_health: float = 100.0

@export var patrol_speed: float = 65.0
@export var chase_speed: float = 115.0
@export var search_speed: float = 80.0
@export var acceleration: float = 520.0
@export var deceleration: float = 680.0

@export var attack_range: float = 34.0
@export var attack_range_exit_multiplier: float = 1.2
@export var attack_damage: float = 12.0
@export var attack_cooldown_sec: float = 1.0
@export var attack_windup_sec: float = 0.15
@export var attack_damage_type: int = 0

@export var is_ranged_enemy: bool = false
@export var ranged_preferred_distance: float = 130.0
@export var ranged_min_distance: float = 90.0
@export var ranged_retreat_step_distance: float = 110.0
@export var projectile_scene: PackedScene
@export var projectile_speed: float = 820.0
@export var projectile_lifetime_sec: float = 2.0
@export var projectile_damage: float = 8.0
@export var projectile_max_distance: float = 420.0
@export var ranged_spread_degrees: float = 9.0
@export var require_line_of_sight_for_attack: bool = true
@export var prevent_friendly_fire: bool = true
@export var ranged_burst_min_shots: int = 3
@export var ranged_burst_max_shots: int = 5
@export var ranged_burst_shot_interval_sec: float = 0.1
@export var ranged_burst_pause_sec: float = 0.55
@export var post_shot_move_speed_ratio: float = 0.3
@export var post_shot_move_duration_min_sec: float = 0.12
@export var post_shot_move_duration_max_sec: float = 0.35
@export var post_shot_forward_bias: float = 0.35
@export var post_shot_stand_time_sec: float = 0.08

@export var vision_radius: float = 260.0
@export_range(1.0, 360.0, 1.0) var vision_fov_deg: float = 110.0
@export var hearing_radius: float = 300.0
@export var sensor_interval_sec: float = 0.14
@export var sensor_far_distance: float = 520.0
@export var sensor_far_interval_sec: float = 0.28
@export var detect_confirm_sec: float = 0.18
@export var lose_confirm_sec: float = 0.55

@export var suspicious_duration_sec: float = 1.8
@export var search_duration_sec: float = 3.5
@export var house_search_duration_sec: float = 30.0
@export var house_search_radius: float = 150.0
@export var house_search_wait_min_sec: float = 0.35
@export var house_search_wait_max_sec: float = 1.2
@export var post_house_patrol_distance: float = 300.0
@export var stun_default_duration_sec: float = 0.6

@export var idle_wait_min_sec: float = 0.6
@export var idle_wait_max_sec: float = 1.8
@export var patrol_wait_min_sec: float = 0.4
@export var patrol_wait_max_sec: float = 1.4

@export var patrol_arrive_distance: float = 12.0
@export var investigate_arrive_distance: float = 14.0
@export var return_arrive_distance: float = 16.0
@export var nav_target_desired_distance: float = 8.0
@export var nav_path_desired_distance: float = 6.0
@export var path_retry_sec: float = 0.5
@export var obstacle_stuck_repath_sec: float = 0.32
@export var obstacle_bypass_probe_distance: float = 72.0
@export var obstacle_bypass_forward_bias: float = 24.0
@export var obstacle_bypass_hold_sec: float = 0.85
@export var obstacle_bypass_reach_distance: float = 10.0

@export var transition_cooldown_sec: float = 0.08
@export var auto_free_after_death: bool = false
@export var death_free_delay_sec: float = 6.0

@export var use_avoidance: bool = false
@export var ally_alert_cooldown_sec: float = 0.8
@export var nearest_bandit_cache_sec: float = 0.25
@export var nearest_bandit_cache_point_epsilon: float = 18.0

extends RefCounted
class_name PlayerVitalsController

var player


func _init(owner) -> void:
	player = owner


func update_needs(delta: float) -> void:
	if player == null:
		return

	var health_before: float = player.health

	player.water_timer += delta
	player.food_timer += delta

	if player.water_timer >= player.water_drain_interval:
		player.water_timer = 0.0
		player.water = clamp(player.water - player.water_drain_amount, 0.0, player.max_water)

		if player.water <= 0.0:
			player.health = clamp(player.health - 5.0, 0.0, player.max_health)
			if player.health <= 0.0:
				player.die()

		player.stats_changed.emit()

	if player.food_timer >= player.food_drain_interval:
		player.food_timer = 0.0
		player.food = clamp(player.food - player.food_drain_amount, 0.0, player.max_food)

		if player.food <= 0.0:
			player.health = clamp(player.health - 5.0, 0.0, player.max_health)
			if player.health <= 0.0:
				player.die()

		player.stats_changed.emit()

	_update_bleeding(delta)
	_update_disease(delta)

	if has_passive_regeneration():
		player.health = clamp(player.health + player.passive_regen_per_sec * delta, 0.0, player.max_health)

	if not is_equal_approx(health_before, player.health):
		player.stats_changed.emit()


func update_stamina(delta: float, inventory_root) -> void:
	if player == null:
		return

	var previous_stamina: float = player.stamina
	var is_inventory_blocking: bool = inventory_root != null and inventory_root.is_inventory_open
	var is_moving: bool = not is_inventory_blocking and player.velocity.length() > 0.1

	if is_moving:
		player.stamina = clamp(player.stamina - player.stamina_drain_per_sec * delta, 0.0, player.max_stamina)
	else:
		player.stamina = clamp(player.stamina + player.stamina_recovery_per_sec * delta, 0.0, player.max_stamina)

	if not is_equal_approx(previous_stamina, player.stamina):
		player.stats_changed.emit()


func take_damage(amount: float, damage_type: int = ItemData.DamageType.GENERIC, apply_clothing_damage: bool = true) -> void:
	if player == null or player.is_dead:
		return
	if apply_clothing_damage:
		player._apply_clothing_endurance_from_damage(amount, damage_type)

	player.health = clamp(player.health - amount, 0.0, player.max_health)
	player.stats_changed.emit()

	if player.health <= 0.0:
		player.die()


func add_water(amount: float) -> void:
	player.water = clamp(player.water + amount, 0.0, player.max_water)
	player.stats_changed.emit()


func add_food(amount: float) -> void:
	player.food = clamp(player.food + amount, 0.0, player.max_food)
	player.stats_changed.emit()


func add_health(amount: float) -> void:
	player.health = clamp(player.health + amount, 0.0, player.max_health)
	player.stats_changed.emit()


func add_radiation(amount: float) -> void:
	player.radiation = max(player.radiation + amount, 0.0)
	player.stats_changed.emit()


func add_stamina(amount: float) -> void:
	player.stamina = clamp(player.stamina + amount, 0.0, player.max_stamina)
	player.stats_changed.emit()


func apply_medical_item_effect(item: ItemData) -> bool:
	if item == null:
		return false

	var applied := false
	if not is_zero_approx(item.medical_health_restore):
		add_health(item.medical_health_restore)
		applied = true
	if not is_zero_approx(item.medical_radiation_change):
		add_radiation(item.medical_radiation_change)
		applied = true
	if item.medical_stop_bleeding:
		set_bleeding(false)
		applied = true
	if item.medical_heal_fracture:
		set_fractured(false)
		applied = true

	return applied


func set_bleeding(value: bool) -> void:
	if player.is_bleeding == value:
		return

	player.is_bleeding = value
	player.bleeding_timer = 0.0
	if player.is_bleeding:
		player.bleeding_trail_timer = max(player.bleeding_trail_interval_sec, 0.01)
		if player.blood_effects_controller != null:
			player.blood_effects_controller.spawn_bleeding_trail_mark()
	if not player.is_bleeding:
		player.bleeding_trail_timer = 0.0
	player.status_effects_changed.emit()


func set_fractured(value: bool) -> void:
	if player.is_fractured == value:
		return

	var was_fractured: bool = player.is_fractured
	player.is_fractured = value
	if was_fractured and not player.is_fractured:
		var target_stamina_after_heal: float = player.max_stamina * 0.85
		if player.stamina < target_stamina_after_heal:
			player.stamina = target_stamina_after_heal
			player.stats_changed.emit()
	player.status_effects_changed.emit()


func try_apply_food_poison(chance: float, custom_duration: float = -1.0) -> bool:
	var clamped_chance: float = clamp(chance, 0.0, 1.0)
	if clamped_chance <= 0.0:
		return false
	if randf() > clamped_chance:
		return false

	var applied_duration: float = player.disease_duration_sec if custom_duration <= 0.0 else custom_duration
	set_diseased(true, applied_duration)
	return true


func set_diseased(value: bool, duration_sec: float = -1.0) -> void:
	if value:
		var target_duration: float = player.disease_duration_sec if duration_sec <= 0.0 else duration_sec
		player.disease_time_left = max(player.disease_time_left, target_duration)
		player.disease_tick_timer = 0.0
		if not player.is_diseased:
			player.is_diseased = true
			player.status_effects_changed.emit()
		return

	if not player.is_diseased:
		return

	player.is_diseased = false
	player.disease_time_left = 0.0
	player.disease_tick_timer = 0.0
	player.status_effects_changed.emit()


func has_passive_regeneration() -> bool:
	return player.health < player.max_health and not player.is_bleeding and (player.food / player.max_food > player.passive_regen_threshold_ratio and player.water / player.max_water > player.passive_regen_threshold_ratio)


func _update_bleeding(delta: float) -> void:
	if player.is_bleeding:
		var tick_interval: float = max(player.bleeding_damage_interval, 0.01)
		player.bleeding_timer += delta

		while player.bleeding_timer >= tick_interval and player.is_bleeding:
			player.bleeding_timer -= tick_interval
			player.health = clamp(player.health - player.bleeding_damage_amount, 0.0, player.max_health)
			if player.health <= 0.0:
				player.die()
				break

			if randf() <= clamp(player.bleeding_auto_heal_chance, 0.0, 1.0):
				set_bleeding(false)
				break
	else:
		player.bleeding_timer = 0.0


func _update_disease(delta: float) -> void:
	if player.is_diseased:
		player.disease_time_left = max(player.disease_time_left - delta, 0.0)
		player.disease_tick_timer += delta
		var disease_interval: float = max(player.disease_damage_interval, 0.01)
		while player.disease_tick_timer >= disease_interval and player.is_diseased:
			player.disease_tick_timer -= disease_interval
			player.health = clamp(player.health - player.disease_damage_amount, 0.0, player.max_health)
			if player.health <= 0.0:
				player.die()
				break

		if player.disease_time_left <= 0.0:
			set_diseased(false)
	else:
		player.disease_tick_timer = 0.0

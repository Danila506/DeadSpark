class_name LootContainerProviderContract
extends RefCounted

## Duck-typed container contract shared by legacy interactive containers.
static func validate(provider: Node) -> Dictionary:
	var errors: Array[String] = []
	for method in ["get_loot_container_id", "get_loot_profile", "get_existing_loot_manifest", "has_materialized_loot", "apply_loot_manifest", "get_loot_slot_bindings"]:
		if provider == null or not provider.has_method(method): errors.append("MISSING_PROVIDER_API:%s" % method)
	if not errors.is_empty(): return {"valid":false, "errors":errors}
	var id := String(provider.call("get_loot_container_id")); var profile := provider.call("get_loot_profile") as LootProfile
	if id.is_empty(): errors.append("MISSING_CONTAINER_ID")
	if profile == null: errors.append("MISSING_PROFILE")
	else:
		for error in profile.validate().errors: errors.append(String(error))
	var bindings := provider.call("get_loot_slot_bindings") as Dictionary; var seen := {}
	for slot_id in bindings.keys():
		if seen.has(slot_id): errors.append("DUPLICATE_SLOT_BINDING:%s" % slot_id)
		seen[slot_id] = true
	return {"valid":errors.is_empty(), "errors":errors}


## Interaction hints and panels belong only to this machine's player.
static func is_local_interactor(body: Node) -> bool:
	if body == null or not body.is_in_group("player"): return false
	return body.multiplayer.multiplayer_peer == null or int(body.get("peer_id")) == body.multiplayer.get_unique_id()

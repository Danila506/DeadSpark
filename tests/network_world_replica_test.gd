extends "res://World/network_test_world.gd"
var failures: Array[String] = []
func _enter_tree() -> void: pass
func _exit_tree() -> void: pass
func _physics_process(_delta: float) -> void: pass
func _ready() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func run() -> void:
	var parent := Node2D.new()
	parent.name = "Objects"
	add_child(parent)
	var fixture = load("res://tests/network_replica_fixture.tscn")
	for i in range(2):
		var node = fixture.instantiate()
		node.position = Vector2(1200 + i * 100, 600)
		node.persistent_value = 70 + i
		node.set_meta("world_generation_id", "fixture/%d" % i)
		node.add_to_group("generated_world_object")
		parent.add_child(node)
	var payload := _collect_world_snapshot_payload()
	check(payload.size() == 2, "both objects serialized")
	var initial_signature := _compute_world_snapshot_signature(payload)
	var sliced_payload: Array = await _collect_world_snapshot_payload_sliced()
	check(sliced_payload == payload, "frame-budgeted snapshot matches synchronous snapshot")
	var freed_node := Node2D.new()
	parent.add_child(freed_node)
	freed_node.free()
	var freed_node_payload: Array = []
	check(
		not _append_world_snapshot_entry(freed_node, freed_node_payload) and freed_node_payload.is_empty(),
		"snapshot collector safely skips a node freed between slices"
	)
	check(
		await _compute_world_snapshot_signature_sliced(sliced_payload) == initial_signature,
		"frame-budgeted snapshot signature matches synchronous signature"
	)
	parent.get_child(0).persistent_value = 99
	var changed_payload := _collect_world_snapshot_payload()
	check(_compute_world_snapshot_signature(changed_payload) != initial_signature, "persistent state changes snapshot signature")
	payload = changed_payload
	var packed := var_to_bytes(payload).compress(FileAccess.COMPRESSION_GZIP)
	var decoded: Array = bytes_to_var(packed.decompress_dynamic(1024 * 1024, FileAccess.COMPRESSION_GZIP))
	check(decoded == payload, "snapshot codec roundtrip")
	for child in parent.get_children(): child.free()
	await _apply_world_snapshot_payload(decoded)
	check(parent.get_child_count() == 2, "replica count")
	for entry in payload:
		check(get_node_or_null(NodePath(entry.parent + "/" + entry.node_name)) != null, "exact server path restored")
	for child in parent.get_children():
		check(child.position_at_ready.is_equal_approx(child.global_position), "replica pose initialized before ready")
		check(child.persistent_value >= 70, "replica persistent state restored")
	var first = parent.get_child(0)
	await _apply_world_snapshot_payload(decoded)
	check(parent.get_child_count() == 2 and parent.get_child(0) == first, "repeated snapshot does not duplicate")
	for child in parent.get_children(): child.free()
	var chunk_seen: Dictionary = {}
	await _apply_world_snapshot_entries([decoded[0]], chunk_seen)
	check(parent.get_child_count() == 1, "first streamed chunk is applied independently")
	await _apply_world_snapshot_entries([decoded[1]], chunk_seen)
	check(parent.get_child_count() == 2, "later streamed chunk preserves earlier replicas")
	_finalize_world_snapshot(chunk_seen)
	check(parent.get_child_count() == 2, "stream finalization keeps every chunk replica")
	payload.remove_at(1)
	await _apply_world_snapshot_payload(payload)
	await get_tree().process_frame
	check(parent.get_child_count() == 1, "removed replica disappears")
	for failure in failures: push_error(failure)
	print("NETWORK_WORLD_REPLICA_TEST=" + ("PASS" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)

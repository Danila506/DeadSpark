class_name GenerationHashes
extends RefCounted

## Canonical serialization for generation contracts. It deliberately has no
## knowledge of resource paths, scene-tree names, wall clock data, or deltas.

static func sha256_of(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(canonical_json(value).to_utf8_buffer())
	return context.finish().hex_encode()


static func canonical_json(value: Variant) -> String:
	return JSON.stringify(_canonicalize(value), "", false)


static func _canonicalize(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var source := value as Dictionary
			var keys: Array[String] = []
			for key in source.keys():
				keys.append(str(key))
			keys.sort()
			var result := {}
			for key in keys:
				result[key] = _canonicalize(source.get(key))
			return result
		TYPE_ARRAY:
			var result: Array = []
			for item in value as Array:
				result.append(_canonicalize(item))
			return result
		TYPE_VECTOR2:
			var vector := value as Vector2
			return {"x": vector.x, "y": vector.y}
		TYPE_VECTOR2I:
			var vector := value as Vector2i
			return {"x": vector.x, "y": vector.y}
		TYPE_RECT2:
			var rect := value as Rect2
			return {"position": _canonicalize(rect.position), "size": _canonicalize(rect.size)}
		TYPE_RECT2I:
			var rect := value as Rect2i
			return {"position": _canonicalize(rect.position), "size": _canonicalize(rect.size)}
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(value)
		TYPE_OBJECT:
			if value is Resource:
				return {"resource_uid": resource_uid(value as Resource), "resource_type": (value as Resource).get_class()}
			return str(value)
		_:
			return value


static func resource_uid(resource: Resource) -> String:
	if resource == null or resource.resource_path.is_empty():
		return ""
	var uid := ResourceLoader.get_resource_uid(resource.resource_path)
	return ResourceUID.id_to_text(uid) if ResourceUID.has_id(uid) else ""

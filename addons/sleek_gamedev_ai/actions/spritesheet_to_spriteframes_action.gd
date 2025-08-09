@tool
extends Node

# Creates a SpriteFrames from a spritesheet texture and assigns it to a node property.
# Usage:
# spritesheet_to_spriteframes("Player/AnimatedSprite2D", "res://player.tscn", {
#   texture: "res://art/mario_sheet.png",
#   rows: 1,
#   cols: 4,
#   frame_width: 32,
#   frame_height: 32,
#   animations: [{ name: "idle", start: 0, length: 4, speed: 8, loop: true }],
#   assign_to_property: "sprite_frames"
# })

const Utils = preload("res://addons/sleek_gamedev_ai/actions/action_parser_utils.gd")

static func execute(node_name: String, scene_path: String, opts: Dictionary) -> bool:
	var packed: PackedScene = load(scene_path)
	if !(packed is PackedScene):
		push_error("spritesheet_to_spriteframes: failed to load scene '%s'" % scene_path)
		return false
	var root = packed.instantiate()
	var node: Node = root.find_child(node_name, true, true)
	if not node and node_name == root.name:
		node = root
	if not node:
		push_error("spritesheet_to_spriteframes: node '%s' not found in '%s'" % [node_name, scene_path])
		return false
	# Normalize texture path and load
	var tex_path := String(opts.get("texture", ""))
	tex_path = Utils.normalize_res_path(tex_path)
	var tex: Texture2D = load(tex_path)
	if not tex and Engine.is_editor_hint():
		EditorPlugin.new().get_editor_interface().get_resource_filesystem().scan()
		tex = load(tex_path)
	if not tex:
		push_error("spritesheet_to_spriteframes: failed to load texture '%s'" % tex_path)
		return false
	var rows := int(opts.get("rows", 1))
	var cols := int(opts.get("cols", 1))
	if rows <= 0 or cols <= 0:
		push_error("spritesheet_to_spriteframes: rows and cols must be > 0 (rows=%d, cols=%d)" % [rows, cols])
		return false
	var fw := int(opts.get("frame_width", tex.get_width() / cols))
	var fh := int(opts.get("frame_height", tex.get_height() / rows))
	if fw <= 0 or fh <= 0:
		push_error("spritesheet_to_spriteframes: invalid frame size (frame_width=%d, frame_height=%d)" % [fw, fh])
		return false
	var sf := SpriteFrames.new()
	# Build frames per animation descriptors
	var anims_raw = opts.get("animations", [])
	var anims: Array = []
	if anims_raw is Array:
		anims = anims_raw
	elif anims_raw is String:
		var s := String(anims_raw)
		var parsed = Utils.parse_jsonish(s)
		if typeof(parsed) == TYPE_ARRAY:
			anims = parsed
		else:
			push_error("spritesheet_to_spriteframes: could not parse 'animations' string; got: %s" % s.substr(0, 200))
			return false
	else:
		push_error("spritesheet_to_spriteframes: 'animations' missing or invalid; expected Array of dicts")
		return false
	for a in anims:
		var name := String(a.get("name", "default"))
		var start := int(a.get("start", 0))
		var length := int(a.get("length", rows * cols))
		var fps := float(a.get("speed", 8))
		var loop := bool(a.get("loop", true))
		sf.add_animation(name)
		sf.set_animation_speed(name, fps)
		sf.set_animation_loop(name, loop)
		for i in range(length):
			var idx = start + i
			var r = idx / cols
			var c = idx % cols
			var region = Rect2(c * fw, r * fh, fw, fh)
			var fr = AtlasTexture.new()
			fr.atlas = tex
			fr.region = region
			sf.add_frame(name, fr)
	var assign_prop := String(opts.get("assign_to_property", "sprite_frames"))
	node.set(assign_prop, sf)
	packed.pack(root)
	var ok = ResourceSaver.save(packed, scene_path)
	if ok != OK:
		push_error("spritesheet_to_spriteframes: failed to save scene '%s' (Error %d)" % [scene_path, ok])
		return false
	return true

static func parse_line(line: String, _full_text: String) -> Dictionary:
	if line.begins_with("spritesheet_to_spriteframes("):
		var body = line.replace("spritesheet_to_spriteframes(", "")
		if body.ends_with(")"):
			body = body.substr(0, body.length() - 1)
		body = body.strip_edges()
		var quoted: Array = []
		var i := 0
		while true:
			var a = body.find('"', i)
			if a == -1:
				break
			var b = body.find('"', a + 1)
			if b == -1:
				break
			quoted.append(body.substr(a + 1, b - a - 1))
			i = b + 1
		var open_i = body.find("{")
		var close_i = body.rfind("}")
		if quoted.size() < 2 or open_i == -1 or close_i == -1:
			return {}
		var opts = Utils.parse_object_map(body.substr(open_i, close_i - open_i + 1))
		return {"type": "spritesheet_to_spriteframes", "node_name": quoted[0], "scene_path": quoted[1], "options": opts}
	return {} 
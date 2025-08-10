@tool
extends Node

# Orchestrates the full pipeline from a natural-language prompt to a playable scene
# Usage:
# create_character_from_prompt("cute gray tabby cat jumping")
# create_character_from_prompt("prompt text", { rows: 3, cols: 3, animation: "cat_jump", scene_path: "res://scenes/cat.tscn", node_name: "Cat", fps: 8 })

const Utils = preload("res://addons/sleek_gamedev_ai/actions/action_parser_utils.gd")
const CreateImage = preload("res://addons/sleek_gamedev_ai/actions/create_image_action.gd")
const CreateScene = preload("res://addons/sleek_gamedev_ai/actions/create_scene_action.gd")
const CreateNode = preload("res://addons/sleek_gamedev_ai/actions/create_node_action.gd")
const EditNode = preload("res://addons/sleek_gamedev_ai/actions/edit_node_action.gd")
const SpriteSheetToFrames = preload("res://addons/sleek_gamedev_ai/actions/spritesheet_to_spriteframes_action.gd")
const SetMainScene = preload("res://addons/sleek_gamedev_ai/actions/set_main_scene_action.gd")
const RunProject = preload("res://addons/sleek_gamedev_ai/actions/run_project_action.gd")

static func execute(prompt: String, opts: Dictionary = {}) -> bool:
	var rows := int(opts.get("rows", 3))
	var cols := int(opts.get("cols", 3))
	var anim_name := String(opts.get("animation", "cat_jump"))
	var fps := float(opts.get("fps", 8.0))
	var loop: bool = opts.get("loop", true)
	var node_name := String(opts.get("node_name", "Cat"))
	var scene_path := String(opts.get("scene_path", "res://scenes/cat.tscn"))
	var image_path := String(opts.get("image_path", "res://art/generated/cat_spritesheet.png"))
	
	# Enhance the prompt to enforce spritesheet and left-to-right ordering
	var enhanced_prompt := (
		"Spritesheet of a cute gray tabby cat performing a jumping/twirling animation. " +
		"9 frames in a 3x3 grid, no margins or gaps, transparent background, consistent framing. " +
		"Each frame fully inside its cell without overlap. Order frames left-to-right, top-to-bottom. " +
		"Pixel art style, clean silhouettes, high contrast.\nUser prompt: " + prompt
	)
	
	# 1) Generate spritesheet image deterministically to a known path
	var img_ok := await CreateImage.execute({
		"prompt": enhanced_prompt,
		"aspect_ratio": "1:1",
		"output_format": "png",
		"exact_output_path": image_path,
		"output_prefix": "cat_sheet"
	})
	if not img_ok:
		push_error("create_character_from_prompt: image generation failed")
		return false
	
	# 2) Create character nodes in the CURRENT open scene (no new .tscn)
	var ei = EditorPlugin.new().get_editor_interface()
	var root: Node = ei.get_edited_scene_root()
	if root == null:
		push_error("create_character_from_prompt: No open scene to add nodes to. Create or open a scene first.")
		return false
	# Create CharacterBody2D as a child of the scene root if not present
	var character := root.find_child(node_name, true, false)
	if character == null:
		character = ClassDB.instantiate("CharacterBody2D")
		character.name = node_name
		root.add_child(character)
		character.set_owner(root)
	# Create AnimatedSprite2D under the character (loose init like editor does)
	var sprite := character.find_child("AnimatedSprite2D", true, false)
	if sprite == null:
		sprite = ClassDB.instantiate("AnimatedSprite2D")
		sprite.name = "AnimatedSprite2D"
		character.add_child(sprite)
		sprite.set_owner(root)
	
	# 3) Slice spritesheet into SpriteFrames and assign to the AnimatedSprite2D in the OPEN scene
	var slice_ok := SpriteSheetToFrames.execute("AnimatedSprite2D", "", {
		"texture": image_path,
		"rows": rows,
		"cols": cols,
		"animations": [{"name": anim_name, "start": 0, "length": rows * cols, "speed": fps, "loop": loop}],
		"assign_to_property": "sprite_frames"
	})
	if not slice_ok:
		push_error("create_character_from_prompt: failed to slice spritesheet")
		return false
	
	# 4) Set default animation and autoplay on AnimatedSprite2D
	var props := { "animation": anim_name, "playing": true }
	if not EditNode.execute("AnimatedSprite2D", "", props):
		# Fallback: set directly
		if sprite.has_method("play"):
			sprite.call_deferred("play", anim_name)
			sprite.playing = true
	
	# 5) Add Camera2D as a child of the character root and make it current
	var cam := character.find_child("Camera2D", true, false)
	if cam == null:
		cam = ClassDB.instantiate("Camera2D")
		cam.name = "Camera2D"
		character.add_child(cam)
		cam.set_owner(root)
		cam.current = true
	else:
		cam.current = true
	
	# Save scene after modifications (best effort)
	var _ok = ei.save_scene()
	
	# 6) Optionally run project if requested in opts
	var should_run: bool = opts.get("run", true)
	if should_run:
		var RunProject = preload("res://addons/sleek_gamedev_ai/actions/run_project_action.gd")
		RunProject.execute()
	return true

static func parse_line(line: String, _full_text: String) -> Dictionary:
	if line.begins_with("create_character_from_prompt("):
		var body = line.replace("create_character_from_prompt(", "").rstrip(")")
		body = body.strip_edges()
		var prompt := ""
		var opts := {}
		if body.begins_with("\""):
			# extract quoted string
			var a = 0
			var b = body.find("\"", 1)
			if b != -1:
				prompt = body.substr(1, b - 1)
				var rest = body.substr(b + 1).strip_edges().trim_prefix(",").strip_edges()
				if rest != "":
					opts = Utils.parse_object_map(rest)
		else:
			opts = Utils.parse_object_map(body)
		return {"type": "create_character_from_prompt", "prompt": prompt, "options": opts}
	return {} 
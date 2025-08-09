@tool
extends RefCounted

const TAG_OPEN_SCRIPTS = "@OpenScripts"
const TAG_SCENE_TREE = "@SceneTree"
const TAG_FILE_TREE = "@FileTree"
const TAG_OUTPUT = "@Output"
const TAG_GITDIFF = "@GitDiff"
const TAG_DOCS = "@Docs"
const TAG_PROJECT_SETTINGS = "@ProjectSettings"

static func apply_tags(prompt: String, editor: EditorInterface) -> String:
	if not _contains_any(prompt):
		return prompt
	var out = prompt
	if TAG_OPEN_SCRIPTS in out:
		out = _inject_open_scripts(out, editor)
	if TAG_SCENE_TREE in out:
		out = _inject_scene_tree(out, editor)
	# Placeholders; you can extend:
	# if TAG_FILE_TREE in out: ...
	# if TAG_OUTPUT in out: ...
	# if TAG_GITDIFF in out: ...
	# if TAG_DOCS in out: ...
	# if TAG_PROJECT_SETTINGS in out: ...
	return out

static func _contains_any(text: String) -> bool:
	return TAG_OPEN_SCRIPTS in text or TAG_SCENE_TREE in text or TAG_FILE_TREE in text or TAG_OUTPUT in text or TAG_DOCS in text or TAG_PROJECT_SETTINGS in text

static func _inject_open_scripts(text: String, editor: EditorInterface) -> String:
	var replacement = TAG_OPEN_SCRIPTS.substr(1)
	var scripts = _get_open_scripts(editor)
	var ctx = "\n[gds_context]\nScripts for context:\n"
	for path in scripts.keys():
		var content: String = scripts[path]
		ctx += "File: %s\nContent:\n```%s\n```\n" % [path, content]
	ctx += "\n[/gds_context]"
	return text.replace(TAG_OPEN_SCRIPTS, replacement).strip_edges() + ctx

static func _get_open_scripts(editor: EditorInterface) -> Dictionary:
	var ed = editor.get_script_editor()
	var arr: Array = ed.get_open_scripts()
	var out := {}
	for s in arr:
		out[s.get_path()] = s.get_source_code()
	return out

static func _inject_scene_tree(text: String, editor: EditorInterface) -> String:
	var replacement = TAG_SCENE_TREE.substr(1)
	var root = editor.get_edited_scene_root()
	if not root:
		return text.replace(TAG_SCENE_TREE, replacement) + "\n[gds_context]Node tree: No scene is currently being edited.[/gds_context]"
	var body = "\n[gds_context]Node tree:\n"
	body += _dump_tree(root)
	body += "--\n\n[/gds_context]"
	return text.replace(TAG_SCENE_TREE, replacement) + body

static func _dump_tree(node: Node, indent: String = "") -> String:
	var line = indent + "- " + node.name + " (" + node.get_class() + ")\n"
	var next = indent + "  "
	for child in node.get_children():
		line += _dump_tree(child, next)
	return line 
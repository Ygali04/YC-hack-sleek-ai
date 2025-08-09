@tool
extends RefCounted

static func _join(arr: Array, sep: String) -> String:
	var s = ""
	for i in range(arr.size()):
		if i > 0:
			s += sep
		s += str(arr[i])
	return s

static func render(markdown: String) -> String:
	var lines = markdown.split("\n")
	var out: Array = []
	var in_code := false
	var code_lines: Array = []
	var text_lines: Array = []
	for line in lines:
		var trimmed = String(line).strip_edges(true, false)
		if trimmed.begins_with("```"):
			if in_code:
				var code = _join(code_lines, "\n")
				code = _pad_code(code)
				if text_lines.size() > 0:
					var txt = _join(text_lines, "\n")
					out.append(_format_text(txt))
					text_lines.clear()
				out.append("\n[table=1]\n[cell bg=#000000]\n[code]" + code + "[/code]\n[/cell]\n[/table]\n")
				code_lines.clear()
				in_code = false
			else:
				if text_lines.size() > 0:
					var txt2 = _join(text_lines, "\n")
					out.append(_format_text(txt2))
					text_lines.clear()
				in_code = true
		elif in_code:
			code_lines.append(line)
		else:
			text_lines.append(line)
	if in_code and code_lines.size() > 0:
		var last = _join(code_lines, "\n")
		last = _pad_code(last)
		out.append("[p][/p][table=1]\n[cell bg=#000000]\n[code]" + last + "[/code]\n[/cell]\n[/table]")
	elif text_lines.size() > 0:
		out.append(_format_text(_join(text_lines, "\n")))
	return _join(out, "\n")

static func _pad_code(code: String) -> String:
	var lines = code.split("\n")
	for i in range(lines.size()):
		lines[i] = "  " + lines[i] + "  "
	return _join(lines, "\n") + "\n"

static func _format_text(text: String) -> String:
	# Minimal sanitation; could expand as needed
	return text.strip_edges() 
@tool
extends RefCounted
class_name EnvLoader

## Utility class to load environment variables from .env files

static func load_env_file(file_path: String = ".env") -> Dictionary:
	var env_vars = {}
	
	if not FileAccess.file_exists(file_path):
		print("[EnvLoader] .env file not found at: ", file_path)
		return env_vars
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		print("[EnvLoader] Could not open .env file: ", file_path)
		return env_vars
	
	print("[EnvLoader] Loading environment variables from: ", file_path)
	
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		
		# Skip empty lines and comments
		if line.is_empty() or line.begins_with("#"):
			continue
		
		# Parse KEY=VALUE or KEY="VALUE"
		var parts = line.split("=", false, 1)
		if parts.size() != 2:
			continue
		
		var key = parts[0].strip_edges()
		var value = parts[1].strip_edges()
		
		# Remove quotes if present
		if value.begins_with('"') and value.ends_with('"'):
			value = value.substr(1, value.length() - 2)
		elif value.begins_with("'") and value.ends_with("'"):
			value = value.substr(1, value.length() - 2)
		
		env_vars[key] = value
		print("[EnvLoader] Loaded: ", key, " = ", value.substr(0, 8), "...")
	
	file.close()
	return env_vars

static func get_env_var(key: String, default_value: String = "") -> String:
	# First try system environment
	var system_value = OS.get_environment(key)
	if not system_value.is_empty():
		return system_value
	
	# Then try .env file
	var env_vars = load_env_file()
	if env_vars.has(key):
		return env_vars[key]
	
	return default_value 
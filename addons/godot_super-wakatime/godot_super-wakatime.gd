@tool
extends EditorPlugin




var Utils = preload("res://addons/godot_super-wakatime/utils.gd").new()
var DecompressorUtils = preload("res://addons/godot_super-wakatime/decompressor.gd").new()


const PLUGIN_PATH: String = "res://addons/godot_super-wakatime"
const ZIP_PATH: String = "%s/wakatime.zip" % PLUGIN_PATH

const WAKATIME_URL_FMT: String = \
"https://github.com/wakatime/wakatime-cli/releases/download/v1.54.0/{wakatime_build}.zip"
const DECOMPERSSOR_URL_FMT: String = \
"https://github.com/ouch-org/ouch/releases/download/0.3.1/{ouch_build}"


const API_MENU_ITEM: String = "Wakatime API key"
const CONFIG_MENU_ITEM: String = "Wakatime Config File"


var wakatime_dir = null
var wakatime_cli = null
var decompressor_cli = null

var ApiKeyPrompt: PackedScene = preload("res://addons/godot_super-wakatime/api_key_prompt.tscn")
var Counter: PackedScene = preload("res://addons/godot_super-wakatime/counter.tscn")


var system_platform: String = Utils.set_platform()[0]
var system_architecture: String = Utils.set_platform()[1]

var debug: bool = false


const LOG_INTERVAL: int = 120000

var key_get_tries: int = 0
var counter_instance: Node
var current_time: String = "0 hrs, 0mins"



func _ready() -> void :
	setup_plugin()
	set_process(true)

func _exit_tree() -> void :
	_disable_plugin()
	set_process(false)


class DataSnapshot:
	var file_path: String
	var line_no: int
	var cursor_pos: int
	var lines: int


func get_coding_data(file: Script = null) -> DataSnapshot:
	var snapshot = DataSnapshot.new()
	if not file:
		file = get_editor_interface().get_script_editor().get_current_script()

	if not file:
		return null

	snapshot.file_path = ProjectSettings.globalize_path(file.resource_path)

	var code_edit: CodeEdit = get_editor_interface().get_script_editor().get_current_editor().get_base_editor()
	if code_edit is not CodeEdit:
		return null
	snapshot.line_no = code_edit.get_caret_line()
	snapshot.cursor_pos = code_edit.get_caret_column()
	snapshot.lines = code_edit.get_line_count()

	return snapshot

func get_building_data(mouse_event: InputEventMouse, file_path: String = "") -> DataSnapshot:
	"Generate"
	var snapshot = DataSnapshot.new()
	if file_path == "":
		if EditorInterface.get_edited_scene_root() == null:
			return null
		var file = EditorInterface.get_edited_scene_root().scene_file_path

		if not file:
			return null

		snapshot.file_path = ProjectSettings.globalize_path(file)
	else:
		snapshot.file_path = file_path

	snapshot.line_no = int(roundf(mouse_event.position.x))
	snapshot.cursor_pos = int(roundf(mouse_event.position.y))


	snapshot.lines = 0
	return snapshot


var last_tick_frame: int = 0
var last_mouse_event: InputEventMouse
var moved_on_edit: bool = false
func _input(event: InputEvent) -> void :
	"Handle all input events"

	if Time.get_ticks_msec() - last_tick_frame > LOG_INTERVAL:

		if tab_open == "Script":
			if event is InputEventKey:
				var key_event = event as InputEventKey
				if (key_event.keycode == KEY_UP || key_event.keycode == KEY_DOWN
					|| key_event.keycode == KEY_LEFT || key_event.keycode == KEY_RIGHT
					|| key_event.keycode == KEY_ALT || key_event.keycode == KEY_SHIFT):
						return

				var snapshot = get_coding_data()

				if snapshot == null:
					return

				send_heartbeat(snapshot.file_path, "coding", snapshot.line_no, snapshot.cursor_pos, snapshot.lines, false)

				last_tick_frame = Time.get_ticks_msec()

		elif tab_open == "2D" || tab_open == "3D":
			if event is InputEventMouse:
				var snapshot = get_building_data(event)

				if snapshot == null:
					return

				send_heartbeat(snapshot.file_path, "building", snapshot.line_no, snapshot.cursor_pos, snapshot.lines, false)

				last_tick_frame = Time.get_ticks_msec()


	if tab_open == "2D" || tab_open == "3D":
		if event is InputEventMouse:
			last_mouse_event = event
			moved_on_edit = true



var tab_open: String = "2D"
func _main_screen_changed(tab_name: String):
	"Update the curent tab so we can know where our input events are going to"
	tab_open = tab_name



func _scene_saved(file_path: String):
	"Handle heartbeats to be sent on scene save"
	if last_mouse_event == null:
		return

	if !moved_on_edit:
		return

	moved_on_edit = false

	var snapshot = get_building_data(last_mouse_event)

	if snapshot == null:
		return

	send_heartbeat(snapshot.file_path, "building", snapshot.line_no, snapshot.cursor_pos, snapshot.lines, true)

func _resource_saved(resource: Resource):
	"Handle heartbeats to be sent on file save"
	if not resource is GDScript:
		return

	var snapshot = get_coding_data(resource)

	if snapshot == null:
		return

	send_heartbeat(snapshot.file_path, "coding", snapshot.line_no, snapshot.cursor_pos, snapshot.lines, true)


func setup_plugin() -> void :
	"Setup Wakatime plugin, download dependencies if needed, initialize menu"
	Utils.plugin_print("Setting up %s" % get_user_agent())
	check_dependencies()

	main_screen_changed.connect(_main_screen_changed)
	scene_saved.connect(_scene_saved)
	resource_saved.connect(_resource_saved)


	var api_key = get_api_key()
	if api_key == null:
		request_api_key()
	await get_tree().process_frame


	add_tool_menu_item(API_MENU_ITEM, request_api_key)
	add_tool_menu_item(CONFIG_MENU_ITEM, open_config)

	counter_instance = Counter.instantiate()
	add_control_to_bottom_panel(counter_instance, current_time)

func _disable_plugin() -> void :
	"Cleanup after disabling plugin"

	remove_tool_menu_item(API_MENU_ITEM)
	remove_tool_menu_item(CONFIG_MENU_ITEM)

	remove_control_from_bottom_panel(counter_instance)


func send_heartbeat(filepath: String, catagory: String, line_num: int, cursor_pos: int, lines: int, is_write: bool) -> void :
	"Send Wakatimde heartbeat for the specified file"

	if not Utils.wakatime_cli_exists(get_waka_cli()):
		print("Wakatime not installed!")
		return


	var api_key = get_api_key()
	if api_key == null:
		Utils.plugin_print("Failed to get Wakatime API key. Are you sure it's correct?")
		if (key_get_tries < 3):
			request_api_key()
			key_get_tries += 1
		else:
			Utils.plugin_print("If this keep occuring, please create a file: ~/.wakatime.cfg\n\n\t\t\t\tinitialize it with:\n[settings]\napi_key={your_key}"\
			)
		return


	var cmd: Array[Variant] = ["--entity", filepath, "--key", api_key]
	if is_write:
		cmd.append("--write")
	cmd.append_array(["--alternate-project", ProjectSettings.get("application/config/name")])
	cmd.append_array(["--time", str(Time.get_unix_time_from_system())])
	cmd.append_array(["--lineno", str(line_num)])
	cmd.append_array(["--cursorpos", str(cursor_pos)])
	cmd.append_array(["--lines-in-file", str(lines)])
	cmd.append_array(["--plugin", get_user_agent()])

	cmd.append_array(["--category", catagory])


	var cmd_callable = Callable(self, "_handle_heartbeat").bind(cmd)

	WorkerThreadPool.add_task(cmd_callable)

func _find_code_edit_recursive(node: Node) -> CodeEdit:
	"Find recursively code editor in a node"

	if node is CodeEdit:
		return node


	for child in node.get_children():
		var editor = _find_code_edit_recursive(child)
		if editor:
			return editor
	return null

func _handle_heartbeat(cmd_arguments) -> void :
	"Handle sending the heartbeat"

	if wakatime_cli == null:
		wakatime_cli = Utils.get_waka_cli()

	var output: Array[Variant] = []
	var exit_code: int = OS.execute(wakatime_cli, cmd_arguments, output, true)

	update_today_time(wakatime_cli)


	if debug:
		if exit_code == -1:
			Utils.plugin_print("Failed to send heartbeat: %s" % output)
		else:
			Utils.plugin_print("Heartbeat sent: %s" % output)

func update_today_time(wakatime_cli) -> void :
	"Update today's time in menu"
	var output: Array[Variant] = []

	var exit_code: int = OS.execute(wakatime_cli, ["--today"], output, true)


	if exit_code == 0:
		current_time = output[0]
	else:
		current_time = "Wakatime"

	call_deferred("_update_panel_label", current_time, output[0])

func _update_panel_label(label: String, content: String):
	"Update bottom panel name that shows time"

	if counter_instance and counter_instance.get_node("HBoxContainer/Label"):
		counter_instance.get_node("HBoxContainer/Label").text = content

		remove_control_from_bottom_panel(counter_instance)
		add_control_to_bottom_panel(counter_instance, label)



func open_config() -> void :
	"Open wakatime config file"
	OS.shell_open(Utils.config_filepath(system_platform, PLUGIN_PATH))

func get_waka_dir() -> String:
	"Search for and return wakatime directory"
	if wakatime_dir == null:
		wakatime_dir = "%s/.wakatime" % Utils.home_directory(system_platform, PLUGIN_PATH)
	return wakatime_dir

func get_waka_cli() -> String:
	"Get wakatime_cli file"
	if wakatime_cli == null:
		var build = Utils.get_waka_build(system_platform, system_architecture)
		var ext: String = ".exe" if system_platform == "windows" else ""
		wakatime_cli = "%s/%s%s" % [get_waka_dir(), build, ext]
	return wakatime_cli

func check_dependencies() -> void :
	"Make sure all dependencies exist"
	if !Utils.wakatime_cli_exists(get_waka_cli()):
		download_wakatime()
		if !DecompressorUtils.lib_exists(decompressor_cli, system_platform, PLUGIN_PATH):
			download_decompressor()

func download_wakatime() -> void :
	"Download wakatime cli"
	Utils.plugin_print("Downloading Wakatime CLI...")
	var url: String = WAKATIME_URL_FMT.format({"wakatime_build":
		Utils.get_waka_build(system_platform, system_architecture)})


	var http = HTTPRequest.new()
	http.download_file = ZIP_PATH
	http.connect("request_completed", Callable(self, "_wakatime_download_completed"))
	add_child(http)


	var status = http.request(url)
	if status != OK:
		Utils.plugin_print_err("Failed to start downloading Wakatime [Error: %s]" % status)
		_disable_plugin()

func download_decompressor() -> void :
	"Download ouch decompressor"
	Utils.plugin_print("Downloading Ouch! decompression library...")
	var url: String = DECOMPERSSOR_URL_FMT.format({"ouch_build":
		Utils.get_ouch_build(system_platform)})
	if system_platform == "windows":
		url += ".exe"


	var http = HTTPRequest.new()
	http.download_file = DecompressorUtils.decompressor_cli(decompressor_cli, system_platform, PLUGIN_PATH)
	http.connect("request_completed", Callable(self, "_decompressor_download_finished"))
	add_child(http)


	var status = http.request(url)
	if status != OK:
		_disable_plugin()
		Utils.plugin_print_err("Failed to start downloading Ouch! library [Error: %s]" % status)

func _wakatime_download_completed(result, status, headers, body) -> void :
	"Finish downloading wakatime, handle errors"
	if result != HTTPRequest.RESULT_SUCCESS:
		Utils.plugin_print_err("Error while downloading Wakatime CLI")
		_disable_plugin()
		return

	Utils.plugin_print("Wakatime CLI has been installed succesfully! Located at %s" % ZIP_PATH)
	extract_files(ZIP_PATH, get_waka_dir())

func _decompressor_download_finished(result, status, headers, body) -> void :
	"Handle errors and finishi decompressor download"

	if result != HTTPRequest.RESULT_SUCCESS:
		Utils.plugin_print_err("Error while downloading Ouch! library")
		_disable_plugin()
		return


	if !DecompressorUtils.lib_exists(decompressor_cli, system_platform, PLUGIN_PATH):
		Utils.plugin_print_err("Failed to save Ouch! library")
		_disable_plugin()
		return


	var decompressor: String = \
	ProjectSettings.globalize_path(DecompressorUtils.decompressor_cli(decompressor_cli, 
		system_platform, PLUGIN_PATH))

	if system_platform == "linux" or system_platform == "darwin":
		OS.execute("chmod", ["+x", decompressor], [], true)


	Utils.plugin_print("Ouch! has been installed succesfully! Located at %s" %\
	DecompressorUtils.decompressor_cli(decompressor_cli, system_platform, PLUGIN_PATH))
	extract_files(ZIP_PATH, get_waka_dir())

func extract_files(source: String, destination: String) -> void :
	"Extract downloaded Wakatime zip"

	if not DecompressorUtils.lib_exists(decompressor_cli, system_platform, 
			PLUGIN_PATH) and not Utils.wakatime_zip_exists(ZIP_PATH):
		return


	Utils.plugin_print("Extracting Wakatime...")
	var decompressor: String
	if system_platform == "windows":
		decompressor = ProjectSettings.globalize_path(
			DecompressorUtils.decompressor_cli(decompressor_cli, system_platform, PLUGIN_PATH))
	else:
		decompressor = ProjectSettings.globalize_path("res://" + 
			DecompressorUtils.decompressor_cli(decompressor_cli, system_platform, PLUGIN_PATH))

	var src: String = ProjectSettings.globalize_path(source)
	var dest: String = ProjectSettings.globalize_path(destination)


	var errors: Array[Variant] = []
	var args: Array[String] = ["--yes", "decompress", src, "--dir", dest]

	var error: int = OS.execute(decompressor, args, errors, true)
	if error:
		Utils.plugin_print(errors)
		_disable_plugin()
		return


	if Utils.wakatime_cli_exists(get_waka_cli()):
		Utils.plugin_print("Wakatime CLI installed (path: %s)" % get_waka_cli())
	else:
		Utils.plugin_print_err("Installation of Wakatime failed")
		_disable_plugin()


	clean_files()

func clean_files():
	"Delete files that aren't needed anymore"
	if Utils.wakatime_zip_exists(ZIP_PATH):
		delete_file(ZIP_PATH)
	if DecompressorUtils.lib_exists(decompressor_cli, system_platform, PLUGIN_PATH):
		delete_file(ZIP_PATH)

func delete_file(path: String) -> void :
	"Delete file at specified path"
	var dir: DirAccess = DirAccess.open("res://")
	var status: int = dir.remove(path)
	if status != OK:
		Utils.plugin_print_err("Failed to clean unnecesary file at %s" % path)
	else:
		Utils.plugin_print("Clean unncecesary file at %s" % path)



func get_api_key():
	"Get wakatime api key"
	var result = []

	var err = OS.execute(get_waka_cli(), ["--config-read", "api_key"], result)
	if err == -1:
		return null


	var key = result[0].strip_edges()
	if key.is_empty():
		return null
	return key

func request_api_key() -> void :
	"Request Wakatime API key from the user"

	var prompt = ApiKeyPrompt.instantiate()
	_set_api_key(prompt, get_api_key())
	_register_api_key_signals(prompt)


	add_child(prompt)
	prompt.popup_centered()
	await prompt.popup_hide
	prompt.queue_free()

func _set_api_key(prompt: PopupPanel, api_key) -> void :
	"Set API key from prompt"

	if api_key == null:
		api_key = ""


	var edit_field: Node = prompt.get_node("VBoxContainer/HBoxContainerTop/LineEdit")
	edit_field.text = api_key

func _register_api_key_signals(prompt: PopupPanel) -> void :
	"Connect all signals related to API key popup"

	var show_button: Node = prompt.get_node("VBoxContainer/HBoxContainerTop/ShowButton")
	var save_button: Node = prompt.get_node("VBoxContainer/HBoxContainerBottom/SubmitButton")


	show_button.connect("pressed", Callable(self, "_on_toggle_key_text").bind(prompt))
	save_button.connect("pressed", Callable(self, "_on_save_key").bind(prompt))
	prompt.connect("popup_hide", Callable(self, "_on_popup_hide").bind(prompt))

func _on_popup_hide(prompt: PopupPanel):
	"Close the popup window when user wants to hide it"
	prompt.queue_free()

func _on_toggle_key_text(prompt: PopupPanel) -> void :
	"Handle hiding and showing API key"

	var show_button: Node = prompt.get_node("VBoxContainer/HBoxContainerTop/ShowButton")
	var edit_field: Node = prompt.get_node("VBoxContainer/HBoxContainerTop/LineEdit")


	edit_field.secret = not edit_field.secret
	show_button.text = "Show" if edit_field.secret else "Hide"

func _on_save_key(prompt: PopupPanel) -> void :
	"Handle entering API key"

	var edit_field: Node = prompt.get_node("VBoxContainer/HBoxContainerTop/LineEdit")
	var api_key = edit_field.text.strip_edges()


	var err: int = OS.execute(get_waka_cli(), ["--config-write", "api-key=%s" % api_key])
	if err == -1:
		Utils.plugin_print("Failed to save API key")
	prompt.visible = false



func get_user_agent() -> String:
	"Get user agent identifier"
	var os_name = OS.get_name().to_lower()
	return "godot/%s %s/%s" % [
		get_engine_version(), 
		_get_plugin_name(), 
		_get_plugin_version()
	]

func _get_plugin_name() -> String:
	"Get name of the plugin"
	return "Godot_Super-Wakatime"

func _get_plugin_version() -> String:
	"Get version of the plugin"
	if get_plugin_version() == "":
		return "unknown"

	return get_plugin_version()

func get_engine_version() -> String:
	"Get verison of currently used engine"
	return "%s.%s.%s" % [Engine.get_version_info()["major"], Engine.get_version_info()["minor"], 
		Engine.get_version_info()["patch"]]

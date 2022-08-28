# Arrow
# Game Narrative Design Tool
# Mor. H. Golkar

# Console Panel
extends PanelContainer

signal request_mind

onready var TheTree = get_tree()
onready var Main = TheTree.get_root().get_child(0)

onready var Terminal = get_node(Addressbook.CONSOLE.TERMINAL)
onready var TerminalScroll = get_node(Addressbook.CONSOLE.TERMINAL_SCROLL_CONTAINER)
onready var ClearConsoleButton = get_node(Addressbook.CONSOLE.CLEAR)
onready var CloseConsoleButton = get_node(Addressbook.CONSOLE.CLOSE)
onready var PlayStepBackButton = get_node(Addressbook.CONSOLE.BACK)
onready var SettingsMenuButton = get_node(Addressbook.CONSOLE.SETTINGS)
onready var SettingsMenuButtonPopup = SettingsMenuButton.get_popup()

const CONSOLE_MESSAGE_DEFAULT_COLOR = Settings.CONSOLE_MESSAGE_DEFAULT_COLOR

var _CACHED_TYPES:Dictionary = {}
var _NODES_IN_TERMINAL = [] # new one first [0]
var _VARIABLES_SYNCED_WITH_NODES_IN_TERMINAL = []
var _SKIPPED_NODES:Dictionary = {}
var _OPEN_MACRO = null # or { "ELEMENT": ..., "TERMINAL": ..., "MACRO_NODES": [...] }

# console settings
var _AUTOSCROLL:bool = true
var _ALLOW_AUTO_PLAY:bool = true
var _PREVENT_CLEARANCE:bool = false
var _INSPECT_VARIABLES:bool = false
var _SHOW_SKIPPED_NODES:bool = false

const CLEARANCE_PREVENTION_MESSAGE = "Clearance ignored."
const CLEARANCE_PREVENTION_MESSAGE_COLOR = Color.yellow

const CONSOLE_SKIPPED_NODES_SELF_MODULATION_COLOR_ON = Settings.CONSOLE_SKIPPED_NODES_SELF_MODULATION_COLOR_ON
const CONSOLE_SKIPPED_NODES_SELF_MODULATION_COLOR_OFF = Settings.CONSOLE_SKIPPED_NODES_SELF_MODULATION_COLOR_OFF

const CONSOLE_SETTINGS_MENU = {
	# CAUTION! The func `refresh_console_setting_menu_buttons` shall be modified respectively in case
	0: { "label": "Auto-scroll", "is_checkbox": true , "action": "_reset_settings_auto_scroll" },
	1: { "label": "Allow Auto-play", "is_checkbox": true , "action": "_reset_settings_allow_auto_play" },
	2: { "label": "Prevent Clearance", "is_checkbox": true , "action": "_reset_settings_prevent_clearance" },
	3: { "label": "Inspect Variables", "is_checkbox": true , "action": "_reset_settings_inspect_variables" },
	4: { "label": "Show Skipped Nodes", "is_checkbox": true , "action": "_reset_settings_show_skipped_nodes" },
}
var _CONSOLE_SETTINGS_MENU_ITEM_INDEX_BY_ACTION = {}

onready var VariablesInspectorPanel = get_node(Addressbook.CONSOLE.VARIABLE_INSPECTOR.itself)
onready var VariableInspectorSelect = get_node(Addressbook.CONSOLE.VARIABLE_INSPECTOR.VARIABLE_SELECT)
onready var VariableInspectorCurrentValue = {
	"itself": get_node(Addressbook.CONSOLE.VARIABLE_INSPECTOR.VALUE_EDITS.itself),
	"str": get_node(Addressbook.CONSOLE.VARIABLE_INSPECTOR.VALUE_EDITS["str"]),
	"num": get_node(Addressbook.CONSOLE.VARIABLE_INSPECTOR.VALUE_EDITS["num"]),
	"bool": get_node(Addressbook.CONSOLE.VARIABLE_INSPECTOR.VALUE_EDITS["bool"])
}
onready var VariableInspectorUpdateButton = get_node(Addressbook.CONSOLE.VARIABLE_INSPECTOR.UPDATE_BUTTON)

func _ready() -> void:
	register_connections()
	load_console_settings_menu()
	pass

func register_connections() -> void:
	ClearConsoleButton.connect("pressed", self, "_request_mind", ["console_clear"], CONNECT_DEFERRED)
	CloseConsoleButton.connect("pressed", self, "_request_mind", ["console_close"], CONNECT_DEFERRED)
	PlayStepBackButton.connect("pressed", self, "play_step_back", [], CONNECT_DEFERRED)
	SettingsMenuButtonPopup.connect("id_pressed", self, "_on_console_settings_popup_menu_id_pressed", [], CONNECT_DEFERRED)
	VariableInspectorSelect.connect("item_selected", self, "_on_variable_inspector_item_select", [], CONNECT_DEFERRED)
	VariableInspectorUpdateButton.connect("pressed", self, "update_current_inspected_variable", [], CONNECT_DEFERRED)
	pass

func _request_mind(req:String, args = null) -> void:
	emit_signal("request_mind", req, args)
	pass

func load_console_settings_menu() -> void:
	SettingsMenuButtonPopup.clear()
	for item_id in CONSOLE_SETTINGS_MENU:
		var item = CONSOLE_SETTINGS_MENU[item_id]
		if item == null: # separator
			SettingsMenuButtonPopup.add_separator()
		else:
			if item.has("is_checkbox") && item.is_checkbox == true:
				SettingsMenuButtonPopup.add_check_item(item.label, item_id)
			else:
				SettingsMenuButtonPopup.add_item(item.label, item_id)
			_CONSOLE_SETTINGS_MENU_ITEM_INDEX_BY_ACTION[item.action] = SettingsMenuButtonPopup.get_item_index(item_id)
	# update checkboxes ...
	refresh_console_setting_menu_buttons()
	pass

func _on_console_settings_popup_menu_id_pressed(pressed_item_id:int) -> void:
	var the_action = CONSOLE_SETTINGS_MENU[pressed_item_id].action
	if the_action is String && the_action.length() > 0 :
		self.call_deferred(the_action)
	pass

func refresh_variables_list() -> void:
	var the_selected_one_index_before_referesh = VariableInspectorSelect.get_selected()
	VariableInspectorSelect.clear()
	var no_var_yet = true
	if _VARIABLES_SYNCED_WITH_NODES_IN_TERMINAL.size() >= 1:
		var variables = _VARIABLES_SYNCED_WITH_NODES_IN_TERMINAL[0]
		if variables.size() > 0 :
			for variable_id in variables:
				VariableInspectorSelect.add_item(variables[variable_id].name, variable_id)
			# reselect the variable after refresh
			if the_selected_one_index_before_referesh < variables.size():
				VariableInspectorSelect.select(the_selected_one_index_before_referesh)
			no_var_yet = false
	if no_var_yet:
		VariableInspectorSelect.add_item("No Variable Available", -1)
	inspect_variable()
	pass

func inspect_variable(id:int = -1) -> void:
	var a_var_inspected = false
	if id < 0 :
		id = VariableInspectorSelect.get_selected_id()
	if id >= 0 && _VARIABLES_SYNCED_WITH_NODES_IN_TERMINAL.size() > 0:
		var current_variable_set = _VARIABLES_SYNCED_WITH_NODES_IN_TERMINAL[0]
		if current_variable_set.size() > 0:
			if current_variable_set.has(id):
				var selected_variable = current_variable_set[id]
				var value = selected_variable.value
				a_var_inspected = true
				match selected_variable.type:
					"str":
						VariableInspectorCurrentValue["str"].set_text(value)
					"num":
						VariableInspectorCurrentValue["num"].set_value(value)
					"bool":
						VariableInspectorCurrentValue["bool"].select( VariableInspectorCurrentValue["bool"].get_item_index( ( 1 if value else 0 ) ) )
				set_variable_inspector_current_value_editor_to_type(selected_variable.type)
			else:
				# there might be a lingering previously inspected variable after step back or removal
				refresh_variables_list()
	VariableInspectorCurrentValue.itself.set("visible", a_var_inspected)
	pass

func set_variable_inspector_current_value_editor_to_type(the_type_visible:String = "") -> void:
	for type in VariableInspectorCurrentValue:
		VariableInspectorCurrentValue[type].set_visible( (type == the_type_visible) )
	pass

func _on_variable_inspector_item_select(idx:int = -1) -> void:
	# it inspects based on `get_selected_id`, so automatically converts idx to id
	inspect_variable()
	pass

func update_current_inspected_variable() -> void:
	var id = VariableInspectorSelect.get_selected_id()
	if id >= 0 && _VARIABLES_SYNCED_WITH_NODES_IN_TERMINAL.size() > 0:
		var current_variable_set = _VARIABLES_SYNCED_WITH_NODES_IN_TERMINAL[0]
		if current_variable_set.has(id):
			var selected_variable = current_variable_set[id]
			var value
			match selected_variable.type:
				"str":
					value = VariableInspectorCurrentValue["str"].get_text()
				"num":
					value = int( VariableInspectorCurrentValue["num"].get_value() )
				"bool":
					var boolean_integer = VariableInspectorCurrentValue["bool"].get_selected_id()
					value = (true if (boolean_integer == 1) else false)
			selected_variable.value = value
		print(current_variable_set)
	pass

func append_to_terminal(node_instance, node_uid: int = -1, node_resource = null, variables_current = null) -> void:
	if _OPEN_MACRO != null && (_OPEN_MACRO.MACRO_NODES.has(node_uid) || node_uid == -1):
		_OPEN_MACRO.ELEMENT.call("append_subnode", node_instance)
	else:
		_OPEN_MACRO = null
		Terminal.call_deferred("add_child", node_instance)
	# ...
	_NODES_IN_TERMINAL.push_front({
		"id": node_uid,
		"resource": node_resource,
		"instance": node_instance,
		"wrapper": _OPEN_MACRO.duplicate(false) if _OPEN_MACRO is Dictionary else null,
	});
	if (variables_current is Dictionary) == false:
		variables_current = clone_fresh_variable_set()
	_VARIABLES_SYNCED_WITH_NODES_IN_TERMINAL.push_front( variables_current )
	# print("New node appended to the terminal. ", _NODES_IN_TERMINAL, _VARIABLES_SYNCED_WITH_NODES_IN_TERMINAL)
	self.call_deferred("refresh_variables_list")
	self.call_deferred("update_scroll_to_v_max")
	pass

func print_console(message:String, centerize:bool = false, color:Color = CONSOLE_MESSAGE_DEFAULT_COLOR) -> void:
	var message_node = Label.new()
	message_node.set_text(message)
	if centerize:
		message_node.set_align(Label.ALIGN_CENTER)
	message_node.set("custom_colors/font_color", color)
	append_to_terminal(message_node)
	pass

func clone_fresh_variable_set() -> Dictionary:
	var new_set:Dictionary = {}
	if _VARIABLES_SYNCED_WITH_NODES_IN_TERMINAL.size() > 0 :
		# clone the changes from the last synced set
		new_set = _VARIABLES_SYNCED_WITH_NODES_IN_TERMINAL[0].duplicate(true)
	# then check for any new variables, because there might be new ones created since previous play in console;
	# it also loads initial values in empty `new_set` if there has been no previously played set
	var all_registered_variables = Main.Mind.clone_dataset_of("variables")
	for variable_id in all_registered_variables:
		if new_set.has(variable_id) == false:
			new_set[variable_id] = all_registered_variables[variable_id]
			new_set[variable_id].value = all_registered_variables[variable_id].init
	return new_set

# clears console even if clearance prevention setting is on,
# because it's called by core and not console nodes
func clear_console() -> void:
	var all_nodes_count = _NODES_IN_TERMINAL.size()
	while (all_nodes_count > 0):
		_NODES_IN_TERMINAL.pop_front().instance.queue_free()
		all_nodes_count -= 1
	_VARIABLES_SYNCED_WITH_NODES_IN_TERMINAL.clear()
	_SKIPPED_NODES.clear()
	print_debug("Console Cleared.")
	self.call_deferred("refresh_variables_list")
	pass

# listens to the playing node for only ONE EMISSION of each possible message,
# because every playing node will finish in a 'play_forward' or a 'status_code'.
# Some nodes may also ask for clearance (like contents) which can happen only once.
const POSSIBLE_SIGNALS_FROM_PLAYING_NODES = {
	"play_forward"   : "request_play_forward",
	"status_code"    : "interpret_status_code",
	"clear_up"       : "clear_nodes_before",
	"reset_variable" : "reset_synced_variable",
}

func listen_to_playing_node(node:Node, node_uid:int = -1) -> void:
	# because in step backs we try to listen back to a playing node,
	# we shall check for existance of the connection first to avoid error
	for the_signal in POSSIBLE_SIGNALS_FROM_PLAYING_NODES:
		var the_method = POSSIBLE_SIGNALS_FROM_PLAYING_NODES[the_signal]
		if node.is_connected(the_signal, self, the_method) == false:
			node.connect(the_signal, self, the_method, [node, node_uid], CONNECT_DEFERRED)
	# 'console' lets users to double click on a playing node and jump to the respective node on the gird,
	# so we listen for that too ...
	if node.is_connected("gui_input", self, "_on_playing_node_gui_input") == false:
		node.connect("gui_input", self, "_on_playing_node_gui_input", [node, node_uid], CONNECT_DEFERRED)
	pass

func open_macro(node_uid: int, node_resource:Dictionary, node_element:Node) -> void:
	_OPEN_MACRO = {
		"ID": node_uid,
		"ELEMENT": node_element,
		"MACRO_NODES": [],
	}
	# getting macro child nodes from the central mind
	if node_resource.has("data") && node_resource.data.has("macro"):
		if (node_resource.data.macro is int) && node_resource.data.macro >= 0 :
			var the_macro_resource = Main.Mind.lookup_resource(node_resource.data.macro, "scenes", false) # ... bacause a macro is a special scene
			if the_macro_resource is Dictionary:
				if the_macro_resource.has("map") && the_macro_resource.map is Dictionary:
					_OPEN_MACRO.MACRO_NODES = the_macro_resource.map.keys()
	print_debug("Type `macro_use` special treatments loaded.", _OPEN_MACRO)
	pass

func play_node(node_uid:int, node_resource:Dictionary, node_map:Dictionary, type:Dictionary, playing_in_slot:int = -1) -> void:
	print_debug("Console, plays node: %s - %s" % [node_uid, node_resource.type])
	var the_play_node = type.console.instance()
	var synced_var_set = (
		_VARIABLES_SYNCED_WITH_NODES_IN_TERMINAL[0].duplicate(true)
		if _VARIABLES_SYNCED_WITH_NODES_IN_TERMINAL.size() > 0 else
		clone_fresh_variable_set()
	)
	the_play_node.call_deferred("setup_play",
		node_uid,
		node_resource.duplicate(true),
		node_map.duplicate(true),
		playing_in_slot,
		synced_var_set
	)
	listen_to_playing_node(the_play_node, node_uid)
	append_to_terminal(the_play_node, node_uid, node_resource, synced_var_set)
	if node_resource.type == 'macro_use':
		open_macro(node_uid, node_resource, the_play_node)
	# and...
	if node_map.has("skip") && node_map.skip == true:
		# the node is appended, because it's part of the continuum anyway when played, so we ask it to get skipped (hidden)
		reset_node_skippness_view(the_play_node, (!_SHOW_SKIPPED_NODES), true)
		_SKIPPED_NODES[node_uid] = the_play_node
	# finally (re-)cache types for later uses
	_CACHED_TYPES[ node_resource.type ] = type
	pass
	
func reset_node_skippness_view(element:Node, do_hide:bool = true, do_modulate = null) -> void:
	element.set_visible( ! do_hide )
	# ... and do modulate if set:
	if do_modulate is bool:
		element.set("self_modulate",
			(
				CONSOLE_SKIPPED_NODES_SELF_MODULATION_COLOR_ON
					if do_modulate else
				CONSOLE_SKIPPED_NODES_SELF_MODULATION_COLOR_OFF
			)
		)
	pass

func update_scroll_to_v_max(forced:bool = false) -> void:
	if _AUTOSCROLL || forced:
		yield(TheTree, "idle_frame")
		var v_max = TerminalScroll.get_v_scrollbar().get_max()
		TerminalScroll.set_v_scroll( v_max )
		TerminalScroll.update()
	pass

func play_step_back(how_many:int = 1) -> void:
	if _NODES_IN_TERMINAL.size() >= how_many:
		while (how_many > 0):
			_VARIABLES_SYNCED_WITH_NODES_IN_TERMINAL.pop_front()
			var node = _NODES_IN_TERMINAL.pop_front().instance
			if is_instance_valid(node):
				if "_NODE_ID" in node && _SKIPPED_NODES.has(node._NODE_ID):
					_SKIPPED_NODES.erase(node._NODE_ID)
				node.queue_free()
				how_many -= 1
		# after stepping back, we shall...
		# make the last node manually playable by the user, to able them debug and decide!
		if _NODES_IN_TERMINAL.size() > 0 :
			var last = _NODES_IN_TERMINAL[0]
			# yet another treatment for `macro_use` nodes
			if last.wrapper != null: # last was a noe inside an open-macro instance
				_OPEN_MACRO = last.wrapper
				_OPEN_MACRO.ELEMENT.set_view_unplayed()
			elif _OPEN_MACRO != null && _OPEN_MACRO.ID != last.id: # out of the macro
				_OPEN_MACRO.ELEMENT.set_view_played();
				_OPEN_MACRO = null;
			elif last.resource.type == 'macro_use':
				open_macro(last.id, last.resource, last.instance)
			# ...
			if last.id >= 0: # Non-node printed messages are expected to be `< 0 ~= -1`
				last.instance.call_deferred("step_back")
			reset_node_skippness_view(last.instance, false) # make sure it's visible even skipped
			self.call_deferred("update_scroll_to_v_max")
		self.call_deferred("refresh_variables_list")
	pass

func request_play_forward(to_node_id:int = -1, to_slot:int = -1, _the_player_one = null, _the_player_one_uid = null):
	print_debug("Play Forward! To node: ", to_node_id, " slot: ", to_slot)
	emit_signal("request_mind", "console_play_node", {
		"id": to_node_id,
		"slot": to_slot
	})
	pass

func interpret_status_code(code:int, the_player_node = null, the_player_node_uid = null) -> void:
	match code:
		CONSOLE_STATUS_CODE.END_EDGE:
			if _OPEN_MACRO != null && the_player_node_uid != _OPEN_MACRO.ID:
				# It seems like a macro's end of line
				_OPEN_MACRO.ELEMENT.play_forward_from() # ~ PLAY_MACRO_END_SLOT
			else:
				print_console( CONSOLE_STATUS_CODE.END_EDGE_MESSAGE )
		CONSOLE_STATUS_CODE.NO_DEFAULT:
			if is_instance_valid(the_player_node):
				var full_no_default_message = CONSOLE_STATUS_CODE.NO_DEFAULT_MESSAGE + " (" + the_player_node._NODE_RESOURCE.name + ")"
				print_console( full_no_default_message , true, Settings.CAUTION_COLOR )
			else:
				print_console( CONSOLE_STATUS_CODE.NO_DEFAULT_MESSAGE , false, Settings.CAUTION_COLOR )
	pass

func clear_nodes_before(the_player_node, the_player_node_uid) -> void:
	if _PREVENT_CLEARANCE != true:
		if _NODES_IN_TERMINAL.size() > 0:
			while true:
				var oldest = _NODES_IN_TERMINAL[ _NODES_IN_TERMINAL.size() - 1 ] # (we did `push_front` to the array)
				if oldest.id != the_player_node_uid:
					_NODES_IN_TERMINAL.pop_back().instance.queue_free()
					_VARIABLES_SYNCED_WITH_NODES_IN_TERMINAL.pop_back()
				else:
					break
			self.call_deferred("refresh_variables_list")
	else:
		print_console( CLEARANCE_PREVENTION_MESSAGE, false, CLEARANCE_PREVENTION_MESSAGE_COLOR )
	pass

func reset_synced_variable(variable_update_list:Dictionary, the_player_node = null, the_player_node_uid = null) -> void:
	# print_debug("reset_synced_variable : ", variable_update_list)
	if _VARIABLES_SYNCED_WITH_NODES_IN_TERMINAL.size() > 0:
		assert(
			_VARIABLES_SYNCED_WITH_NODES_IN_TERMINAL.size() == _NODES_IN_TERMINAL.size(),
			"Size of synced variable sets are expected to be the same as nodes in terminal!"
		)
		if _NODES_IN_TERMINAL[0].id == the_player_node_uid:
			var the_set = _VARIABLES_SYNCED_WITH_NODES_IN_TERMINAL[0]
			for variable_id in variable_update_list:
				if the_set.has(variable_id):
					if typeof( the_set[variable_id].value ) == typeof( variable_update_list[variable_id] ):
						the_set[variable_id].value = variable_update_list[variable_id]
					else:
						printerr("Invalid Console Node Behavior! The variable %s is tried to be reset by value of other type: " % variable_id, variable_update_list[variable_id])
				else:
					printerr("Invalid Console Node Behavior! Trying to reset nonexistent variable %s by node %s " % [variable_id, the_player_node_uid])
		else:
			printerr(
				"Unexpected behavior: Variable update ignored! Only the last node (%s) is allowed to update variable sets (not requesting %s.)"
				% [_NODES_IN_TERMINAL[0].id, the_player_node_uid]
			)
	else:
		printerr("Unexpected behavior: node " + the_player_node_uid + " tried to update variables while no one is set up in memory!")
	refresh_variables_list()
	pass

func refresh_console_setting_menu_buttons() -> void:
	SettingsMenuButtonPopup.set_item_checked(0, _AUTOSCROLL)
	SettingsMenuButtonPopup.set_item_checked(1, _ALLOW_AUTO_PLAY)
	SettingsMenuButtonPopup.set_item_checked(2, _PREVENT_CLEARANCE)
	SettingsMenuButtonPopup.set_item_checked(3, _INSPECT_VARIABLES)
	SettingsMenuButtonPopup.set_item_checked(4, _SHOW_SKIPPED_NODES)
	VariablesInspectorPanel.set_visible(_INSPECT_VARIABLES)
	if _INSPECT_VARIABLES:
		self.call_deferred("refresh_variables_list")
	pass

func _reset_settings_auto_scroll() -> void:
	_AUTOSCROLL = (! _AUTOSCROLL)
	refresh_console_setting_menu_buttons()
	pass

func _reset_settings_allow_auto_play() -> void:
	_ALLOW_AUTO_PLAY = (! _ALLOW_AUTO_PLAY)
	refresh_console_setting_menu_buttons()
	pass

func _reset_settings_prevent_clearance() -> void:
	_PREVENT_CLEARANCE = (! _PREVENT_CLEARANCE)
	refresh_console_setting_menu_buttons()
	pass

func _reset_settings_inspect_variables() -> void:
	_INSPECT_VARIABLES = (! _INSPECT_VARIABLES)
	refresh_console_setting_menu_buttons()
	pass

func _reset_settings_show_skipped_nodes() -> void:
	_SHOW_SKIPPED_NODES = (! _SHOW_SKIPPED_NODES)
	refresh_console_setting_menu_buttons()
	# for all the skipped nodes reset view (and don't change modulation)
	refresh_skipped_nodes_view_all( (! _SHOW_SKIPPED_NODES) )
	pass

func refresh_skipped_nodes_view_all(do_hide:bool = true, do_modulate = null) -> void:
	for node_uid in _SKIPPED_NODES:
		reset_node_skippness_view(_SKIPPED_NODES[node_uid], do_hide, do_modulate)
	pass

func _on_playing_node_gui_input(event:InputEvent, node = null, node_uid:int = -1) -> void:
	# on mouse click
	if event is InputEventMouseButton:
		# ... double click
		if event.is_doubleclick():
			# jump to the respective node on the grid
			if node_uid >= 0 :
				_request_mind("locate_node_on_grid", { "id": node_uid, "highlight": true } )
	pass

# make this panel,
# dragable
# ... it also makes the panel compete for the parent's top z-index by default
onready var drag_point = get_node(Addressbook.CONSOLE.drag_point)
onready var dragability = Helpers.Dragable.new(self, drag_point)
# and resizable
onready var resize_point = get_node(Addressbook.CONSOLE.resize_point)
onready var resizability = Helpers.Resizable.new(self, resize_point)

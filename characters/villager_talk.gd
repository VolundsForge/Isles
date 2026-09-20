extends Node

@export var lines: PackedStringArray = PackedStringArray([
	"Washed up on the sand, did you? Happens more than you'd think.",
	"This is my house. Door's open if you need shade.",
	"There's a cave further inland. Something in there glints — and it isn't empty.",
	"Want off the island? Talk to the captain at the harbor.",
])

var _index: int = 0


func _ready() -> void:
	var npc := get_parent()
	var interaction := npc.get_node_or_null("BasicInteraction")
	if interaction:
		interaction.interaction_text = "Talk"
		if interaction.has_signal("basic_signal") and not interaction.basic_signal.is_connected(_on_talk):
			interaction.basic_signal.connect(_on_talk)
	var camera := npc.get_node_or_null("SecurityCamera")
	if camera:
		camera.process_mode = Node.PROCESS_MODE_DISABLED
	var timer := npc.get_node_or_null("CheckPlayerTimer")
	if timer is Timer:
		(timer as Timer).stop()


func _on_talk() -> void:
	if lines.is_empty():
		return
	var player := CogitoSceneManager._current_player_node
	if player == null or player.player_interaction_component == null:
		return
	var line := lines[_index % lines.size()]
	_index += 1
	player.player_interaction_component.send_hint(null, line)

extends Node

## Isle-v1 loop flags. Persist to user:// so later scenes can skip the cave.
## har_skatt
var has_treasure: bool = false
## har_betalat
var has_paid_captain: bool = false
## intro_sett
var intro_seen: bool = false

const SAVE_PATH := "user://isle_game_state.cfg"


func _ready() -> void:
	load_from_disk()


func reset() -> void:
	has_treasure = false
	has_paid_captain = false
	intro_seen = false
	save_to_disk()


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("isle", "has_treasure", has_treasure)
	cfg.set_value("isle", "has_paid_captain", has_paid_captain)
	cfg.set_value("isle", "intro_seen", intro_seen)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("GameState: could not save to %s (%s)" % [SAVE_PATH, error_string(err)])


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	has_treasure = bool(cfg.get_value("isle", "has_treasure", false))
	has_paid_captain = bool(cfg.get_value("isle", "has_paid_captain", false))
	intro_seen = bool(cfg.get_value("isle", "intro_seen", false))

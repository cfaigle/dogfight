extends Node

# NOTE:
# This script is autoloaded as the singleton `GameEvents` (see project.godot).
# Don't declare a `class_name GameEvents` here, otherwise the class name would
# shadow the autoload instance and break calls like `GameEvents.reset()`.

signal score_changed(new_score: int)
signal wave_changed(wave: int)
signal target_changed(target: Node)
signal missile_lock_changed(locked: bool, progress: float)
signal player_health_changed(hp: float, max_hp: float)
signal player_destroyed()
signal enemy_destroyed(enemy: Node)
signal enemy_spawned(enemy: Node)
signal hit_confirmed(strength: float)
signal red_square_destroyed(position: Vector3)

var score = 0
var wave = 1

func reset() -> void:
    score = 0
    wave = 1
    score_changed.emit(score)
    wave_changed.emit(wave)

func add_score(delta: int) -> void:
    score += delta
    score_changed.emit(score)

func _ready():
    print("GameEvents autoload initialized successfully!")

func set_wave(w: int) -> void:
    wave = w
    wave_changed.emit(wave)

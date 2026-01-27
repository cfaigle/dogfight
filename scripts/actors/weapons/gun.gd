extends Node3D

var _flash_mesh: QuadMesh = QuadMesh.new()

@export var defs: Resource
# Keep this as a plain Array for maximum compatibility across GDScript versions.
@export var muzzle_paths: Array = []
@export var owner_hitbox_path: NodePath = NodePath("Hitbox")
@export var tracer_scene: PackedScene

var _muzzles: Array = []  # Array of Node3D muzzle points (resolved from muzzle_paths)

const AutoDestructScript = preload("res://scripts/components/auto_destruct.gd")
const ExplosionScript = preload("res://scripts/fx/explosion.gd")

var cooldown = 0.075
var heat_per_shot = 0.055
var damage = 10.0
var range = 1600.0
var spread_deg = 0.35

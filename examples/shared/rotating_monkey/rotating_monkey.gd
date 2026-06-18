extends Node3D
## A self-contained, slowly rotating monkey stage (environment, light, camera,
## and Suzanne). Spinning the monkey makes any main-thread stutter visible.

@onready var _monkey: Node3D = $Monkey


func _process(delta: float) -> void:
	_monkey.rotate_z(delta)

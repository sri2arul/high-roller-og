extends Camera3D

@export var target: Node3D


func _process(delta):
	if !target: return
	global_position.x = lerp(global_position.x, target.global_position.x - 7, 1)
	global_position.y = lerp(global_position.y, target.global_position.y + 11, 1)
	global_position.z = lerp(global_position.z, target.global_position.z + 7, 1)
	look_at(target.global_position, Vector3.UP)

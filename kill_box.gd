extends Area3D

func _on_body_entered(body):
	if body.name == "Dice":
		get_node("/root/Main/LevelMan").loadlvl(get_node("/root/Main/LevelMan").level_index)

extends Button

func _pressed():
	get_node("/root/Main/CanvasLayer/WinScreen").visible = false
	get_node("/root/Main/LevelMan").next()

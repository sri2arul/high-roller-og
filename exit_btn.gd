extends Button

func _pressed():
	var lm = get_node("/root/Main/LevelMan")
	lm.level_index -= 1
	if lm.level_index < 0:
		lm.level_index = 0
	lm.loadlvl(lm.level_index)

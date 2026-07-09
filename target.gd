extends Area3D

@export var gm: Node

func _on_body_entered(body):
	print("body entered:", body.name)
	if body.name == "Dice":
		gm.next()

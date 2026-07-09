extends RigidBody3D

enum State{IDLE, AIR, LANDED, WAITING}
var state = State.WAITING
var touching: = false



var airtime: = 0.0
var flips: = 0
var finalrotation: = 0.0
var points: = 0
var rot_total: = 0.0

@onready var hud = get_node("/root/Main/CanvasLayer/AimLabel")
@onready var pts_label = get_node("/root/Main/CanvasLayer/PointsLabel")

func _physics_process(delta):
	rotation.x = 0
	rotation.y = 0
	if state == State.WAITING:
		hud.text = "press space to start"
		freeze = true
	elif state == State.IDLE:
		hud.text = "on the edge..."
	elif state == State.AIR:
		var lorx= get_viewport().get_mouse_position().x
		var scrsizx= get_viewport().size.x
		if lorx< scrsizx/2:
			if Input.is_action_pressed("ui_accept"):
				apply_torque_impulse(Vector3(0, 0, 0.01))
		else:
			if Input.is_action_pressed("ui_accept"):
				apply_torque_impulse(Vector3(0, 0, -0.01))
		hud.text = "spin it!"
		airtime += delta
		var rot_diff = abs(rotation.z - finalrotation)
		rot_total += rot_diff
		finalrotation = rotation.z
		flips = int(rot_total / (PI * 2))
		pts_label.text = str(int(airtime * 100) + (flips * 100)) + " pts"
		if touching and linear_velocity.length() < 1.2 and angular_velocity.length() < 1.2:
			var tilt = abs(rotation.z)
			if tilt < 0.45 or abs(tilt - PI) < 0.45:
				state = State.LANDED
				points = int(airtime * 100) + (flips * 100)
				pts_label.text = str(points) + " pts"
				get_node("/root/Main/CanvasLayer/WinScreen").visible = true
			else:
				state = State.LANDED
				hud.text = "FAIL"
				get_node("/root/Main/LevelMan").loadlvl(get_node("/root/Main/LevelMan").level_index)
		elif state == State.LANDED:
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO

func _input(event):
	if state == State.WAITING and Input.is_action_just_pressed("roll"):
		freeze = false
		state = State.IDLE
	elif state == State.IDLE and Input.is_action_just_pressed("roll") and linear_velocity.length() < 2.0:
		launch()

func launch():
	state = State.AIR

	airtime = 0.0
	flips = 0
	rot_total = 0.0
	finalrotation = rotation.z
	var angle = rotation.z
	var dir = Vector3(sin(angle), cos(angle), 0)
	linear_velocity = dir * 7
	print("if you can see this ur going thru my code btw")

func _on_body_entered(body):
	var lm = get_node("/root/Main/LevelMan")
	if lm.current_level and body == lm.current_level.get_lander():
		touching = true

func _on_body_exited(body):
	var lm = get_node("/root/Main/LevelMan")
	if lm.current_level and body == lm.current_level.get_lander():
		touching = false

func reset():
	state = State.WAITING
	freeze = true

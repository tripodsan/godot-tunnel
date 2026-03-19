extends CharacterBody3D

@export var mouse_sensitivity: float = 0.002
@export var speed: float = 50
@onready var camera = $Camera3D

func _ready():
  # Lock the mouse cursor to the game window
  Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
  if event.is_action_pressed('escape'):
    if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
      Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    else:
      Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

  # Handle Mouse Look
  if event is InputEventMouseMotion:
    rotate_y(-event.relative.x * mouse_sensitivity)
    camera.rotate_x(-event.relative.y * mouse_sensitivity)

    # Clamp camera to prevent flipping upside down
    camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))

func _physics_process(delta):
  var dir = Vector3.ZERO
  if Input.is_action_pressed("forward"):	dir.z -= 1
  if Input.is_action_pressed("back"): dir.z += 1
  if Input.is_action_pressed("left"): dir.x -= 1
  if Input.is_action_pressed("right"): dir.x += 1
  if Input.is_action_pressed("up"): dir.y += 1
  if Input.is_action_pressed("down"): dir.y -= 1
  dir = dir.normalized()
  var forward = camera.global_transform.basis.z
  var right = camera.global_transform.basis.x
  var up = camera.global_transform.basis.y
  velocity = (forward * dir.z + right * dir.x + up * dir.y) * speed
  move_and_slide()

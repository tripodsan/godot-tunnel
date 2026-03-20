extends CharacterBody3D

@export var mouse_sensitivity: float = 0.002
@export var speed: float = 50
@onready var camera = $Camera3D

@export var tunnel:Tunnel
@onready var visual: Node3D = $visual
@onready var ray_cast_3d: RayCast3D = $RayCast3D

var _rotate_y:float = 0.0

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
    _rotate_y = -event.relative.x * mouse_sensitivity
    #rotate_y(-event.relative.x * mouse_sensitivity)
    camera.rotate_x(-event.relative.y * mouse_sensitivity)

    # Clamp camera to prevent flipping upside down
    camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))

func _physics_process(delta):
  var floorNormal := tunnel.get_normal(global_position)
  up_direction = floorNormal
  var floorQuaternion := Quaternion(transform.basis.y, floorNormal)
  transform.basis = Basis(floorQuaternion * basis.get_rotation_quaternion()).rotated(floorNormal, _rotate_y)

  _rotate_y = 0
  #if _rotate_y != 0:
    #transform = transform.rotated_local(floorNormal, _rotate_y)
  #var pos:Vector3 = ray_cast_3d.get_collision_point()

  velocity -= floorNormal * 10.0

  var input_dir := Input.get_vector("left", "right", "forward", "back")
  var direction := (global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
  if direction:
    var targetAngle = atan2(direction.x, direction.z) - rotation.y
    #visual.rotation.y = lerp_angle(visual.rotation.y, targetAngle, 0.1)

    velocity.x = direction.x * speed
    velocity.z = direction.z * speed
  else:
    velocity.x = move_toward(velocity.x, 0, speed)
    velocity.z = move_toward(velocity.z, 0, speed)

  move_and_slide()
  #velocity
  #global_position = pos + floorNormal * 1.0
  ##transform.basis.y = floorNormal
  ##global_position = tunnel.get_shell_position(radial)
#
  #var input_dir := Input.get_vector("left", "right", "forward", "back")
#
  #radial += input_dir * Vector2(speed, 0.1) * delta

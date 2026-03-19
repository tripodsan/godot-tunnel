@tool
extends Node3D

# ─── Parameters ───────────────────────────────────────────────────────────────
@export var segments_ahead    : int     = 40
@export var base_ring_verts   : int     = 16   # minimum ring resolution
@export var segment_length    : float  = 3.0
@export var min_radius        : float  = 1.5
@export var max_radius        : float  = 12.0
@export var radius_noise_freq : float  = 0.15
@export var path_noise_freq   : float  = 0.08
@export var path_noise_amp    : float  = 4.0
@export_tool_button("Rebuild") var tool_button_rebuild = _build_tube

# ─── Internals ────────────────────────────────────────────────────────────────
var _mesh_instance : MeshInstance3D
var _col_shape     : CollisionShape3D
var _static_body   : StaticBody3D

# Per-ring data
class Ring:
  var center   : Vector3
  var tangent  : Vector3
  var normal   : Vector3
  var binormal : Vector3
  var radius   : float
  var verts    : int      # 8, 16, or 32

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
  _build_tube()

func _build_tube() -> void:
  # Clean up previous nodes
  for c in get_children():
    c.queue_free()

  _mesh_instance = MeshInstance3D.new()
  add_child(_mesh_instance)
  _mesh_instance.owner = owner
  _mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  var mat := StandardMaterial3D.new()
  mat.cull_mode = BaseMaterial3D.CULL_DISABLED
  _mesh_instance.material_overlay = mat

  if not Engine.is_editor_hint():
    _static_body = StaticBody3D.new()
    add_child(_static_body)

  var rings := _generate_rings()
  var arr_mesh := _build_mesh(rings)
  _mesh_instance.mesh = arr_mesh

  if not Engine.is_editor_hint():
    var shape := ConcavePolygonShape3D.new()
    shape.set_faces(arr_mesh.get_faces())
    _col_shape = CollisionShape3D.new()
    _col_shape.shape = shape
    _static_body.add_child(_col_shape)

# ─── Step 1: Generate spline centerline + frames ──────────────────────────────
func _generate_rings() -> Array[Ring]:
  var rings : Array[Ring] = []

  # Build control points with path noise
  var ctrl : Array[Vector3] = []
  for i in range(segments_ahead + 3):
    var t := float(i)
    var x := sin(t * path_noise_freq * 1.3) * path_noise_amp
    var y := sin(t * path_noise_freq * 0.7 + 1.0) * path_noise_amp * 0.6
    ctrl.append(Vector3(x, y, -t * segment_length))

  # Sample Catmull-Rom and compute rotation-minimizing frames
  var prev_n := Vector3.UP

  for i in range(1, ctrl.size() - 2):
    var p0 := ctrl[i - 1]
    var p1 := ctrl[i]
    var p2 := ctrl[i + 1]
    var p3 := ctrl[i + 2] if i + 2 < ctrl.size() else ctrl[i + 1]

    var center  := _catmull_rom(p0, p1, p2, p3, 0.0)
    var tangent := _catmull_rom_tangent(p0, p1, p2, p3, 0.0).normalized()

    # Rotation-minimizing frame
    var n := (prev_n - tangent * prev_n.dot(tangent)).normalized()
    var b := tangent.cross(n).normalized()
    prev_n = n

    # Radius and LOD
    var noise_t  := float(i) * radius_noise_freq
    var nr       := (sin(noise_t) * 0.5 + 0.5)           # 0..1
    nr           = nr * nr * (3.0 - 2.0 * nr)            # smoothstep
    var radius   := lerpf(min_radius, max_radius, nr)
    var vcount   := _verts_for_radius(radius)

    var ring     := Ring.new()
    ring.center  = center
    ring.tangent = tangent
    ring.normal  = n
    ring.binormal = b
    ring.radius  = radius
    ring.verts   = vcount
    rings.append(ring)

  return rings

# ─── Step 2: Build ArrayMesh ──────────────────────────────────────────────────
func _build_mesh(rings: Array[Ring]) -> ArrayMesh:
  var verts   : PackedVector3Array = []
  var normals : PackedVector3Array = []
  var uvs     : PackedVector2Array = []
  var indices : PackedInt32Array   = []

  # Build per-ring vertex arrays
  # ring_start[i] = first index in verts[] for ring i
  var ring_start : Array[int] = []
  var arc_len    := 0.0

  for i in range(rings.size()):
    ring_start.append(verts.size())
    var ring := rings[i]
    var k    := ring.verts
    for j in range(k):
      var angle := TAU * float(j) / float(k)
      var local := cos(angle) * ring.normal + sin(angle) * ring.binormal
      var pos   := ring.center + local * ring.radius
      verts.append(pos)
      normals.append(-local)          # inward normals (we're inside)
      uvs.append(Vector2(float(j) / float(k), arc_len))
    if i > 0:
      arc_len += rings[i].center.distance_to(rings[i-1].center) / (max_radius * TAU)

  # Stitch rings
  for i in range(rings.size() - 1):
    var ka  := rings[i].verts
    var kb  := rings[i + 1].verts
    var sa  := ring_start[i]
    var sb  := ring_start[i + 1]

    if ka == kb:
      _stitch_equal(indices, sa, sb, ka)
    elif kb == ka * 2:
      _stitch_split(indices, sa, sb, ka)   # 1 → 2
    elif ka == kb * 2:
      _stitch_merge(indices, sa, sb, kb)   # 2 → 1
    else:
      # Fallback: resample both rings to lcm count via fan centroid
      _stitch_fan_bridge(indices, verts, normals, uvs,
                rings[i], rings[i+1], sa, sb)

  var arr := []
  arr.resize(Mesh.ARRAY_MAX)
  arr[Mesh.ARRAY_VERTEX] = verts
  arr[Mesh.ARRAY_NORMAL] = normals
  arr[Mesh.ARRAY_TEX_UV] = uvs
  arr[Mesh.ARRAY_INDEX]  = indices

  var am := ArrayMesh.new()
  am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
  return am

# ─── Stitching helpers ────────────────────────────────────────────────────────

# Equal ring sizes — simple quad strip
func _stitch_equal(idx: PackedInt32Array, sa: int, sb: int, k: int) -> void:
  for j in range(k):
    var j1 := (j + 1) % k
    idx.append_array([sa+j, sb+j, sa+j1,
               sb+j, sb+j1, sa+j1])

# 1:2 split — coarse ring A, fine ring B (kb = 2*ka)
# Each coarse edge fans into 3 triangles
func _stitch_split(idx: PackedInt32Array, sa: int, sb: int, ka: int) -> void:
  for j in range(ka):
    var j1   := (j + 1) % ka
    var fj   := j * 2          # fine index for coarse vertex j
    var fj1  := fj + 1         # mid fine vertex
    var fj2  := (fj + 2) % (ka * 2)  # fine index for coarse vertex j+1
    # Triangle fan: A[j] → A[j+1] with B[fj], B[fj1], B[fj2] between them
    idx.append_array([sa+j,  sb+fj,  sb+fj1,
               sa+j,  sb+fj1, sa+j1,
               sa+j1, sb+fj1, sb+fj2])

# 2:1 merge — coarse ring A (ka = 2*kb), fine ring B
# A: 0 1 2 3 4 5 6
#    __ __
#    |/_\|
# B: 0   1   2   3
# Mirror of split
func _stitch_merge(idx: PackedInt32Array, sa: int, sb: int, kb: int) -> void:
  for j in range(kb):
    var j1  := (j + 1) % kb
    var fj  := j * 2
    var fj1 := fj + 1
    var fj2 := (fj + 2) % (kb * 2)
    idx.append_array([
      sb+j,  sa+fj1, sa+fj,
      sb+j,  sb+j1,  sa+fj1,
      sb+j1, sa+fj2, sa+fj1
    ])

# Fallback bridge using a centroid fan (handles arbitrary mismatches)
func _stitch_fan_bridge(idx: PackedInt32Array,
             verts: PackedVector3Array,
             normals: PackedVector3Array,
             uvs: PackedVector2Array,
             ra: Ring, rb: Ring,
             sa: int, sb: int) -> void:
  # Insert a centroid vertex between the two rings
  var mid_center := (ra.center + rb.center) * 0.5
  var mid_n      := -(ra.normal + rb.normal).normalized()
  var ci         := verts.size()
  verts.append(mid_center)
  normals.append(mid_n)
  uvs.append(Vector2(0.5, 0.5))

  # Fan from ring A to centroid
  for j in range(ra.verts):
    var j1 := (j + 1) % ra.verts
    idx.append_array([sa+j, ci, sa+j1])

  # Fan from centroid to ring B
  for j in range(rb.verts):
    var j1 := (j + 1) % rb.verts
    idx.append_array([ci, sb+j, sb+j1])

# ─── Helpers ──────────────────────────────────────────────────────────────────

# LOD: pick ring resolution based on radius
func _verts_for_radius(r: float) -> int:
  if   r < 2.5:  return 8
  elif r < 5.0:  return 16
  else:           return 32

# Catmull-Rom position
func _catmull_rom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
  var t2 := t * t
  var t3 := t2 * t
  return 0.5 * ((2.0*p1)
    + (-p0 + p2) * t
    + (2.0*p0 - 5.0*p1 + 4.0*p2 - p3) * t2
    + (-p0 + 3.0*p1 - 3.0*p2 + p3) * t3)

# Catmull-Rom tangent (derivative)
func _catmull_rom_tangent(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
  var t2 := t * t
  return 0.5 * ((-p0 + p2)
    + (2.0*p0 - 5.0*p1 + 4.0*p2 - p3) * 2.0 * t
    + (-p0 + 3.0*p1 - 3.0*p2 + p3) * 3.0 * t2)

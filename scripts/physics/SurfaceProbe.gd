class_name SurfaceProbe
extends RefCounted

## Geometric queries against the world's static collision. Pure geometry - this class knows nothing
## about skating, tricks or grinding, and must stay that way. It answers "what is under this point",
## "what is ahead of this point", and "is there an edge near this point"; deciding what to DO with
## those answers belongs to the caller.
##
## Uses direct space state queries rather than RayCast3D nodes deliberately: the rig's raycasts were
## children of BoardPivot, so they tilted with trick pitch (22 deg on every pop) and probed sideways
## exactly when landing accuracy mattered most. Explicit world-space from/to keeps probe direction
## true regardless of how the board is rotated.

## A single surface hit. `valid` is false when the ray reached nothing.
class Hit extends RefCounted:
	var valid: bool = false
	var position: Vector3 = Vector3.ZERO
	var normal: Vector3 = Vector3.UP
	var collider: Object = null

## An edge found between two faces, with the direction it runs in.
class Edge extends RefCounted:
	var valid: bool = false
	var position: Vector3 = Vector3.ZERO
	var direction: Vector3 = Vector3.FORWARD # Unit tangent along the edge.
	var top_normal: Vector3 = Vector3.UP

var _space: PhysicsDirectSpaceState3D
## Always empty today: the rig is a plain Node3D with no physics body, so there is nothing of
## its own for the probes to hit. Kept for when that changes.
var _exclude: Array[RID] = []
var _mask: int = 0xFFFFFFFF

func _init(space: PhysicsDirectSpaceState3D, exclude: Array[RID] = [], mask: int = 0xFFFFFFFF) -> void:
	_space = space
	_exclude = exclude
	_mask = mask

## Raw cast between two world-space points.
func cast(from: Vector3, to: Vector3) -> Hit:
	var hit := Hit.new()
	if _space == null:
		return hit
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = _exclude
	params.collision_mask = _mask
	params.hit_back_faces = false
	var result: Dictionary = _space.intersect_ray(params)
	if result.is_empty():
		return hit
	hit.valid = true
	hit.position = result["position"]
	hit.normal = result["normal"]
	hit.collider = result.get("collider")
	return hit

## Straight down from `from`, up to `distance` metres. Direction is always true world down, never
## affected by how the board happens to be rotated.
func cast_down(from: Vector3, distance: float) -> Hit:
	return cast(from, from + Vector3.DOWN * distance)

## Highest surface found beneath a set of world-space points (the truck corners, typically).
## Returns an invalid Hit when nothing is under any of them - which is exactly the "rolled off a
## ledge" case, so the caller needs no special handling for it.
func highest_below(points: PackedVector3Array, distance: float) -> Hit:
	var best := Hit.new()
	for p in points:
		var h: Hit = cast_down(p, distance)
		if h.valid and (not best.valid or h.position.y > best.position.y):
			best = h
	return best

## Horizontal cast used for wall blocking. `direction` is expected to be horizontal and normalised.
func cast_horizontal(from: Vector3, direction: Vector3, distance: float) -> Hit:
	return cast(from, from + direction * distance)

## Finds the edge of a ledge near `top_hit`, without any authored spline.
##
## An edge is the intersection of two faces, so its direction is the cross product of their normals:
## probe down to get the top face, then probe sideways just beneath it to find the side face. Works
## on any convex edge of any static body, and because callers re-run it every tick it follows
## segmented or curved edges naturally.
##
## `side_dirs` are the horizontal directions to look for a drop-off in (usually board left/right).
func find_edge_near(top_hit: Hit, side_dirs: Array[Vector3], reach: float, drop: float) -> Edge:
	var edge := Edge.new()
	if not top_hit.valid:
		return edge
	# Sit just under the top face so the sideways ray strikes the side wall, not the top.
	var probe_origin: Vector3 = top_hit.position + Vector3.DOWN * drop
	for dir in side_dirs:
		var flat: Vector3 = Vector3(dir.x, 0.0, dir.z)
		if flat.length_squared() < 0.0001:
			continue
		flat = flat.normalized()
		var side: Hit = cast_horizontal(probe_origin - flat * reach, flat, reach)
		if not side.valid:
			continue
		var tangent: Vector3 = top_hit.normal.cross(side.normal)
		if tangent.length_squared() < 0.0001:
			continue # Faces are parallel - not an edge.
		edge.valid = true
		edge.direction = tangent.normalized()
		edge.top_normal = top_hit.normal
		edge.position = Vector3(side.position.x, top_hit.position.y, side.position.z)
		return edge
	return edge

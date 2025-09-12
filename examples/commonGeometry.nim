import vmath

proc normal*(v: Vec2): Vec2 =
  return v / length(v)

proc normal3*(v: Vec3): Vec3 =
  return v / length(v)


proc lenOnAxis*(v: Vec2, axis: Vec2): float32 =
  return v.dot(axis.normal)

proc projectToAxis*(v: Vec2, axis: Vec2): Vec2 =
  return axis.normal * v.lenOnAxis(axis.normal)


proc lenOnAxis3*(v: Vec3, axis: Vec3): float32 =
  return v.dot(axis.normal3)

proc projectToAxis3*(v: Vec3, axis: Vec3): Vec3 =
  return axis.normal3 * v.lenOnAxis3(axis.normal3)


proc cross3*(a, b: Vec3): Vec3 =
  vec3(
    a.y * b.z - a.z * b.y,
    a.z * b.x - a.x * b.z,
    a.x * b.y - a.y * b.x
  )


proc rotate*(v: Vec3, axis: Vec3, angle: float32): Vec3 =
  v * cos(angle) + cross3(v, axis) * sin(angle) + axis * v.lenOnAxis3(axis) * (1 - cos(angle))



proc overlapsTri*(tri_0: Vec2, tri_1: Vec2, tri_2: Vec2, p: Vec2): bool =
  let areaOrig = abs(
    (tri_1.x - tri_0.x) * (tri_2.y - tri_0.y) -
    (tri_2.x - tri_0.x) * (tri_1.y-tri_0.y)
  )

  let area1 = abs((tri_0.x - p.x) * (tri_1.y - p.y) - (tri_1.x - p.x) * (tri_0.y - p.y))
  let area2 = abs((tri_1.x - p.x) * (tri_2.y - p.y) - (tri_2.x - p.x) * (tri_1.y - p.y))
  let area3 = abs((tri_2.x - p.x) * (tri_0.y - p.y) - (tri_0.x - p.x) * (tri_2.y - p.y))

  return (area1 + area2 + area3 - areaOrig).abs < 0.0001


proc distanceToSection*(pt: Vec2, p1: Vec2, p2: Vec2): float32 =
  let dp1 = pt - p1
  let dp2 = pt - p2

  let axis = (p2 - p1).normal
  let l = dp1.lenOnAxis(axis)

  if l >= 0 and l <= (p2 - p1).length:
    return length(dp1 - dp1.projectToAxis(axis))
  elif l < 0:
    return length(dp1)
  else:
    return length(dp2)


proc signedDistanceToPlane*(ray_start: Vec3, ray_dir: Vec3, origin: Vec3, normal: Vec3): float32 =
  ## a distance to hit a point on a plane via `ray`
  let l = (origin - ray_start).lenOnAxis3(normal)

  let dl = ray_dir.lenOnAxis3(normal) / ray_dir.length
  return l / dl


proc overlaps*(p: Vec2, tri_p1: Vec2, tri_p2: Vec2, tri_p3: Vec2): bool =
  # from treeform/bumpy

  # get the area of the triangle
  let areaOrig = abs(
    (tri_p2.x - tri_p1.x) * (tri_p3.y - tri_p1.y) -
    (tri_p3.x - tri_p1.x) * (tri_p2.y - tri_p1.y)
  )

  # get the area of 3 triangles made between the point
  # and the corners of the triangle
  let
    area1 = abs((tri_p1.x - p.x) * (tri_p2.y - p.y) - (tri_p2.x - p.x) * (tri_p1.y - p.y))
    area2 = abs((tri_p2.x - p.x) * (tri_p3.y - p.y) - (tri_p3.x - p.x) * (tri_p2.y - p.y))
    area3 = abs((tri_p3.x - p.x) * (tri_p1.y - p.y) - (tri_p1.x - p.x) * (tri_p3.y - p.y))

  # If the sum of the three areas equals the original,
  # we're inside the triangle!
  return abs(area1 + area2 + area3 - areaOrig) < 1e-5


proc overlapsAssumingInSamePlane*(pt: Vec3, tri_p1: Vec3, tri_p2: Vec3, tri_p3: Vec3): bool =
  let x = (tri_p2 - tri_p1).normal3
  var y = (tri_p3 - tri_p1).normal3
  y = (y - y.lenOnAxis3(x)).normal3

  return overlaps(
    vec2((pt - tri_p1).lenOnAxis3(x), (pt - tri_p1).lenOnAxis3(y)),
    vec2(0, 0),
    vec2((tri_p2 - tri_p1).lenOnAxis3(x), (tri_p2 - tri_p1).lenOnAxis3(y)),
    vec2((tri_p3 - tri_p1).lenOnAxis3(x), (tri_p3 - tri_p1).lenOnAxis3(y)),
  )



proc raycast_depth*(ray_start: Vec3, ray_dir: Vec3, tri_p1: Vec3, tri_p2: Vec3, tri_p3: Vec3): float32 =
  ## assumes ray hits the triangle
  let x = (tri_p2 - tri_p1).normal3
  var y = (tri_p3 - tri_p1).normal3
  y = (y - y.projectToAxis3(x)).normal3
  var triNormal = x.cross3(y)
  return signedDistanceToPlane(ray_start, ray_dir, tri_p1, triNormal)


proc raycast_hit*(ray_start: Vec3, ray_dir: Vec3, tri_p1: Vec3, tri_p2: Vec3, tri_p3: Vec3): bool =
  var triNormal = (tri_p2 - tri_p1).cross3(tri_p3 - tri_p1).normal3

  let distance = signedDistanceToPlane(ray_start, ray_dir, tri_p1, triNormal)
  let point = ray_start + ray_dir * distance

  return overlapsAssumingInSamePlane(point, tri_p1, tri_p2, tri_p3)


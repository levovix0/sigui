import pkg/[vmath, chroma]

proc vec4*(color: Color): Vec4 =
  vec4(color.r, color.g, color.b, color.a)

proc color*(v: Vec4): Color =
  Color(r: v.x, g: v.y, b: v.z, a: v.w)


proc round*(v: Vec2): Vec2 =
  vec2(round(v.x), round(v.y))

proc ceil*(v: Vec2): Vec2 =
  vec2(ceil(v.x), ceil(v.y))

proc floor*(v: Vec2): Vec2 =
  vec2(floor(v.x), floor(v.y))


import std/[json, strutils, math]
import pkg/[vmath, chroma]
import ../[uiobj, properties]


#* ------------- tree dump (machine-readable) ------------- *#

proc parseDumpedValue(value: string): JsonNode =
  ## converts a value printed by `$` into a json value when it is trivially parseable,
  ## otherwise keeps it as a string
  case value
  of "true": return newJBool(true)
  of "false": return newJBool(false)
  of "nil": return newJNull()
  else: discard

  try:
    return newJInt(value.parseInt)
  except CatchableError:
    discard

  try:
    return newJFloat(value.parseFloat)
  except CatchableError:
    discard

  result = newJString(value)


proc uiJson*(obj: Uiobj): JsonNode =
  ## builds a machine-readable json representation of a component tree.
  ## properties that differ from their default values are included as fields,
  ## nested components are placed into the "childs" array
  if obj == nil: return newJNull()

  result = %*{
    "type": obj.componentTypeName,
    "globalBox": [round(obj.globalX[]).int, round(obj.globalY[]).int, round(obj.w[]).int, round(obj.h[]).int],
    "localBox": [round(obj.x[]).int, round(obj.y[]).int, round(obj.w[]).int, round(obj.h[]).int],
  }

  for field in obj.formatFields():
    let i = field.find(':')
    if i == -1: continue
    let
      name = field[0 ..< i].strip
      value = field[(i+1) ..< field.len].strip
    if name == "box": continue  # it is already included as localBox
    result[name] = parseDumpedValue(value)

  var childs = newJArray()
  for child in obj.childs:
    childs.add child.uiJson
  if childs.len > 0:
    result["childs"] = childs


proc uiJsonRepr*(obj: Uiobj): string =
  ## `uiJson` pretty-printed as a json string
  pretty obj.uiJson


proc uiRepr*(obj: Uiobj): string =
  ## builds a compact machine-readable representation of a component tree, one component per line
  ## example: "UiRect(globalBox = [10, 20, 100x50], color = #FF0000)"
  if obj == nil: return "nil"

  result = obj.componentTypeName & "("
  result.add "globalBox = [" &
    $round(obj.globalX[]).int & ", " & $round(obj.globalY[]).int & ", " &
    $round(obj.w[]).int & "x" & $round(obj.h[]).int & "]"

  for field in obj.formatFields():
    let i = field.find(':')
    if i == -1: continue
    let
      name = field[0 ..< i].strip
      value = field[(i+1) ..< field.len].strip
    if name == "box": continue
    result.add ", " & name & " = " & value

  result.add ")"

  for child in obj.childs:
    for line in child.uiRepr.split('\n'):
      result.add "\n  " & line


proc findComponents*[T: Uiobj](obj: Uiobj, typ: typedesc[T]): seq[T] =
  ## returns all components that is of or inherited from `typ`
  if obj == nil: return
  if obj of T: result.add obj.T
  for child in obj.childs:
    result.add child.findComponents(typ)

proc findComponent*[T: Uiobj](obj: Uiobj, typ: typedesc[T]): T =
  ## returns first components that is of or inherited from `typ`
  if obj == nil: return nil
  if obj of T: return obj.T
  for child in obj.childs:
    let res = child.findComponent(typ)
    if res != nil: return res


proc findComponentsByExactType*(obj: Uiobj, name: string): seq[Uiobj] =
  ## returns all components in the subtree with componentTypeName == `name`
  ## (e.g. "Button", "UiText")
  if obj == nil: return
  if obj.componentTypeName == name: result.add obj
  for child in obj.childs:
    result.add child.findComponentsByExactType(name)

proc findComponentByExactType*(obj: Uiobj, name: string): Uiobj =
  ## returns the first component in the subtree with componentTypeName == `name`, nil if none
  if obj == nil: return nil
  if obj.componentTypeName == name: return obj
  for child in obj.childs:
    let res = child.findComponentByExactType(name)
    if res != nil: return res


proc componentAt*(obj: Uiobj, pos: Vec2): Uiobj =
  ## returns the deepest component in the subtree that contains `pos`
  ## (in window coordinates), nil if there is none.
  ## hidden/collapsed components and their subtrees are skipped
  proc impl(o: Uiobj): Uiobj =
    if o == nil: return nil
    if o.visibility[] in {hidden, collapsed}: return nil

    # children first (last drawn on top), so the deepest/frontmost match wins
    for i in countdown(o.childs.high, 0):
      let res = impl(o.childs[i])
      if res != nil: return res

    if pos.x in o.globalX[] .. (o.globalX[] + o.w[]) and
       pos.y in o.globalY[] .. (o.globalY[] + o.h[]):
      result = o

  result = impl(obj)


proc id*(obj: Uiobj): tuple[name: string, address: int] =
  ## alias for casting Uiobj to int
  ## this is recommended for obj identity comparison in check
  ((if obj == nil: "<nil>" else: obj.componentTypeName), cast[int](obj))


proc `~==`*(a: Color, b: Color, eps = 0.08): bool =
  ## returs if colors are almost equal
  ## this is recomended for use in check instead of `==`
  abs(a.r - b.r) < eps and
  abs(a.g - b.g) < eps and
  abs(a.b - b.b) < eps and
  abs(a.a - b.a) < eps

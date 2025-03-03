import std/[strutils, macros]
import pkg/[chroma, bumpy]
import pkg/fusion/[astdsl]
import ./[events, properties, uiobj {.all.}]

method componentTypeName*(this: Uiobj): string {.base.} = "Uiobj"


proc formatProperty[T](res: var seq[string], name: string, prop: Property[T]) =
  if (prop[] != typeof(prop[]).default or prop.changed.hasHandlers):
    when compiles($prop[]):
      res.add name & ": " & $prop[]


proc formatProperty[T](res: var seq[string], name: string, prop: CustomProperty[T]) =
  if (
    prop.get != nil and
    (prop[] != typeof(prop[]).default or prop.changed.hasHandlers)
  ):
    when compiles($prop[]):
      res.add name & ": " & $prop[]


proc formatValue[T](res: var seq[string], name: string, val: T) =
  if (val is bool) or (val is enum) or (val != typeof(val).default):
    when compiles($val):
      res.add name & ": " & $val


proc formatFieldsStatic[T: UiobjObjType](this: T): seq[string] {.inline.} =
  {.push, warning[Deprecated]: off.}
  result.add "box: " & $rect(this.x, this.y, this.w, this.h)
  
  for k, v in this.fieldPairs:
    when k in ["eventHandler", "parent", "childs", "x", "y", "w", "h", "initialized", "attachedToWindow", "anchors", "drawLayering"] or k.startsWith("m_"):
      discard
    
    elif k == "visibility":
      if v[] != visible:
        result.add k & ": " & $v[]
    
    elif v is Uiobj:
      ## todo
    
    elif v is Event:
      ## todo
    
    elif v is Property or v is CustomProperty:
      result.formatProperty(k, v)

    else:
      result.formatValue(k, v)

  {.pop.}


method formatFields*(this: Uiobj): seq[string] {.base.} =
  formatFieldsStatic(this[])


proc `$`*(this: Uiobj): string


proc `$`*(x: Color): string =
  result.add '"'
  if x.a == 1:
    result.add x.toHex
  else:
    result.add x.toHexAlpha
  result.add '"'


proc formatChilds(this: Uiobj): string =
  for x in this.childs:
    if result != "": result.add "\n\n"
    result.add $x


proc `$`*(this: Uiobj): string =
  if this == nil: return "nil"
  result = this.componentTypeName & ":\n"
  result.add this.formatFields().join("\n").indent(2)
  if this.childs.len > 0:
    result.add "\n\n"
    result.add this.formatChilds().indent(2)


macro declareComponentTypeName(t: typed) =
  result = buildAst:
    methodDef:
      let thisSym = genSym(nskParam, "this")
      ident"componentTypeName"
      empty(); empty()
      formalParams:
        bindSym"string"
        identDefs:
          thisSym
          t
          empty()
      empty(); empty()
      stmtList:
        newLit $t

registerReflection declareComponentTypeName, T is Uiobj and t != "Uiobj"


macro declareFormatFields(t: typed) {.used.} =
  result = buildAst:
    methodDef:
      let thisSym = genSym(nskParam, "this")
      
      ident"formatFields"
      empty(); empty()
      formalParams:
        bracketExpr:
          bindSym"seq"
          bindSym"string"
        identDefs:
          thisSym
          t
          empty()
      empty(); empty()
      stmtList:
        call bindSym"formatFieldsStatic":
          bracketExpr:
            thisSym

when defined(nimcheck) or defined(nimsuggest):
  discard
else:
  registerReflection declareFormatFields, T is Uiobj and t != "Uiobj"


when isMainModule:
  import ./[uibase, mouseArea]

  type MyComponent = ref object of UiRect
    invisibleProp: Property[int]
    visibleProp: Property[int] = 1.property
    field: int
  
  registerComponent MyComponent

  let x = MyComponent()
  x.makeLayout:
    this.color[] = color(1, 0, 0)
    this.w[] = 20
    this.h[] = 30
    this.field = 2

    - RectShadow.new as shadow:
      this.fill(parent, -5)
      this.drawLayer = before parent
      this.radius[] = 5
    
    - MouseArea.new:
      this.mouseDownAndUpInside.connectTo parent:
        discard

  echo x


when defined(sigui_debug_redrawInitiatedBy):
  sigui_debug_redrawInitiatedBy_formatFunction = proc(obj: Uiobj, alreadyRedrawing, hasWindow: bool): string =
    when defined(sigui_debug_redrawInitiatedBy_all):
      if alreadyRedrawing: result.add "redraw initiated (already redrawing):\n"
      elif not hasWindow: result.add "redraw initiated (no window):\n"
      else: result.add "redraw initiated:\n"
    else:
      if alreadyRedrawing: return "redraw initiated (already redrawing)"
      elif not hasWindow: return "redraw initiated (no window)"
      result.add "redraw initiated:\n"
  
    var hierarchy = obj.componentTypeName
    var parent = obj.parent
    while parent != nil:
      hierarchy = parent.componentTypeName & " > " & hierarchy
      parent = parent.parent
    result.add "  hierarchy: " & hierarchy & "\n"

    when defined(sigui_debug_redrawInitiatedBy_includeStacktrace):
      result.add "  stacktrace:\n" & getStackTrace().indent(4)
  
    result.add ($obj).indent(2)

import std/[strutils, macros]
import pkg/fusion/[astdsl]
import ./uibase {.all.}

method componentTypeName*(this: Uiobj): string {.base.} = "Uiobj"

proc formatFieldsStatic[T: UiobjObjType](this: T): seq[string] =
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
      if v[] != typeof(v[]).default or v.changed.hasHandlers:
        when compiles($v[]):
          result.add k & ": " & $v[]
    else:
      if v != typeof(v).default:
        when compiles($v):
          result.add k & ": " & $v

method formatFields*(this: Uiobj): seq[string] {.base.} =
  formatFieldsStatic(this[])


proc `$`*(this: Uiobj): string

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

registerReflection declareComponentTypeName


macro declareFormatFields(t: typed) =
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

registerReflection declareFormatFields


when isMainModule:
  import ./mouseArea

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

    - RectShadow() as shadow:
      this.fill(parent, -5)
      this.drawLayer = before parent
      this.radius[] = 5
    
    - MouseArea():
      this.mouseDownAndUpInside.connectTo parent:
        discard

  echo x

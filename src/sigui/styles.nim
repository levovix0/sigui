import std/[macros]
import pkg/fusion/matching
import ./[uibase]

type
  Styler* = ref object of UiObj
    style*: Property[proc(obj: UiObj)]

    objsCreatedUsingStyle: seq[UiObj]
    runningStyle: bool

registerComponent Styler


method recieve*(this: Styler, signal: Signal) =
  if signal of ChildAdded:
    if this.style[] != nil:
      if this.runningStyle:
        this.objsCreatedUsingStyle.add signal.ChildAdded.child
        this.style[](signal.ChildAdded.child)
      else:
        this.runningStyle = true
        this.style[](signal.ChildAdded.child)
        this.runningStyle = false

  procCall this.super.recieve(signal)


method init*(this: Styler) =
  procCall this.super.init

  this.style.changed.connectTo this:
    for x in this.objsCreatedUsingStyle:
      delete x
    this.objsCreatedUsingStyle = @[]

    if this.style[] != nil:
      proc impl(n: UiObj) =
        if n == nil: return
        this.style[](n)
        for x in n.childs:
          impl(x)
      
      impl(this)


macro makeStyle*(body: untyped): proc(obj: UiObj) =
  var styleBody = newStmtList()

  for x in body:
    case x
    of Command[Ident(strVal: "apply"), @style], Call[Ident(strVal: "apply"), @style]:
      styleBody.add newCall(style, ident("obj"))
    
    of Call[@typ, @body]:
      styleBody.add nnkIfStmt.newTree(
        nnkElifBranch.newTree(
          nnkInfix.newTree(
            ident("of"),
            ident("obj"),
            nnkBracketExpr.newTree(
              ident("typedesc"),
              typ
            )
          ),
          newCall(
            bindSym("makeLayout"),
            newCall(typ, ident("obj")),
            body
          )
        )
      )

  result = nnkStmtList.newTree(
    nnkLambda.newTree(
      newEmptyNode(),
      newEmptyNode(),
      newEmptyNode(),
      nnkFormalParams.newTree(
        newEmptyNode(),
        nnkIdentDefs.newTree(
          ident("obj"),
          bindSym("UiObj"),
          newEmptyNode()
        )
      ),
      newEmptyNode(),
      newEmptyNode(),
      styleBody
    )
  )

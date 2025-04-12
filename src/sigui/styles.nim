import std/[macros]
import ./[uiobj, properties]

type
  Styler* = ref object of Uiobj
    style*: Property[proc(obj: Uiobj)]

    objsCreatedUsingStyle: seq[Uiobj]
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
      proc impl(n: Uiobj) =
        if n == nil: return
        this.style[](n)
        for x in n.childs:
          impl(x)
      
      impl(this)


macro makeStyle*(body: untyped): proc(obj: Uiobj) =
  var styleBody = newStmtList()

  for x in body:
    # apply(style)
    if x.kind in {nnkCommand, nnkCall} and x.len == 2 and x[0] == ident("apply"):
      let style = x[1]
      styleBody.add newCall(style, ident("obj"))
    
    # typ: body
    elif x.kind == nnkCall and x.len == 2:
      let typ = x[0]
      let body = x[1]
      
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
          bindSym("Uiobj"),
          newEmptyNode()
        )
      ),
      newEmptyNode(),
      newEmptyNode(),
      styleBody
    )
  )

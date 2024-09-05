import std/[macros]
import pkg/fusion/matching
import ./[uibase]

type
  Styler* = ref object of UiObj
    style*: Property[proc(obj: UiObj)]

registerComponent Styler


method recieve*(this: Styler, signal: Signal) =
  if signal of ChildAdded:
    if this.style[] != nil:
      this.style[](signal.ChildAdded.child)

  procCall this.super.recieve(signal)


# todo: re-apply styles when Styler.style changes


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

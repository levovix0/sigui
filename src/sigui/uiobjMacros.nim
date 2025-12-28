import std/[macros, strutils]
import pkg/fusion/[astdsl]
import ./[uiobjOnly, events, properties]
export events, properties


type
  BindingKind = enum
    bindProperty
    bindValue
    bindProc
    bindBody


proc bindingImpl*(
  obj: NimNode,
  target: NimNode,
  body: NimNode,
  init: bool,
  kind: BindingKind,
  ctor: NimNode = newEmptyNode()
): NimNode =
  ## connects update proc to every `x[]` property changed, and invokes update proc instantly
  ##
  ## .. code-block:: nim
  ##   type MyObj = ref object of Uiobj
  ##     c: Property[int]
  ##   
  ##   let obj = MyObj()
  ##   obj.binding c:
  ##     if config.csd[]: parent[].b else: 10[]
  ##
  ## converts to (roughly):
  ##
  ## .. code-block:: nim
  ##   block bindingBlock:
  ##     let o {.cursor.} = obj
  ##     proc updateC(this: MyObj) =
  ##       this.c[] = if config.csd[]: parent[].b else: 10[]
  ##
  ##     config.csd.changed.connectTo o: updateC(this)
  ##     parent.changed.connectTo o: updateC(this)
  ##     10.changed.connectTo o: updateC(this)  # yes, 10[] will considered property too
  ##     updateC(o)
  
  let updateProc = genSym(nskProc, "bindingUpdate")
  
  let objCursor =
    case kind
    of bindProperty, bindProc:
      genSym(nskLet, "objCursor")
    of bindValue, bindBody:
      obj

  let thisInProc = genSym(nskParam, "thisInProc")
  var alreadyBinded: seq[NimNode]

  proc impl(stmts: var seq[NimNode], body: NimNode) =
    if body in alreadyBinded:
      return
    
    elif (
      var exp: NimNode
      if body.kind == nnkCall and body.len == 2 and body[0].kind in {nnkSym, nnkIdent} and body[0].strVal == "[]":
        exp = body[1]
        true
      elif body.kind == nnkBracketExpr and body.len == 1:
        exp = body[0]
        true
      else: false
    ):
      stmts.add: buildAst(call):
        bindSym("connectTo")
        dotExpr(exp, ident "changed")
        objCursor
        call updateProc:
          case kind
          of bindProperty, bindProc:
            objCursor
          of bindValue, bindBody:
            discard
          
      alreadyBinded.add body
      impl(stmts, exp)
    
    else:
      if body.kind == nnkAsgn and body.len == 2 and body[0].kind == nnkBracketExpr and body[0].len == 1:
        # skip assigning to a property (rhs and inner part of lhs still can have property access though)
        impl(stmts, body[0][0])
        impl(stmts, body[1])
      else:
        for x in body:
          impl(stmts, x)
  
  result = buildAst(blockStmt):
    ident "bindingBlock"
    stmtList:
      case kind
      of bindProperty, bindProc:
        letSection:
          identDefs(objCursor, empty(), obj)
      of bindValue, bindBody:
        discard
      
      procDef updateProc:
        empty(); empty()

        formalParams:
          empty()
          case kind
          of bindProperty, bindProc:
            identDefs(thisInProc, obj.getType, empty())
          of bindValue, bindBody:
            discard
        
        empty(); empty()
        
        stmtList:
          case kind
          of bindProperty:
            asgn:
              bracketExpr dotExpr(thisInProc, target)
              if ctor.kind != nnkEmpty: ctor else: body
          of bindValue:
            asgn:
              target
              if ctor.kind != nnkEmpty: ctor else: body
          of bindProc:
            call:
              target
              thisInProc
              if ctor.kind != nnkEmpty: ctor else: body
          of bindBody:
            if ctor.kind != nnkEmpty: ctor else: body
      
      var stmts: seq[NimNode]
      (impl(stmts, body))
      for x in stmts: x

      if init:
        case kind
        of bindProperty, bindProc:
          call updateProc, objCursor
        of bindValue, bindBody:
          call updateProc



macro binding*(obj: EventHandler, target: untyped, body: typed, init: static bool = true): untyped {.deprecated: "use bindingProperty instead".} =
  bindingImpl(obj, target, body, init, bindProperty)

macro bindingProperty*(obj: EventHandler, target: untyped, body: typed, init: static bool = true): untyped =
  bindingImpl(obj, target, body, init, bindProperty)

macro bindingValue*(obj: EventHandler, target: untyped, body: typed, init: static bool = true): untyped =
  bindingImpl(obj, target, body, init, bindValue)

macro bindingProc*(obj: EventHandler, target: untyped, body: typed, init: static bool = true): untyped =
  bindingImpl(obj, target, body, init, bindProc)


macro binding*[T: HasEventHandler](obj: T, target: untyped, body: typed, init: static bool = true): untyped {.deprecated: "use bindingProperty instead".} =
  bindingImpl(obj, target, body, init, bindProperty)

macro bindingProperty*[T: HasEventHandler](obj: T, target: untyped, body: typed, init: static bool = true): untyped =
  bindingImpl(obj, target, body, init, bindProperty)

macro bindingValue*[T: HasEventHandler](obj: T, target: untyped, body: typed, init: static bool = true): untyped =
  bindingImpl(obj, target, body, init, bindValue)

macro bindingProc*[T: HasEventHandler](obj: T, target: untyped, body: typed, init: static bool = true): untyped =
  bindingImpl(obj, target, body, init, bindProc)


macro binding*(obj: EventHandler | HasEventHandler, body: untyped, init: static bool = true): untyped =
  result = bindingImpl(obj, nil, body, init, bindBody)


macro bindingChangableChild[T](obj: T, target: untyped, body: untyped, ctor: typed): untyped =
  bindingImpl(obj, target, body, true, bindValue, ctor)


macro makeLayout*(obj: Uiobj, body: untyped) =
  ## tip: use a.makeLauyout(-soMeFuN()) instead of (let b = soMeFuN(); a.addChild(b); init b)
  ## 
  ## .. code-block:: nim
  ##   import sigui/uibase
  ##   
  ##   let a = UiRect.new
  ##   let b = UiRect.new
  ##   let c = UiRect.new
  ##   var ooo: ChangableChild[UiRect]
  ##   a.makeLayout:
  ##     - RectShadow(
  ##       radius: 7.5'f32.property,  # pre-initialization of properties (not recommended)
  ##       blurRadius: 10'f32.property,
  ##       color: color(0, 0, 0, 0.3).property
  ##     ) as shadowEffect
  ##   
  ##     - newUiRect():
  ##       this.fill(parent)
  ##       echo shadowEffect.radius
  ##       doassert parent.Uiobj == this.parent
  ##   
  ##       - ClipRect.new:
  ##         this.radius[] = 7.5
  ##         this.fill(parent, 10)
  ##         doassert root.Uiobj == this.parent.parent
  ##   
  ##         ooo --- UiRect.new:  # add changable child
  ##           this.fill(parent)
  ##   
  ##         - b
  ##         - UiRect.new
  ##   
  ##     - c:
  ##       this.fill(parent)


  proc implFwd(body: NimNode, res: var seq[NimNode]) =
    for x in body:
      # - ctor: body
      if x.kind == nnkPrefix and x.len == 3 and x[0] == ident("-"):
        implFwd(x[2] #[ body ]#, res)


      # - ctor as path.to.alias: body
      elif (
        x.kind == nnkInfix and x.len in 3..4 and x[0] == ident("as") and
        x[1].kind == nnkPrefix and x[1][0] == ident("-") and
        x[2].kind notin {nnkIdent, nnkAccQuoted, nnkSym}
      ):
        res.add nnkAsgn.newTree(
          x[2] #[ alias ]#,
          x[1][1] #[ ctor ]#
        )

        if x.len == 4:
          implFwd(x[3] #[ body ]#, res)


      # - ctor as alias: body
      elif (
        x.kind == nnkInfix and x.len in 3..4 and x[0] == ident("as") and
        x[1].kind == nnkPrefix and x[1][0] == ident("-")
      ):
        res.add nnkLetSection.newTree(
          nnkIdentDefs.newTree(
            x[2] #[ alias ]#,
            newEmptyNode(),
            x[1][1] #[ ctor ]#
          )
        )

        if x.len == 4:
          implFwd(x[3] #[ body ]#, res)


  proc impl(parent: NimNode, obj: NimNode, body: NimNode, changableChild: NimNode, changableChildUpdaters: NimNode): NimNode =
    proc checkCtor(ctor: NimNode): bool =
      if ctor == ident "root": warning("adding root to itself causes recursion", ctor)
      if ctor == ident "this": warning("adding this to itself causes recursion", ctor)
      if ctor == ident "parent": warning("adding parent to itself causes recursion", ctor)
      if ctor.kind == nnkCall and ctor[0].kind == nnkIdent and ctor[0].strVal[0].isUpperAscii and ctor.len == 1:
        warning("default nim constructor cannot be overloaded, please prefer using " & ctor[0].strVal & ".new, new " & ctor[0].strVal & " or new" & ctor[0].strVal & "()", ctor)

    proc changableImpl(prop, ctor, body: NimNode): NimNode =
      discard checkCtor ctor

      var updateBody = newStmtList()
      var updaters = newStmtList()

      let this = ident("this")
      let parent = ident("parent")
      let updateProc = genSym(nskProc, "updateProc")

      updateBody.add quote do:
        initIfNeeded(`this`)

      if body != nil:
        updateBody.add impl(ident("parent"), ident("this"), body, prop, updaters)
      
      updateBody.add quote do:
        markCompleted(`this`)
    
      let addingToParent =
        if ctor == nil:  # called by `+ accessor[]: body`, adding to parent is not needed
          newEmptyNode()
        else:
          quote do: `prop` = addChangableChild(`this`, `ctor`)

      result = quote do:
        block changableChildInit:
          `addingToParent`

          proc `updateProc`(`parent`: typeof(`this`), `this`: typeof(`prop`[])) =
            `updateBody`

          connect(
            `prop`.changed, `this`.eventHandler,
            proc() = `updateProc`(`this`, `prop`[])
          )

          emit(`prop`.changed)

          `updaters`

    let makeLayoutCaptureSym = genSym(nskProc, "makeLayoutCapture")
    makeLayoutCaptureSym.copyLineInfo(obj)

    result = buildAst blockStmt:
      genSym(nskLabel, "initializationBlock")
      stmtList:
        procDef:
          makeLayoutCaptureSym
          newEmptyNode(); newEmptyNode()
          nnkFormalParams.newTree(
            newEmptyNode(),
            nnkIdentDefs.newTree(ident "parent", nnkCall.newTree(bindSym"typeof", parent), newEmptyNode()),
            nnkIdentDefs.newTree(ident "this", nnkCall.newTree(bindSym"typeof", obj), newEmptyNode()),
          )
          newEmptyNode(); newEmptyNode()
          
          stmtList:
            nnkCall.newTree(ident"initIfNeeded", ident "this")

            for x in body:
              # - ctor: body
              if (
                x.kind == nnkPrefix and x.len in 2..3 and x[0] == ident("-")
              ):
                let ctor = x[1]
                discard checkCtor ctor
                let alias = genSym(nskLet, "unnamedObj")
                letSection:
                  identDefs(alias, empty(), ctor)
                call(ident"addChild", ident "this", alias)
                
                if x.len == 2:
                  call(ident"initIfNeeded", alias)
                  call(ident("markCompleted"), alias)
                else:
                  let body = x[2]
                  impl(ident "this", alias, body, changableChild, changableChildUpdaters)
                  call(ident("markCompleted"), alias)


              # - ctor as alias: body
              elif (
                x.kind == nnkInfix and x.len in 3..4 and x[0] == ident("as") and
                x[1].kind == nnkPrefix and x[1][0] == ident("-")
              ):
                let ctor = x[1][1]
                let alias = x[2]
                discard checkCtor ctor
                call(ident"addChild", ident "this", alias)
                
                if x.len == 3:
                  call(ident"initIfNeeded", alias)
                  call(ident("markCompleted"), alias)
                else:
                  let body = x[3]
                  impl(ident "this", alias, body, changableChild, changableChildUpdaters)
                  call(ident("markCompleted"), alias)
              

              # to --- ctor: body
              elif (
                x.kind == nnkInfix and x.len in 3..4 and x[0] == ident("---")
              ):
                let to = x[1]
                let ctor = x[2]
                discard checkCtor ctor
                changableImpl(to, ctor, (if x.len == 3: nil else: x[3]))
              

              # --- ctor: body
              elif (
                x.kind == nnkPrefix and x.len == 3 and x[0] == ident("---")
              ):
                let ctor = x[1]
                let anonimusChangableChild = nskVar.genSym("anonimusChangableChild")
                discard checkCtor ctor
                quote do:
                  var `anonimusChangableChild`: ChangableChild[typeof(`ctor`)]
                changableImpl(anonimusChangableChild, ctor, x[2])

              
              # <--- ctor: body
              elif (
                x.kind == nnkPrefix and x.len == 3 and x[0] == ident("<---")
              ):
                let ctor = x[1]
                let body = x[2]
                if changableChild.kind == nnkEmpty:
                  (error("Must be inside changable child", x))

                changableChildUpdaters.add:
                  buildAst:
                    call bindSym("bindingChangableChild"):
                      ident "this"
                      bracketExpr:
                        changableChild
                      body
                      ctor

              
              # + accessor[]: body
              elif (
                x.kind == nnkPrefix and x.len in 2..3 and x[0] == ident("+") and x[1].kind == nnkBracketExpr and x[1].len == 1
              ):
                # connect to accessor.changed, then immediatly and each time accessor changed,
                # operate on object, accessed by `accessor`, with this/parent logic, without actually adding it to parent
                let accessor = x[1][0]
                changableImpl(accessor, nil, (if x.len == 2: nil else: x[2]))


              # + accessor: body
              elif (
                x.kind == nnkPrefix and x.len in 2..3 and x[0] == ident("+")
              ):
                # operate on object, accessed by `accessor`, with this/parent logic, without actually adding it to parent
                let accessor = x[1]
                let alias = genSym(nskLet)
                letSection:
                  identDefs(alias, empty(), accessor)
                
                if x.len == 2:
                  call(ident"initIfNeeded", alias)
                else:
                  let body = x[2]
                  impl(ident "this", alias, body, changableChild, changableChildUpdaters)
              

              # binding: body
              elif x.kind in {nnkCommand, nnkCall} and x.len == 2 and x[0] == ident("binding"):
                let body = x[1]
                nnkCall.newTree(bindSym("binding"), ident("this"), body)


              # prop := val
              # prop = binding: val
              elif (
                var name, val, eh: NimNode
                
                # prop := val
                if x.kind == nnkInfix and x.len == 3 and x[0] == ident(":="):
                  name = x[1]
                  val = x[2]
                  eh = ident("this")
                  true
                
                # prop = binding: val
                elif x.kind == nnkAsgn and x[1].kind in {nnkCommand, nnkCall} and x[1].len == 2 and x[1][0] == ident("binding"):
                  name = x[0]
                  val = x[1][1]
                  eh = ident("this")
                  true
                
                # prop = binding(eh): val
                elif x.kind == nnkAsgn and x[1].kind in {nnkCommand, nnkCall} and x[1].len == 3 and x[1][0] == ident("binding"):
                  name = x[0]
                  val = x[1][2]
                  eh = x[1][1]
                  true
                
                else: false
              ):
                if name.kind in {nnkIdent, nnkSym, nnkAccQuoted}:  # name should be resolved to this.name[]
                  call bindSym("bindingValue"):
                    eh
                    bracketExpr:
                      dotExpr(ident("this"), name)
                    val
                else:  # name should be as is
                  call bindSym("bindingValue"):
                    eh
                    name
                    val
              

              # name = val
              elif (
                x.kind == nnkAsgn and x[0].kind == nnkIdent
              ):
                # todo: add setters (`prop=`) for each property and unify syntax for procs, field and properties on this
                let name = x[0]
                let val = x[1]

                let asgnProperty = nnkAsgn.newTree(
                  nnkBracketExpr.newTree(
                    nnkDotExpr.newTree(ident("this"), name),
                  ),
                  val
                )

                var asgnField = nnkAsgn.newTree(
                  nnkDotExpr.newTree(ident("this"), name),
                  val
                )

                var asgnSimple = nnkAsgn.newTree(
                  name,
                  val
                )

                if name.kind in {nnkIdent, nnkSym, nnkAccQuoted}:
                  if $name notin ["drawLayer", "top", "left", "bottom", "right", "centerX", "centerY"]:
                    asgnField = nnkStmtList.newTree(
                      asgnField,
                      nnkPragma.newTree(
                        nnkExprColonExpr.newTree(
                          ident("warning"),
                          newLit("ambiguous assignment, use `this.field_name = ...` instead. The `property_name = ...` syntax is for properties on this")
                        )
                      )
                    )

                  asgnSimple = nnkStmtList.newTree(
                    asgnSimple,
                    nnkPragma.newTree(
                      nnkExprColonExpr.newTree(
                        ident("warning"),
                        newLit("ambiguous assignment, use (var_name) = ... instead. The `property_name = ...` syntax is for properties on this")
                      )
                    )
                  )

                let selector = nnkWhenStmt.newTree(
                  nnkElifBranch.newTree(
                    nnkCall.newTree(bindSym("compiles"), asgnProperty.copy),
                    asgnProperty
                  ),
                  nnkElifBranch.newTree(
                    nnkCall.newTree(bindSym("compiles"), asgnField.copy),
                    asgnField
                  ),
                  nnkElifBranch.newTree(
                    nnkCall.newTree(bindSym("compiles"), asgnSimple.copy),
                    asgnSimple
                  ),
                  nnkElse.newTree(
                    asgnProperty
                  )
                )
                
                (asgnProperty.copyLineInfo(x))
                (asgnProperty[0].copyLineInfo(x))
                (asgnField.copyLineInfo(x))
                (asgnSimple.copyLineInfo(x))

                (selector[0][0].copyLineInfo(selector[0][0][0]))
                (selector[1][0].copyLineInfo(selector[1][0][0]))
                (selector[2][0].copyLineInfo(selector[2][0][0]))

                selector
            

              # for x in y: body
              elif x.kind == nnkForStmt:
                forStmt:
                  for y in x[0..^2]: y
                  call:
                    par:
                      lambda:
                        empty()
                        empty(); empty()
                        formalParams:
                          empty()
                          for param in x[0..^3]:
                            identDefs:
                              param
                              call:
                                ident("typeof")
                                param
                              empty()
                        empty(); empty()
                        stmtList:
                          var fwd: seq[NimNode]
                          (implFwd(x[^1], fwd))
                          for x in fwd: x
                          impl(ident "parent", ident "this", x[^1], changableChild, changableChildUpdaters)
                    
                    for param in x[0..^3]:
                      param


              # if x: body
              # when x: body
              elif x.kind in {nnkIfStmt, nnkWhenStmt}:
                var branches: seq[NimNode]
                for branch in x.children:
                  branch[^1] = buildAst:
                    stmtList:
                      var fwd: seq[NimNode]
                      (implFwd(branch[^1], fwd))
                      for x in fwd: x
                      impl(ident "parent", ident "this", branch[^1], changableChild, changableChildUpdaters)
                  branches.add branch
                
                x.kind.newTree(branches)


              # case x:
              # of y: body
              elif x.kind == nnkCaseStmt:
                caseStmt:
                  x[0]

                  for x in x[1..^1]:
                    x[^1] = buildAst:
                      stmtList:
                        var fwd: seq[NimNode]
                        (implFwd(x[^1], fwd))
                        for x in fwd: x
                        impl(ident "parent", ident "this", x[^1], changableChild, changableChildUpdaters)
                    x
              

              # on property[] == value: body
              elif x.kind == nnkCommand and x.len == 3 and x[0] == ident("on") and x[1].kind == nnkInfix and x[1][1].kind == nnkBracketExpr:
                let cond = x[1]
                let property = x[1][1]
                let body = x[2]

                let connectCall = nnkCall.newTree(
                  bindSym("connectTo"),
                  nnkDotExpr.newTree(property[0], ident("changed")),
                  ident "this",
                  nnkIfStmt.newTree(
                    nnkElifBranch.newTree(
                      cond,
                      body,
                    )
                  )
                )
                (connectCall[0].copyLineInfo(x[0]))
                
                connectCall


              # on event: body
              elif x.kind == nnkCommand and x.len == 3 and x[0] == ident("on"):
                let event = x[1]
                let body = x[2]

                let connectCall = nnkCall.newTree(
                  bindSym("connectTo"),
                  event,
                  ident "this",
                  body
                )
                (connectCall[0].copyLineInfo(x[0]))
                
                connectCall
              

              else:
                x

        call:
          makeLayoutCaptureSym
          parent
          obj


  result = buildAst blockStmt:
    genSym(nskLabel, "makeLayoutBlock")
    stmtList:
      letSection:
        identDefs(pragmaExpr(ident "root", pragma ident "used"), empty(), obj)
      var fwd: seq[NimNode]
      (implFwd(body, fwd))
      for x in fwd: x
      
      impl(
        nnkDotExpr.newTree(ident "root", ident "parent"),
        ident "root",
        if body.kind == nnkStmtList: body else: newStmtList(body),
        newEmptyNode(),
        newStmtList()
      )


template makeLayoutInside*[T](res: var T, container: Uiobj, init: T, body: untyped) =
  res = init
  let obj = res
  addChild(container, obj)
  initIfNeeded(obj)
  makeLayout(obj, body)
  markCompleted(obj)


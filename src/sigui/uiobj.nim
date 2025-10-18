import std/[times, macros, strutils, importutils, macrocache]
import pkg/[vmath, bumpy, siwin, chroma]
import pkg/fusion/[astdsl]
import ./[events {.all.}, properties]
import ./render/[gl, contexts]

when defined(sigui_debug_useLogging):
  import logging


type
  Col* = chroma.Color

  AnchorOffsetFrom = enum
    start
    center
    `end`

  Anchor* = object
    obj {.cursor.}: Uiobj
      # if nil, anchor is disabled
    offsetFrom: AnchorOffsetFrom
    offset: float32
    eventHandler: EventHandler
  
  Anchors = object
    left, right, top, bottom, centerX, centerY: Anchor
  
  Visibility* = enum
    visible
    hidden
    hiddenTree
    collapsed  #? is it needed?
  
  
  Signal* = ref object of RootObj
    sender* {.cursor.}: Uiobj
  

  DrawLayering = object
    before: seq[UiobjCursor]
    beforeChilds: seq[UiobjCursor]
    after: seq[UiobjCursor]
  
  LayerOrder = enum
    before
    beforeChilds
    after

  Layer = object
    obj {.cursor.}: Uiobj
    order: LayerOrder

  DrawLayer = object
    obj {.cursor.}: Uiobj
    order: LayerOrder
    this {.cursor.}: Uiobj


  Uiobj* = ref UiobjObjType
  UiobjObjType = object of RootObj
    eventHandler*: EventHandler
    
    parent* {.cursor.}: Uiobj
      ## parent of this object, that must have this object as child
      ## note: object can have no parent
    childs*: seq[owned(Uiobj)]
      ## childs that should be deleted when this object is deleted
    
    x*, y*, w*, h*: Property[float32]
    visibility*: Property[Visibility]
    globalTransform*: Property[bool]
    
    globalX*, globalY*: Property[float32]
    
    onSignal*: Event[Signal]
    
    newChildsObject*: Uiobj

    initialized*: bool
    attachedToWindow*: bool
    # todo: add a pointer to UiRoot
    
    anchors: Anchors

    drawLayering: DrawLayering
    m_drawLayer: DrawLayer


  UiobjCursor = object
    obj {.cursor.}: Uiobj


  UiRoot* = ref object of Uiobj
    onTick*: Event[TickEvent]


  UiWindow* = ref object of UiRoot
    siwinWindow*: Window
    ctx*: DrawContext
    clearColor*: Col


  ChangableChild*[T] = object
    parent {.cursor.}: Uiobj
    childIndex: int
    changed*: Event[void]


  #--- Signals ---

  SubtreeSignal* = ref object of Signal
    ## signal sends to all childs recursively (by default)

  SubtreeReverseSignal* = ref object of SubtreeSignal
    ## signal sends to all childs recursively in reverse order (by default)
  
  AttachedToWindow* = ref object of SubtreeSignal
    window*: UiWindow

  ParentChanged* = ref object of SubtreeSignal
    newParentInTree*: Uiobj
  
  WindowEvent* = ref object of SubtreeReverseSignal
    event*: ref AnyWindowEvent
    handled*: bool
    fake*: bool
  
  GetActiveCursor* = ref object of SubtreeReverseSignal
    cursor*: ref Cursor
    handled*: bool
  
  VisibilityChanged* = ref object of SubtreeSignal
    visibility*: Visibility

  BeforeDraw* = ref object of SubtreeSignal
    ## this signal sends after onTick, just before draw
    ## this signal should be used to trigger compute-heavy private data updates that will be displayed on an upcoming frame
    ## call procCall this.super.recieve(signal) before handling it (unless you know what you're doing)

  
  UptreeSignal* = ref object of Signal
    ## signal sends to all parents recursively (by default)
  
  ChildAdded* = ref object of UptreeSignal
    child*: Uiobj
  
  # todo: ChildRemoved

  
  BindingKind = enum
    bindProperty
    bindValue
    bindProc
  
  HasEventHandler* = concept x
    x.eventHandler is EventHandler



# ------------- Utils ------------- #

proc containsShift*(keyboardPressed: set[Key]): bool =
  Key.lshift in keyboardPressed or Key.rshift in keyboardPressed

proc containsControl*(keyboardPressed: set[Key]): bool =
  Key.lcontrol in keyboardPressed or Key.rcontrol in keyboardPressed

proc containsAlt*(keyboardPressed: set[Key]): bool =
  Key.lalt in keyboardPressed or Key.ralt in keyboardPressed

proc containsSystem*(keyboardPressed: set[Key]): bool =
  Key.lsystem in keyboardPressed or Key.rsystem in keyboardPressed


proc toColor*(s: string): colortypes.Color =
  case s.len
  of 3:
    result = colortypes.Color(
      r: ($s[0]).parseHexInt.float32 / 15.0,
      g: ($s[1]).parseHexInt.float32 / 15.0,
      b: ($s[2]).parseHexInt.float32 / 15.0,
      a: 1,
    )
  of 4:
    result = colortypes.Color(
      r: ($s[0]).parseHexInt.float32 / 15.0,
      g: ($s[1]).parseHexInt.float32 / 15.0,
      b: ($s[2]).parseHexInt.float32 / 15.0,
      a: ($s[3]).parseHexInt.float32 / 15.0,
    )
  of 6:
    result = colortypes.Color(
      r: (s[0..1].parseHexInt.float32) / 255.0,
      g: (s[2..3].parseHexInt.float32) / 255.0,
      b: (s[4..5].parseHexInt.float32) / 255.0,
      a: 1,
    )
  of 8:
    result = colortypes.Color(
      r: (s[0..1].parseHexInt.float32) / 255.0,
      g: (s[2..3].parseHexInt.float32) / 255.0,
      b: (s[4..5].parseHexInt.float32) / 255.0,
      a: (s[6..7].parseHexInt.float32) / 255.0,
    )
  else:
    raise ValueError.newException("invalid color: " & s)


converter litToColor*(s: string{lit}): colortypes.Color =
  s.toColor


macro color*(s: static string): colortypes.Color =
  s.toColor.newLit



#* ------------- Uiobj ------------- *#

proc xy*(obj: Uiobj): Vec2 =
  vec2(obj.x[], obj.y[])

proc `xy=`*(obj: Uiobj, v: Vec2) =
  obj.x[] = v.x
  obj.y[] = v.y


proc wh*(obj: Uiobj): Vec2 =
  vec2(obj.w[], obj.h[])

proc `wh=`*(obj: Uiobj, v: Vec2) =
  obj.w[] = v.x
  obj.h[] = v.y


proc globalXy*(obj: Uiobj): Vec2 =
  vec2(obj.globalX[], obj.globalY[])

proc `globalXy=`*(obj: Uiobj, v: Vec2) =
  obj.globalX[] = v.x
  obj.globalY[] = v.y


method draw*(obj: Uiobj, ctx: DrawContext) {.base.}
  ## draw current state to a window or framebuffer
  ## ! do not update state of ui objects on draw() !  handle BeforeDraw signal instead

proc drawBefore*(obj: Uiobj, ctx: DrawContext) =
  for x in obj.drawLayering.before:
    draw(x.obj, ctx)

proc drawChilds*(obj: Uiobj, ctx: DrawContext) =
  if obj.visibility notin {hiddenTree, collapsed}:
    for x in obj.childs:
      if x.m_drawLayer.obj == nil:
        draw(x, ctx)

proc drawBeforeChilds*(obj: Uiobj, ctx: DrawContext) =
  for x in obj.drawLayering.beforeChilds:
    draw(x.obj, ctx)

proc drawAfterLayer*(obj: Uiobj, ctx: DrawContext) =
  for x in obj.drawLayering.after:
    draw(x.obj, ctx)

proc drawAfter*(obj: Uiobj, ctx: DrawContext) =
  obj.drawBeforeChilds(ctx)
  obj.drawChilds(ctx)
  obj.drawAfterLayer(ctx)

method draw*(obj: Uiobj, ctx: DrawContext) {.base.} =
  obj.drawBefore(ctx)
  obj.drawAfter(ctx)


proc parentUiWindow*(obj: Uiobj): UiWindow =
  var obj {.cursor.} = obj
  while true:
    if obj == nil: return nil
    if obj of UiWindow: return obj.UiWindow
    obj = obj.parent

proc parentWindow*(obj: Uiobj): Window =
  let uiWin = obj.parentUiWindow
  if uiWin != nil: uiWin.siwinWindow
  else: nil

proc lastParent*(obj: Uiobj): Uiobj =
  result = obj
  while true:
    if result.parent == nil: return
    result = result.parent


when defined(sigui_debug_redrawInitiatedBy):
  import std/importutils
  privateAccess Window
  proc sigui_debug_redrawInitiatedBy_formatFunction(obj: Uiobj, alreadyRedrawing, hasWindow: bool): string
  
  # proc sigui_debug_redrawInitiatedBy_formatFunction(obj: Uiobj, alreadyRedrawing, hasWindow: bool): string =
  #   proc(obj: Uiobj, alreadyRedrawing, hasWindow: bool): string =
  #     if alreadyRedrawing:
  #       "redraw initiated (already redrawing)"
  #     else:
  #       "redraw initiated"

proc redraw*(obj: Uiobj, ifVisible = true) =
  if ifVisible and obj.visibility[] != visible: return
  
  var win: Window

  var objp {.cursor.} = obj
  while true:
    if objp == nil: break
    if ifVisible and objp != obj and objp.visibility[] notin {visible, hidden}: return
    if objp of UiWindow:
      win = objp.UiWindow.siwinWindow
      break
    objp = objp.parent

  when defined(sigui_debug_redrawInitiatedBy):
    let alreadyRedrawing =
      if win != nil: win.redrawRequested
      else: false

    when defined(sigui_debug_useLogging):
      info(sigui_debug_redrawInitiatedBy_formatFunction(obj, alreadyRedrawing, win != nil))
    else:
      echo sigui_debug_redrawInitiatedBy_formatFunction(obj, alreadyRedrawing, win != nil)
  
  if win != nil: redraw win


proc posToLocal*(pos: Vec2, obj: Uiobj): Vec2 =
  result = pos
  var obj {.cursor.} = obj
  while true:
    if obj == nil: return
    result.x -= obj.x[]
    result.y -= obj.y[]
    if obj.globalTransform[]: return
    obj = obj.parent


proc posToGlobal*(pos: Vec2, obj: Uiobj): Vec2 =
  result = pos
  var obj {.cursor.} = obj
  while true:
    if obj == nil: return
    result.x += obj.x[]
    result.y += obj.y[]
    if obj.globalTransform[]: return
    obj = obj.parent


proc posToObject*(fromObj, toObj: Uiobj, pos: Vec2): Vec2 =
  pos + fromObj.globalXy - toObj.globalXy

proc posToObject*(pos: Vec2, fromObj, toObj: Uiobj): Vec2 {.inline.} =
  posToObject(fromObj, toObj, pos)


proc `$`*(this: Uiobj): string



#----- Events connection -----

template connectTo*[T](s: var Event[T], obj: HasEventHandler, body: untyped) =
  connect s, obj.eventHandler, proc(e {.inject.}: T) =
    body

template connectTo*(s: var Event[void], obj: HasEventHandler, body: untyped) =
  connect s, obj.eventHandler, proc() =
    body

template connectTo*[T](s: var Event[T], obj: HasEventHandler, argname: untyped, body: untyped) =
  connect s, obj.eventHandler, proc(argname {.inject.}: T) =
    body

template connectTo*(s: var Event[void], obj: HasEventHandler, argname: untyped, body: untyped) =
  connect s, obj.eventHandler, proc() =
    body



#----- Reposition -----

proc pos*(anchor: Anchor, isY: bool, toObject: Uiobj): float32 =
  assert anchor.obj != nil
  let p = case anchor.offsetFrom
  of start:
    if isY:
      if anchor.obj.visibility[] == collapsed and anchor.obj.anchors.top.obj == nil and anchor.obj.anchors.bottom.obj != nil:
        anchor.obj.h[] + anchor.offset
      else:
        anchor.offset
    else:
      if anchor.obj.visibility[] == collapsed and anchor.obj.anchors.left.obj == nil and anchor.obj.anchors.right.obj != nil:
        anchor.obj.w[] + anchor.offset
      else:
        anchor.offset

  of `end`:
    if isY:
      if anchor.obj.visibility[] == collapsed and anchor.obj.anchors.top.obj != nil and anchor.obj.anchors.bottom.obj == nil:
        anchor.offset
      else:
        anchor.obj.h[] + anchor.offset
    else:
      if anchor.obj.visibility[] == collapsed and anchor.obj.anchors.left.obj != nil and anchor.obj.anchors.right.obj == nil:
        anchor.offset
      else:
        anchor.obj.w[] + anchor.offset

  of center:
    if isY:
      if anchor.obj.visibility[] == collapsed:
        if anchor.obj.anchors.top.obj == nil and anchor.obj.anchors.bottom.obj != nil:
          anchor.obj.h[] + anchor.offset
        else:
          anchor.offset
      else:
        anchor.obj.h[] / 2 + anchor.offset
    else:
      if anchor.obj.visibility[] == collapsed:
        if anchor.obj.anchors.left.obj == nil and anchor.obj.anchors.right.obj != nil:
          anchor.obj.w[] + anchor.offset
        else:
          anchor.offset
      else:
        anchor.obj.w[] / 2 + anchor.offset

  if isY: p + anchor.obj.globalY[] - (if toObject != nil: toObject.globalY[] else: 0)
  else: p + anchor.obj.globalX[] - (if toObject != nil: toObject.globalX[] else: 0)


proc applyAnchors*(obj: Uiobj) =
  # x and w
  if obj.anchors.left.obj != nil:
    obj.x[] = obj.anchors.left.pos(isY=false, obj.parent)
  
  if obj.anchors.right.obj != nil:
    if obj.anchors.left.obj != nil:
      obj.w[] = obj.anchors.right.pos(isY=false, obj.parent) - obj.x[]
    else:
      obj.x[] = obj.anchors.right.pos(isY=false, obj.parent) - obj.w[]
  
  if obj.anchors.centerX.obj != nil:
    obj.x[] = obj.anchors.centerX.pos(isY=false, obj.parent) - obj.w[] / 2

  # y and h
  if obj.anchors.top.obj != nil:
    obj.y[] = obj.anchors.top.pos(isY=true, obj.parent)
  
  if obj.anchors.bottom.obj != nil:
    if obj.anchors.top.obj != nil:
      obj.h[] = obj.anchors.bottom.pos(isY=true, obj.parent) - obj.y[]
    else:
      obj.y[] = obj.anchors.bottom.pos(isY=true, obj.parent) - obj.h[]
  
  if obj.anchors.centerY.obj != nil:
    obj.y[] = obj.anchors.centerY.pos(isY=true, obj.parent) - obj.h[] / 2


proc left*(obj: Uiobj, margin: float32 = 0): Anchor =
  Anchor(obj: obj, offsetFrom: start, offset: margin)
proc right*(obj: Uiobj, margin: float32 = 0): Anchor =
  Anchor(obj: obj, offsetFrom: `end`, offset: margin)
proc top*(obj: Uiobj, margin: float32 = 0): Anchor =
  Anchor(obj: obj, offsetFrom: start, offset: margin)
proc bottom*(obj: Uiobj, margin: float32 = 0): Anchor =
  Anchor(obj: obj, offsetFrom: `end`, offset: margin)
proc center*(obj: Uiobj, margin: float32 = 0): Anchor =
  Anchor(obj: obj, offsetFrom: center, offset: margin)

proc `+`*(a: Anchor, offset: float32): Anchor =
  Anchor(obj: a.obj, offsetFrom: a.offsetFrom, offset: a.offset + offset)

proc `-`*(a: Anchor, offset: float32): Anchor =
  Anchor(obj: a.obj, offsetFrom: a.offsetFrom, offset: a.offset - offset)

proc handleChangedEvent(this: Uiobj, anchor: var Anchor, isY: bool) =
  proc applyThisAnchors(env: pointer) {.nimcall.} =
    # closure creation is expensive, but we can pass (proc(evn: pointer) {.nimcall.}, pointer) as a closure, that is cheaper
    # don't know about possible side effects of it
    cast[Uiobj](env).applyAnchors()
  let env = cast[pointer](this)

  if anchor.obj == nil: return
  if not isY:
    case anchor.offsetFrom:
    of start:
      if anchor.obj != this.parent:
        anchor.obj.globalX.changed.connect(anchor.eventHandler, applyThisAnchors, env, {EventConnectionFlag.internal})
    of `end`:
      if anchor.obj != this.parent:
        anchor.obj.globalX.changed.connect(anchor.eventHandler, applyThisAnchors, env, {EventConnectionFlag.internal})
      anchor.obj.w.changed.connect(anchor.eventHandler, applyThisAnchors, env, {EventConnectionFlag.internal})
    of center:
      if anchor.obj != this.parent:
        anchor.obj.globalX.changed.connect(anchor.eventHandler, applyThisAnchors, env, {EventConnectionFlag.internal})
      anchor.obj.w.changed.connect(anchor.eventHandler, applyThisAnchors, env, {EventConnectionFlag.internal})
  else:
    case anchor.offsetFrom:
    of start:
      if anchor.obj != this.parent:
        anchor.obj.globalY.changed.connect(anchor.eventHandler, applyThisAnchors, env, {EventConnectionFlag.internal})
    of `end`:
      if anchor.obj != this.parent:
        anchor.obj.globalY.changed.connect(anchor.eventHandler, applyThisAnchors, env, {EventConnectionFlag.internal})
      anchor.obj.h.changed.connect(anchor.eventHandler, applyThisAnchors, env, {EventConnectionFlag.internal})
    of center:
      if anchor.obj != this.parent:
        anchor.obj.globalY.changed.connect(anchor.eventHandler, applyThisAnchors, env, {EventConnectionFlag.internal})
      anchor.obj.h.changed.connect(anchor.eventHandler, applyThisAnchors, env, {EventConnectionFlag.internal})
  anchor.obj.visibility.changed.connect(anchor.eventHandler, applyThisAnchors, env, {EventConnectionFlag.internal})

template anchorAssign(anchor: untyped, isY: bool): untyped {.dirty.} =
  proc `anchor=`*(obj: Uiobj, v: Anchor) =
    obj.anchors.anchor = v
    handleChangedEvent(obj, obj.anchors.anchor, isY)
    obj.applyAnchors()

anchorAssign left, false
anchorAssign right, false
anchorAssign top, true
anchorAssign bottom, true
anchorAssign centerX, false
anchorAssign centerY, true


proc spreadGlobalXChange(obj: Uiobj, delta: float32) =
  obj.globalX{} += delta
  for x in obj.childs:
    x.spreadGlobalXChange(delta)
  obj.globalX.changed.emit()

proc spreadGlobalYChange(obj: Uiobj, delta: float32) =
  obj.globalY{} += delta
  for x in obj.childs:
    x.spreadGlobalYChange(delta)
  obj.globalY.changed.emit()



#----- receiving signals -----

method recieve*(obj: Uiobj, signal: Signal) {.base.} =
  if signal of AttachedToWindow:
    obj.attachedToWindow = true

  obj.onSignal.emit signal

  if signal of SubtreeReverseSignal:
    for i in countdown(obj.childs.high, 0):
      obj.childs[i].recieve(signal)

  elif signal of SubtreeSignal:
    for x in obj.childs:
      x.recieve(signal)
  
  if signal of UptreeSignal:
    if obj.parent != nil:
      obj.parent.recieve(signal)



#----- reflection: trigger redraw automatically when property changes -----


method shouldAutoredraw*(obj: Uiobj): bool {.base.} = false


proc autoredraw*(obj: Uiobj) =
  if shouldAutoredraw(obj): redraw(obj)


proc firstHandHandler_redrawOnly*(env: pointer) {.nimcall.} =
  autoredraw(cast[Uiobj](env))


macro disableAutoRedrawHook*[T: Uiobj](typ: typedesc[T]) =
  CacheSeq("disableAutoRedrawHook").incl typ


proc getTypeName(t: NimNode): string =
  var t = t.getTypeInst
  if t.kind == nnkBracketExpr and t.len == 2 and ident(t[0].repr) == ident("typeDesc"):
    t = t[1]
  t.repr


macro addFirstHandHandler*[T: Uiobj](objtyp: typedesc[T], propname: static string, body: untyped) =
  for i in 0 .. body.len-1:
    if body[i].kind in nnkCallKinds and body[i].len == 1 and body[i][0] == ident("superHook"):
      body[i] = newEmptyNode()
      
      var typ = objtyp.getTypeInst[1]
      while true:
        var t = typ.getImpl
        if t.kind == nnkRefTy and t[0].kind == nnkSym: t = t[0].getImpl
        if t.kind == nnkTypeDef and t[2].kind == nnkRefTy: t[2] = t[2][0]
        if t.kind == nnkTypeDef and t[2].kind == nnkObjectTy and t[2][1].kind == nnkOfInherit:
          typ = t[2][1][0]
          if CacheTable("firstHandHandlers").hasKey(typ.getTypeName & "_" & propname):
            body[i] = newCall(CacheTable("firstHandHandlers")[typ.getTypeName & "_" & propname], ident("env"))
            break
        else: break
  
  let procName = ident("firstHandHandler" & "_" & objtyp.getTypeName & "_" & propname)

  result = quote do:
    proc `procName`*(env {.inject.}: pointer) {.nimcall.} =
      let this {.inject, used.} = cast[`objtyp`](env)
      `body`

  CacheTable("firstHandHandlers")[objtyp.getTypeName & "_" & propname] = procName


macro connectFirstHandHandler*[T: Uiobj](objtyp: typedesc[T], propname: static string, prop: untyped) =
  var bodyProc: NimNode

  block traverseHierarchy:
    var typ = objtyp.getTypeInst[1]
    while true:
      if CacheTable("firstHandHandlers").hasKey(typ.getTypeName & "_" & propname):
        bodyProc = CacheTable("firstHandHandlers")[typ.getTypeName & "_" & propname]
        break
      
      var t = typ.getImpl
      if t.kind == nnkRefTy and t[0].kind == nnkSym: t = t[0].getImpl
      if t.kind == nnkTypeDef and t[2].kind == nnkRefTy: t[2] = t[2][0]
      if t.kind == nnkTypeDef and t[2].kind == nnkObjectTy and t[2][1].kind == nnkOfInherit:
        typ = t[2][1][0]
      else: break
  
  var redraw = true
  for x in CacheSeq("disableAutoRedrawHook"):
    if objtyp.getTypeName == x.getTypeName: redraw = false

  if redraw:
    if bodyProc == nil:
      bodyProc = bindSym("firstHandHandler_redrawOnly")
  
  if bodyProc != nil:
    result = newStmtList(
      nnkAsgn.newTree(
        nnkDotExpr.newTree(prop, ident("firstHandHandlerEnv")),
        nnkCast.newTree(ident("pointer"), ident("this")),
      ),
      nnkAsgn.newTree(
        nnkDotExpr.newTree(prop, ident("firstHandHandler")),
        bodyProc,
      ),
    )
  
  else:
    result = newEmptyNode()


disableAutoRedrawHook Uiobj

addFirstHandHandler Uiobj, "globalX": discard  # disable auto-redraw
addFirstHandHandler Uiobj, "globalY": discard  # disable auto-redraw

addFirstHandHandler Uiobj, "visibility":
  this.recieve(VisibilityChanged(sender: this, visibility: this.visibility[]))
  redraw(this, ifVisible = false)

addFirstHandHandler Uiobj, "w": this.applyAnchors(); autoredraw(this)
addFirstHandHandler Uiobj, "h": this.applyAnchors(); autoredraw(this)

addFirstHandHandler Uiobj, "x":
  this.spreadGlobalXChange(
    if this.parent == nil or this.globalTransform[]: this.x[] - this.globalX[]
    else: this.x[] - (this.globalX[] - this.parent.globalX[])
  )
  autoredraw(this)

addFirstHandHandler Uiobj, "y":
  this.spreadGlobalYChange(
    if this.parent == nil or this.globalTransform[]: this.y[] - this.globalY[]
    else: this.y[] - (this.globalY[] - this.parent.globalY[])
  )
  autoredraw(this)


proc connectFirstHandHandlersStatic[T: Uiobj](this: T) =
  mixin firstHandHandler_hook
  privateAccess Event

  # we are iterating over all fields of an object, some of which can be deprecated
  # we don't care.
  {.push, warning[Deprecated]: off.}

  for name, x in this[].fieldPairs:
    when x is Property or x is CustomProperty:
      connectFirstHandHandler(T, name, x.changed)
  
  {.pop.}


method connectFirstHandHandlers*(this: Uiobj) {.base.} =
  connectFirstHandHandlersStatic(this)



#----- Uiobj initialization -----

method init*(obj: Uiobj) {.base.} =
  obj.globalX[] = obj.x + (if obj.parent == nil: 0'f32 else: obj.parent.globalX[])
  obj.globalY[] = obj.y + (if obj.parent == nil: 0'f32 else: obj.parent.globalY[])

  connectFirstHandHandlers(obj)
  
  if not obj.attachedToWindow:
    let win = obj.parentUiWindow
    if win != nil:
      obj.recieve(AttachedToWindow(window: win))

  obj.initialized = true

proc initIfNeeded*(obj: Uiobj) =
  if obj.initialized: return
  init(obj)
  if obj.parent != nil:
    obj.recieve(ParentChanged(newParentInTree: obj.parent))
    obj.parent.recieve(ChildAdded(child: obj))



#----- Anchors -----

proc fillHorizontal*(this: Uiobj, obj: Uiobj, margin: float32 = 0) =
  this.left = obj.left + margin
  this.right = obj.right - margin

proc fillVertical*(this: Uiobj, obj: Uiobj, margin: float32 = 0) =
  this.top = obj.top + margin
  this.bottom = obj.bottom - margin

proc centerIn*(this: Uiobj, obj: Uiobj, offset: Vec2 = vec2(), xCenterAt: AnchorOffsetFrom = center, yCenterAt: AnchorOffsetFrom = center) =
  this.centerX = Anchor(obj: obj, offsetFrom: xCenterAt, offset: offset.x)
  this.centerY = Anchor(obj: obj, offsetFrom: yCenterAt, offset: offset.y)

proc fill*(this: Uiobj, obj: Uiobj, margin: float32 = 0) =
  this.fillHorizontal(obj, margin)
  this.fillVertical(obj, margin)

proc fill*(this: Uiobj, obj: Uiobj, marginX: float32, marginY: float32) =
  this.fillHorizontal(obj, marginX)
  this.fillVertical(obj, marginY)



#----- Layers -----

proc `=destroy`(l: DrawLayer) =
  if l.obj != nil:
    case l.order
    of before: l.obj.drawLayering.before.delete l.obj.drawLayering.before.find(UiobjCursor(obj: l.this))
    of beforeChilds: l.obj.drawLayering.beforeChilds.delete l.obj.drawLayering.beforeChilds.find(UiobjCursor(obj: l.this))
    of after: l.obj.drawLayering.after.delete l.obj.drawLayering.after.find(UiobjCursor(obj: l.this))

proc `=destroy`(l: DrawLayering) =
  for x in l.before:
    x.obj.m_drawLayer.obj = nil
    x.obj.m_drawLayer = DrawLayer()
  for x in l.after:
    x.obj.m_drawLayer.obj = nil
    x.obj.m_drawLayer = DrawLayer()


proc before*(this: Uiobj): Layer =
  Layer(obj: this, order: LayerOrder.before)

proc beforeChilds*(this: Uiobj): Layer =
  Layer(obj: this, order: LayerOrder.beforeChilds)

proc after*(this: Uiobj): Layer =
  Layer(obj: this, order: LayerOrder.after)


proc `drawLayer=`*(this: Uiobj, layer: typeof nil) =
  this.m_drawLayer = DrawLayer()

proc `drawLayer=`*(this: Uiobj, layer: Layer) =
  if this.m_drawLayer.obj != nil: this.drawLayer = nil
  if layer.obj == nil: return
  this.m_drawLayer = DrawLayer(obj: layer.obj, order: layer.order, this: this)

  case layer.order
  of before: layer.obj.drawLayering.before.add UiobjCursor(obj: this)
  of beforeChilds: layer.obj.drawLayering.beforeChilds.add UiobjCursor(obj: this)
  of after: layer.obj.drawLayering.after.add UiobjCursor(obj: this)



#----- Adding childs -----

method deteach*(this: Uiobj) {.base.}

proc deteachStatic[T: Uiobj](this: T) =
  if this == nil: return

  this.drawLayer = nil

  disconnect this.eventHandler

  # for x in this[].fields:
  #   when x is Property or x is CustomProperty:
  #     disconnect x.changed

  for anchor in this.anchors.fields:
    disconnect anchor.eventHandler
    anchor = Anchor()

  for x in this.childs:
    deteach(x)
    x.parent = nil
  
  this.childs = @[]


method deteach*(this: Uiobj) {.base.} =
  ## disconnect all events
  deteachStatic(this)


proc delete*(this: Uiobj) =
  if this == nil: return

  deteach this
  
  if this.parent != nil:
    let i = this.parent.childs.find(this)
    if i != -1:
      this.parent.childs.delete i
    this.parent = nil


method addChild*(parent: Uiobj, child: Uiobj) {.base.} =
  assert child.parent == nil
  if parent.newChildsObject != nil:
    parent.newChildsObject.addChild(child)
  else:
    child.parent = parent
    parent.childs.add child
    if not child.attachedToWindow and parent.attachedToWindow:
      let win = parent.parentUiWindow
      if win != nil:
        child.recieve(AttachedToWindow(window: win))
    if child.initialized:
      child.recieve(ParentChanged(newParentInTree: parent))
      parent.recieve(ChildAdded(child: child))


proc `val=`*[T](p: var ChangableChild[T], v: T) =
  ## note: p.changed will not be emitted if new value is same as previous value
  p.parent.childs[p.childIndex].parent = nil
  deteach p.parent.childs[p.childIndex]
  p.parent.childs[p.childIndex] = v
  v.parent = p.parent

  if v.initialized:
    v.recieve(ParentChanged(newParentInTree: p.parent))
    p.parent.recieve(ChildAdded(child: v))

  emit(p.changed)

proc `[]=`*[T](p: var ChangableChild[T], v: T) {.inline.} = p.val = v

proc val*[T](p: ChangableChild[T]): T {.inline.} =
  result = p.parent.childs[p.childIndex].T

proc val*(p: ChangableChild[Uiobj]): Uiobj {.inline.} =
  # we need this overload to avoid ConvFromXtoItselfNotNeeded warning
  result = p.parent.childs[p.childIndex]

proc `[]`*[T](p: ChangableChild[T]): T {.inline.} = p.val

proc `{}`*[T](p: var ChangableChild[T]): T {.inline.} = p.val
proc `{}=`*[T](p: var ChangableChild[T], v: T) {.inline.} = p.val = v


method addChangableChildUntyped*(parent: Uiobj, child: Uiobj): ChangableChild[Uiobj] {.base.} =
  assert child != nil
  
  if parent.newChildsObject != nil:
    return parent.newChildsObject.addChangableChildUntyped(child)
  else:
    # add to parent.childs seq even if addChild is overrided
    assert child.parent == nil

    child.parent = parent
    parent.childs.add child

    if not child.attachedToWindow and parent.attachedToWindow:
      let win = parent.parentUiWindow
      if win != nil:
        child.recieve(AttachedToWindow(window: win))

    if child.initialized:
      child.recieve(ParentChanged(newParentInTree: parent))
      parent.recieve(ChildAdded(child: child))

    result = ChangableChild[Uiobj](parent: parent, childIndex: parent.childs.high)


proc addChangableChild*[T: Uiobj](parent: Uiobj, child: T): ChangableChild[T] =
  result = cast[ChangableChild[T]](parent.addChangableChildUntyped(child))


macro super*[T: Uiobj](obj: T): auto =
  var t = obj.getTypeImpl
  if t.kind == nnkRefTy and t[0].kind == nnkSym:
    t = t[0].getImpl
  
  if t.kind == nnkTypeDef and t[2].kind == nnkObjectTy and t[2][1].kind == nnkOfInherit:
    return nnkDotExpr.newTree(obj, t[2][1][0])
  else:
    error("unexpected type impl", obj)



#----- Drawing -----

method draw*(win: UiWindow, ctx: DrawContext) =
  glClearColor(win.clearColor.r, win.clearColor.g, win.clearColor.b, win.clearColor.a)
  glClear(GlColorBufferBit or GlDepthBufferBit)
  win.drawBefore(ctx)
  win.drawAfter(ctx)


proc setupEventsHandling*(win: UiWindow) =
  proc toRef[T](e: T): ref AnyWindowEvent =
    result = (ref T)()
    (ref T)(result)[] = e

  win.siwinWindow.eventsHandler = WindowEventsHandler(
    onClose: proc(e: CloseEvent) =
      win.recieve(WindowEvent(sender: win, event: e.toRef))
    ,
    onRender: proc(e: RenderEvent) =
      win.recieve(BeforeDraw(sender: win))
      win.draw(win.ctx)
    ,
    onTick: proc(e: TickEvent) =
      win.onTick.emit(e)
    ,
    onResize: proc(e: ResizeEvent) =
      win.wh = e.size.vec2
      glViewport 0, 0, e.size.x.GLsizei, e.size.y.GLsizei
      win.ctx.updateDrawingAreaSize(e.size)

      win.recieve(WindowEvent(sender: win, event: e.toRef))
    ,
    onWindowMove: proc(e: WindowMoveEvent) =
      win.recieve(WindowEvent(sender: win, event: e.toRef))
    ,

    onStateBoolChanged: proc(e: StateBoolChangedEvent) =
      redraw win.siwinWindow
      win.recieve(WindowEvent(sender: win, event: e.toRef))
    ,

    onMouseMove: proc(e: MouseMoveEvent) =
      win.recieve(WindowEvent(sender: win, event: e.toRef))
    ,
    onMouseButton: proc(e: MouseButtonEvent) =
      win.recieve(WindowEvent(sender: win, event: e.toRef))
    ,
    onScroll: proc(e: ScrollEvent) =
      win.recieve(WindowEvent(sender: win, event: e.toRef))
    ,
    onClick: proc(e: ClickEvent) =
      win.recieve(WindowEvent(sender: win, event: e.toRef))
    ,

    onKey: proc(e: KeyEvent) =
      win.recieve(WindowEvent(sender: win, event: e.toRef))
    ,
    onTextInput: proc(e: TextInputEvent) =
      win.recieve(WindowEvent(sender: win, event: e.toRef))
    ,
  )

proc newUiWindow*(siwinWindow: Window): UiWindow =
  result = UiWindow(siwinWindow: siwinWindow)
  loadExtensions()
  result.setupEventsHandling
  result.ctx = newDrawContext()

template newUiRoot*(siwinWindow: Window): UiWindow =
  newUiWindow(siwinWindow)


method addChild*(this: UiWindow, child: Uiobj) =
  procCall this.super.addChild(child)
  child.recieve(AttachedToWindow(window: this))
        


proc newUiobj*(): Uiobj = new result
proc newUiWindow*(): UiWindow = new result



#----- Macros -----

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
  
  let updateProc = genSym(nskProc)
  let objCursor = genSym(nskLet)
  let thisInProc = genSym(nskParam)
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
        ident "connectTo"
        dotExpr(exp, ident "changed")
        objCursor
        call updateProc:
          objCursor
      alreadyBinded.add body
      impl(stmts, exp)
    
    else:
      for x in body:
        impl(stmts, x)
  
  result = buildAst(blockStmt):
    ident "bindingBlock"
    stmtList:
      letSection:
        identDefs(objCursor, empty(), obj)
      
      procDef updateProc:
        empty(); empty()
        formalParams:
          empty()
          identDefs(thisInProc, obj.getType, empty())
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
      
      var stmts: seq[NimNode]
      (impl(stmts, body))
      for x in stmts: x

      if init:
        call updateProc, objCursor


# todo: instead of this nonesence, make a single `binding:` block that can be attached to specific event handler and executes statements istead of expression
when false:
  - UiRect.new:
    binding: w = this.h[]
    var eh = EventHandler()
    eh.binding: radius = this.w[]


macro binding*(obj: EventHandler, target: untyped, body: typed, init: static bool = true): untyped {.deprecated: "reserved for future use. Use bindingProperty instead".} =
  bindingImpl(obj, target, body, init, bindProperty)

macro bindingProperty*(obj: EventHandler, target: untyped, body: typed, init: static bool = true): untyped =
  bindingImpl(obj, target, body, init, bindProperty)

macro bindingValue*(obj: EventHandler, target: untyped, body: typed, init: static bool = true): untyped =
  bindingImpl(obj, target, body, init, bindValue)

macro bindingProc*(obj: EventHandler, target: untyped, body: typed, init: static bool = true): untyped =
  bindingImpl(obj, target, body, init, bindProc)


macro binding*[T: HasEventHandler](obj: T, target: untyped, body: typed, init: static bool = true): untyped {.deprecated: "reserved for future use. Use bindingProperty instead".} =
  bindingImpl(obj, target, body, init, bindProperty)

macro bindingProperty*[T: HasEventHandler](obj: T, target: untyped, body: typed, init: static bool = true): untyped =
  bindingImpl(obj, target, body, init, bindProperty)

macro bindingValue*[T: HasEventHandler](obj: T, target: untyped, body: typed, init: static bool = true): untyped =
  bindingImpl(obj, target, body, init, bindValue)

macro bindingProc*[T: HasEventHandler](obj: T, target: untyped, body: typed, init: static bool = true): untyped =
  bindingImpl(obj, target, body, init, bindProc)



macro bindingChangableChild[T](obj: T, target: untyped, body: untyped, ctor: typed): untyped =
  bindingImpl(obj, target, body, true, bindValue, ctor)



macro makeLayout*(obj: Uiobj, body: untyped) =
  ## tip: use a.makeLauyout(-soMeFuN()) instead of (let b = soMeFuN(); a.addChild(b); init b)
  runnableExamples:
    import sigui/uibase
    
    let a = UiRect.new
    let b = UiRect.new
    let c = UiRect.new
    var ooo: ChangableChild[UiRect]
    a.makeLayout:
      - RectShadow(
        radius: 7.5'f32.property,  # pre-initialization of properties (not recommended)
        blurRadius: 10'f32.property,
        color: color(0, 0, 0, 0.3).property
      ) as shadowEffect

      - newUiRect():
        this.fill(parent)
        echo shadowEffect.radius
        doassert parent.Uiobj == this.parent

        - ClipRect.new:
          this.radius[] = 7.5
          this.fill(parent, 10)
          doassert root.Uiobj == this.parent.parent

          ooo --- UiRect.new:  # add changable child
            this.fill(parent)

          - b
          - UiRect.new

      - c:
        this.fill(parent)


  proc implFwd(body: NimNode, res: var seq[NimNode]) =
    for x in body:
      # - ctor: body
      if x.kind == nnkPrefix and x.len == 3 and x[0] == ident("-"):
        implFwd(x[2] #[ body ]#, res)

      # - ctor as alias: body
      elif (
        x.kind == nnkInfix and x.len in 3..4 and x[0] == ident("as") and
        x[1].kind == nnkPrefix and x[1][0] == ident("-")
      ):
        res.add nnkIdentDefs.newTree(
          x[2] #[ alias ]#,
          newEmptyNode(),
          x[1][1] #[ ctor ]#
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
      buildAst:
        blockStmt:
          genSym(nskLabel, "changableChildInitializationBlock")
          stmtList:
            discard checkCtor ctor

            let updateProc = genSym(nskProc)
            
            asgn:
              prop
              call(bindSym"addChangableChild", ident "this", ctor)
            
            let updaters = newStmtList()
            
            procDef:
              updateProc
              empty(); empty()
              formalParams:
                empty()
                identDefs(ident"parent", call(bindSym"typeof", ident"this"), empty())
                identDefs(ident"this", call(bindSym"typeof", bracketExpr(prop)), empty())
              empty(); empty()
              stmtList:
                if body == nil:
                  call ident"initIfNeeded":
                    ident "this"
                if body != nil: impl(ident"parent", ident"this", body, prop, updaters)

            call updateProc:
              ident "this"
              bracketExpr(prop)
            
            call bindSym"connect":
              dotExpr(prop, ident"changed")
              dotExpr ident "this", ident "eventHandler"
              lambda:
                empty()
                empty(); empty()
                formalParams:
                  empty()
                empty(); empty()
                call updateProc:
                  ident "this"
                  bracketExpr(prop)
            
            for x in updaters: x

    buildAst blockStmt:
      genSym(nskLabel, "initializationBlock")
      call:
        lambda:
          empty(); empty(); empty()
          formalParams:
            empty()
            identDefs(ident "parent", call(bindSym"typeof", parent), empty())
            identDefs(ident "this", call(bindSym"typeof", obj), empty())
          empty(); empty()
          
          stmtList:
            call(ident"initIfNeeded", ident "this")

            for x in body:
              # - ctor: body
              if (
                x.kind == nnkPrefix and x.len in 2..3 and x[0] == ident("-")
              ):
                let ctor = x[1]
                discard checkCtor ctor
                let alias = genSym(nskLet)
                letSection:
                  identDefs(alias, empty(), ctor)
                call(ident"addChild", ident "this", alias)
                
                if x.len == 2:
                  call(ident"initIfNeeded", alias)
                else:
                  let body = x[2]
                  impl(ident "this", alias, body, changableChild, changableChildUpdaters)


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
                else:
                  let body = x[3]
                  impl(ident "this", alias, body, changableChild, changableChildUpdaters)
              

              # to --- ctor: body
              elif (
                x.kind == nnkInfix and x.len in 3..4 and x[0] == ident("---")
              ):
                let to = x[1]
                let ctor = x[2]
                discard checkCtor ctor
                changableImpl(to, ctor, (if x.len == 3: nil else: x[3]))

              
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
              

              # prop := val
              # prop = binding: val
              elif (
                var name, val: NimNode
                
                # prop := val
                if x.kind == nnkInfix and x.len == 3 and x[0] == ident(":="):
                  name = x[1]
                  val = x[2]
                  true
                
                # prop = binding: val
                elif x.kind == nnkAsgn and x[1].kind in {nnkCommand, nnkCall} and x[1][0] == ident("binding"):
                  name = x[0]
                  val = x[1][1]
                  true
                
                else: false
              ):
                if name.kind in {nnkIdent, nnkSym, nnkAccQuoted}:  # name should be resolved to this.name[]
                  call bindSym"bindingValue":
                    ident "this"
                    bracketExpr:
                      dotExpr(ident "this", name)
                    val
                else:  # name should be as is
                  call bindSym"bindingValue":
                    ident "this"
                    name
                    val
              

              # name = val
              elif (
                x.kind == nnkAsgn and x[0].kind == nnkIdent
              ):
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
                          newLit("deprecated, use this.field_name = ... instead")
                        )
                      )
                    )

                  asgnSimple = nnkStmtList.newTree(
                    asgnSimple,
                    nnkPragma.newTree(
                      nnkExprColonExpr.newTree(
                        ident("warning"),
                        newLit("deprecated, use (var_name) = ... instead")
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
                          letSection:
                            var fwd: seq[NimNode]
                            (implFwd(x[^1], fwd))
                            for x in fwd: x
                          impl(ident "parent", ident "this", x[^1], changableChild, changableChildUpdaters)
                    
                    for param in x[0..^3]:
                      param


              # if x: body
              elif x.kind == nnkIfStmt:
                ifStmt:
                  for x in x.children:
                    x[^1] = buildAst:
                      stmtList:
                        letSection:
                          var fwd: seq[NimNode]
                          (implFwd(x[^1], fwd))
                          for x in fwd: x
                        impl(ident "parent", ident "this", x[^1], changableChild, changableChildUpdaters)
                    x


              # case x:
              # of y: body
              elif x.kind == nnkCaseStmt:
                caseStmt:
                  x[0]

                  for x in x[1..^1]:
                    x[^1] = buildAst:
                      stmtList:
                        letSection:
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

        parent
        obj


  buildAst blockStmt:
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
        newStmtList(),
      )


template withWindow*(obj: Uiobj, winVar: untyped, body: untyped) =
  proc bodyProc(winVar {.inject.}: UiWindow) =
    body
  if obj.attachedToWindow:
    bodyProc(obj.parentUiWindow)
  obj.onSignal.connect obj.eventHandler, proc(e: Signal) =
    if e of AttachedToWindow:
      bodyProc(obj.parentUiWindow)



#----- reflection -----

macro generateDeteachMethod(t: typed) {.used.} =
  result = quote do:
    method deteach*(this: `t`) =
      deteachStatic(this)


macro generateConnectFirstHandHandlersMethod(t: typed) {.used.} =
  result = quote do:
    method connectFirstHandHandlers*(this: `t`) =
      connectFirstHandHandlersStatic(this)


macro generateShouldAutoredrawMethod(t: typed) {.used.} =
  var redraw = true
  for x in CacheSeq("disableAutoRedrawHook"):
    if t.getTypeName == x.getTypeName: redraw = false
  
  let shouldRedrawLit = newLit redraw

  result = quote do:
    method shouldAutoredraw*(this: `t`): bool =
      `shouldRedrawLit`



#----- reflection: dolars (formating Uiobj to string) -----

method componentTypeName*(this: Uiobj): string {.base.} = "Uiobj"


proc formatProperty[T](res: var seq[string], name: static string, prop: Property[T]) =
  if (prop[] != typeof(prop[]).default or prop.changed.hasExternalHandlers):
    when v is Uiobj:
      result.add name & ": -> " & prop[].componentTypeName
    
    elif compiles($prop[]):
      res.add name & ": " & $prop[]


proc formatProperty[T](res: var seq[string], name: static string, prop: CustomProperty[T]) =
  if (
    prop.get != nil and
    (prop[] != typeof(prop[]).default or prop.changed.hasExternalHandlers)
  ):
    when v is Uiobj:
      result.add name & ": -> " & prop[].componentTypeName
    
    elif compiles($prop[]):
      res.add name & ": " & $prop[]


proc formatValue[T](res: var seq[string], name: string, val: T) =
  if (val is bool) or (val is enum) or (val != typeof(val).default):
    when compiles($val):
      res.add name & ": " & $val


proc formatFieldsStatic[T: UiobjObjType](this: T): seq[string] {.inline.} =
  {.push, warning[Deprecated]: off.}
  result.add "box: " & $rect(this.x, this.y, this.w, this.h)
  
  for k, v in this.fieldPairs:
    when k in [
      "eventHandler", "parent", "childs", "x", "y", "w", "h", "globalX", "globalY",
      "initialized", "attachedToWindow", "anchors", "drawLayering"
    ] or k.startsWith("m_"):
      discard
    
    elif v is Uiobj:
      if v == nil:
        when k != "newChildsObject":
          result.add k & ": nil.Uiobj"
      else:
        result.add k & ": -> " & v.componentTypeName
    
    elif v is ChangableChild:
      if v[] == nil:
        result.add k & ": nil.Uiobj"
      else:
        result.add k & ": -> " & v[].componentTypeName
    
    elif v is Event:
      ## todo
    
    elif v is Property or v is CustomProperty:
      result.formatProperty(k, v)

    else:
      result.formatValue(k, v)

  {.pop.}


method formatFields*(this: Uiobj): seq[string] {.base.} =
  formatFieldsStatic(this[])


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
  let typename = newLit($t)

  result = quote do:
    method componentTypeName(this: `t`): string =
      `typename`


macro declareFormatFields(t: typed) =
  result = quote do:
    method formatFields(this: `t`): seq[string] =
      formatFieldsStatic(this[])


when defined(sigui_debug_redrawInitiatedBy):
  proc sigui_debug_redrawInitiatedBy_formatFunction(obj: Uiobj, alreadyRedrawing, hasWindow: bool): string =
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



#----- reflection: registerComponent -----

macro registerComponent*(t: typed) =
  result = newStmtList()
  result.add nnkCall.newTree(bindSym("generateDeteachMethod"), t)
  result.add nnkCall.newTree(bindSym("generateConnectFirstHandHandlersMethod"), t)
  result.add nnkCall.newTree(bindSym("generateShouldAutoredrawMethod"), t)
  result.add nnkCall.newTree(bindSym("declareComponentTypeName"), t)
  result.add nnkCall.newTree(bindSym("declareFormatFields"), t)


registerComponent UiWindow


import std/[times, macros, strutils, importutils, macrocache]
import pkg/[vmath, bumpy, chroma]
# import pkg/fusion/[astdsl]
import ./[events {.all.}, properties, window]
import ./render/[gl, contexts]

when defined(refactor):
  import refactoring/fileTemplates


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
    visible     ## draws itself, draws children
    hidden      ## does not draw anything itself, but still draw children
    hiddenTree  ## does not draw, including children
    collapsed   ## does not draw, does not count in layouts, behaves like zero-sized component in anchoring
  
  
  Signal* = ref object of RootObj
    sender* {.cursor.}: Uiobj
  

  Layering = object
    before: seq[UiobjCursor]
    beforeChilds: seq[UiobjCursor]
    after: seq[UiobjCursor]
  
  LayerOrder = enum
    before
    beforeChilds
    after

  Layer* = object
    obj* {.cursor.}: Uiobj
    order*: LayerOrder

  LayerPinned = object
    ## to correctly destruct itself, layer needs to know what object it is layering
    obj {.cursor.}: Uiobj
    order: LayerOrder
    this {.cursor.}: Uiobj

  SideOffsets* = object
    left*: float32
    right*: float32
    top*: float32
    bottom*: float32


  Uiobj* = ref UiobjObjType
  UiobjObjType = object of RootObj
    #? todo: use ptr object instead of ref object?
    eventHandler*: EventHandler
    
    parent* {.cursor.}: Uiobj
      ## parent of this object, that must have this object as child
      ## note: object can have no parent
    childs*: seq[Uiobj]
      ## childs that should be deleted when this object is deleted
    
    x*, y*, w*, h*: Property[float32]
      ## position of rect of the object

    visibility*: Property[Visibility]
      ## is component `visible`,
      ## hidden` (does not draw anything),
      ## `hiddenTree` (does not draw, including it's children), or
      ## `collapsed` (does not draw, does not count in layouts, behaves like zero-sized component in anchoring)
    
    globalTransform*: Property[bool]
      ## if true, x and y of this object is relative to UiRoot's top-left courner,
      ## if false, relative to parent's top-left courner

    globalX*, globalY*: Property[float32]
      ## position, relative to UiRoot (the window)
    
    onSignal*: Event[Signal]  #? todo: rename to gotSignal?
    completed*: Event[void]
    
    newChildsObject*: Uiobj

    isInitialized*: bool
    isDeteached*: bool
    isCompleted*: bool
    root* {.cursor.}: UiRoot
    
    anchors: Anchors

    layering: Layering
    m_layer: LayerPinned

    childsCow: ptr seq[Uiobj]
    beforeCow: ptr seq[UiobjCursor]
    beforeChildsCow: ptr seq[UiobjCursor]
    afterCow: ptr seq[UiobjCursor]


  UiobjCursor = object
    obj {.cursor.}: Uiobj


  UiRoot* = ref object of Uiobj
    onTick*: Event[TickEvent]


  ChangableChild*[T] = object
    parent {.cursor.}: Uiobj
    child {.cursor.}: Uiobj
    changed*: Event[void]


  #--- Signals ---
  #? todo: rename Signal to BroadcastEvent?

  SubtreeSignal* = ref object of Signal
    ## signal sends to all childs recursively (by default)

  SubtreeReverseSignal* = ref object of SubtreeSignal
    ## signal sends to all childs recursively in reverse order (by default)

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
    # child is just added to child.parent, sends after ParentChanged (for child)
    child*: Uiobj
  
  ChildRemoved* = ref object of UptreeSignal
    # child is about to be removed from child.parent
    child*: Uiobj


  Completed* = ref object of Signal
    ## signal for this element from makeLayout telling that it was fully created and will rarely be modified afterwards
    ## used in Layout's for optimization, only start updating after fully created.
  
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
  var i = 0
  if s[0] == '#':
    inc i

  case s.len - i
  of 3:
    result = colortypes.Color(
      r: ($s[i+0]).parseHexInt.float32 / 15.0,
      g: ($s[i+1]).parseHexInt.float32 / 15.0,
      b: ($s[i+2]).parseHexInt.float32 / 15.0,
      a: 1,
    )
  of 4:
    result = colortypes.Color(
      r: ($s[i+0]).parseHexInt.float32 / 15.0,
      g: ($s[i+1]).parseHexInt.float32 / 15.0,
      b: ($s[i+2]).parseHexInt.float32 / 15.0,
      a: ($s[i+3]).parseHexInt.float32 / 15.0,
    )
  of 6:
    result = colortypes.Color(
      r: (s[i+0 .. i+1].parseHexInt.float32) / 255.0,
      g: (s[i+2 .. i+3].parseHexInt.float32) / 255.0,
      b: (s[i+4 .. i+5].parseHexInt.float32) / 255.0,
      a: 1,
    )
  of 8:
    result = colortypes.Color(
      r: (s[i+0 .. i+1].parseHexInt.float32) / 255.0,
      g: (s[i+2 .. i+3].parseHexInt.float32) / 255.0,
      b: (s[i+4 .. i+5].parseHexInt.float32) / 255.0,
      a: (s[i+6 .. i+7].parseHexInt.float32) / 255.0,
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


template initialized*(this: Uiobj): var bool {.deprecated: "renamed to isInitialized".} =
  this.isInitialized

template `initialized=`*(this: Uiobj, v: bool) {.deprecated: "renamed to isInitialized".} =
  this.isInitialized = v


template deteached*(this: Uiobj): var bool {.deprecated: "renamed to isDeteached".} =
  this.isInitialized

template `deteached=`*(this: Uiobj, v: bool) {.deprecated: "renamed to isDeteached".} =
  this.isInitialized = v


proc makeCopy[T](arr: var seq[T], cow: var ptr seq[T]) =
  if cow == arr.addr:
    cow = create seq[T]
    cow[] = arr


iterator iterateChangeAware[T](arr: var seq[T], cow: var ptr seq[T]): T =
  let shouldReset = cow == nil
  if cow == nil: cow = arr.addr
  var i = 0
  while i < cow[].high:
    if (when T is UiobjCursor: not cow[][i].obj.isDeteached else: not cow[][i].isDeteached):
      yield cow[][i]
    inc i
  if shouldReset:
    if cow != arr.addr: dealloc(cow)
    cow = nil

iterator iterateChangeAwareReversed[T](arr: var seq[T], cow: var ptr seq[T]): T =
  let shouldReset = cow == nil
  if cow == nil: cow = arr.addr
  var i = arr.high
  while true:
    if i < 0: break
    if (when T is UiobjCursor: not cow[][i].obj.isDeteached else: not cow[][i].isDeteached):
      yield cow[][i]
    dec i
  if shouldReset:
    if cow != arr.addr: dealloc(cow)
    cow = nil



method draw*(obj: Uiobj, ctx: DrawContext) {.base.}
  ## draw current state to a window or framebuffer
  ## ! do not update state of ui objects on draw() !  handle BeforeDraw signal instead

proc drawBefore*(obj: Uiobj, ctx: DrawContext) =
  for x in obj.layering.before:
    draw(x.obj, ctx)

proc drawChilds*(obj: Uiobj, ctx: DrawContext) =
  if obj.visibility notin {hiddenTree, collapsed}:
    for x in obj.childs:
      if x.m_layer.obj == nil:
        draw(x, ctx)

proc drawBeforeChilds*(obj: Uiobj, ctx: DrawContext) =
  for x in obj.layering.beforeChilds:
    draw(x.obj, ctx)

proc drawAfterLayer*(obj: Uiobj, ctx: DrawContext) =
  for x in obj.layering.after:
    draw(x.obj, ctx)

proc drawAfter*(obj: Uiobj, ctx: DrawContext) =
  obj.drawBeforeChilds(ctx)
  obj.drawChilds(ctx)
  obj.drawAfterLayer(ctx)

method draw*(obj: Uiobj, ctx: DrawContext) {.base.} =
  obj.drawBefore(ctx)
  obj.drawAfter(ctx)


proc parentUiRoot*(obj: Uiobj, forceFind = false): UiRoot =
  if forceFind:
    var obj {.cursor.} = obj
    while true:
      if obj == nil: return nil
      if obj of UiRoot: return obj.UiRoot
      obj = obj.parent

  else:
    return obj.root


proc lastParent*(obj: Uiobj): Uiobj =
  result = obj
  while true:
    if result.parent == nil: return
    result = result.parent


method doRedraw*(obj: UiRoot) {.base.} = discard

proc redraw*(obj: Uiobj, ifVisible = true) =
  if ifVisible and obj.visibility[] != visible: return
  
  let root = obj.parentUiRoot
  if root != nil:
    doRedraw root


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


method mouseState*(root: UiRoot): Mouse {.base.} = discard
method keyboardState*(root: UiRoot): Keyboard {.base.} = discard
method touchscreenState*(root: UiRoot): TouchScreen {.base.} = discard

method `cursor=`(root: UiRoot, v: Cursor) {.base.} = discard


proc `$`*(this: Uiobj): string



#----- Events connection -----


template connectTo*[T](s: var Event[T], eh: EventHandler, body: untyped) =
  connect s, eh, proc(e {.inject.}: T) =
    body

template connectTo*(s: var Event[void], eh: EventHandler, body: untyped) =
  connect s, eh, proc() =
    body

template connectTo*[T](s: var Event[T], eh: EventHandler, argname: untyped, body: untyped) =
  connect s, eh, proc(argname {.inject.}: T) =
    body

template connectTo*(s: var Event[void], eh: EventHandler, argname: untyped, body: untyped) =
  connect s, eh, proc() =
    body


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



proc left*(offset: float32): SideOffsets =
  SideOffsets(left: offset)

proc right*(offset: float32): SideOffsets =
  SideOffsets(right: offset)

proc top*(offset: float32): SideOffsets =
  SideOffsets(top: offset)

proc bottom*(offset: float32): SideOffsets =
  SideOffsets(bottom: offset)

proc horizontal*(offset: float32): SideOffsets =
  SideOffsets(left: offset, right: offset)

proc vertical*(offset: float32): SideOffsets =
  SideOffsets(top: offset, bottom: offset)

proc allSides*(offset: float32): SideOffsets =
  SideOffsets(left: offset, right: offset, top: offset, bottom: offset)

converter toSideOffsets*(offset: SomeNumber): SideOffsets =
  allSides(offset.float32)


proc `+`*(a, b: SideOffsets): SideOffsets =
  SideOffsets(
    left:   a.left + b.left,
    right:  a.right + b.right,
    top:    a.top + b.top,
    bottom: a.bottom + b.bottom
  )
  
proc `-`*(a, b: SideOffsets): SideOffsets =
  SideOffsets(
    left:   a.left - b.left,
    right:  a.right - b.right,
    top:    a.top - b.top,
    bottom: a.bottom - b.bottom
  )
  
proc `-`*(a: SideOffsets): SideOffsets =
  SideOffsets(
    left:   -a.left,
    right:  -a.right,
    top:    -a.top,
    bottom: -a.bottom
  )

proc w*(offsets: SideOffsets): float32 =
  offsets.left + offsets.right

proc h*(offsets: SideOffsets): float32 =
  offsets.top + offsets.bottom


proc margin*(obj: Uiobj): SideOffsets =
  SideOffsets(
    left:    obj.anchors.left.offset,
    right:  -obj.anchors.right.offset,
    top:     obj.anchors.top.offset,
    bottom: -obj.anchors.bottom.offset,
  )

proc `margin=`*(obj: Uiobj, v: SideOffsets) =
  obj.anchors.left.offset   =  v.left
  obj.anchors.right.offset  = -v.right
  obj.anchors.top.offset    =  v.top
  obj.anchors.bottom.offset = -v.bottom
  obj.applyAnchors()


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

method recieve*(this: Uiobj, signal: Signal) {.base.}

proc handleSubtreeSignals(this: Uiobj, signal: Signal) =
  if signal of SubtreeReverseSignal:
    for child in this.childs.iterateChangeAwareReversed(this.childsCow):
      if child.m_layer.obj == nil:
        for after in child.layering.after.iterateChangeAwareReversed(child.afterCow):
          after.obj.recieve(signal)

        for beforeChilds in child.layering.beforeChilds.iterateChangeAwareReversed(child.beforeChildsCow):
          beforeChilds.obj.recieve(signal)
        
        child.recieve(signal)
        
        for before in child.layering.before.iterateChangeAwareReversed(child.beforeCow):
          before.obj.recieve(signal)

  elif signal of SubtreeSignal:
    for child in this.childs.iterateChangeAware(this.childsCow):
      if child.m_layer.obj == nil:
        for before in child.layering.before.iterateChangeAware(child.beforeCow):
          before.obj.recieve(signal)

        child.recieve(signal)

        for beforeChilds in child.layering.beforeChilds.iterateChangeAware(child.beforeChildsCow):
          beforeChilds.obj.recieve(signal)

        for after in child.layering.after.iterateChangeAware(child.afterCow):
          after.obj.recieve(signal)
  
  elif signal of UptreeSignal:
    if this.parent != nil:
      this.parent.recieve(signal)


method recieve*(this: Uiobj, signal: Signal) {.base.} =
  this.onSignal.emit signal

  handleSubtreeSignals(this, signal)



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
  if not (obj of UiRoot):
    assert obj.parent != nil, "ui object must be added to a parent before initializing"
  
  if not (obj of UiRoot):
    obj.root = obj.parent.root
  
  obj.globalX[] = obj.x + (if obj.parent == nil: 0'f32 else: obj.parent.globalX[])
  obj.globalY[] = obj.y + (if obj.parent == nil: 0'f32 else: obj.parent.globalY[])

  connectFirstHandHandlers(obj)

  obj.isInitialized = true


proc initIfNeeded*(obj: Uiobj) =
  if obj.isInitialized: return
  init(obj)
  if obj.parent != nil:
    obj.recieve(ParentChanged(newParentInTree: obj.parent))
    obj.parent.recieve(ChildAdded(child: obj))



#----- Anchors -----

proc fillHorizontal*[T: Uiobj](this: Uiobj, obj: T, margin: float32 = 0) =
  this.left = obj.left(margin)
  this.right = obj.right(-margin)

proc fillVertical*[T: Uiobj](this: Uiobj, obj: T, margin: float32 = 0) =
  this.top = obj.top(margin)
  this.bottom = obj.bottom(-margin)

proc centerIn*[T](this: Uiobj, obj: T, offset: Vec2 = vec2()) =
  this.centerX = obj.center(offset.x)
  this.centerY = obj.center(offset.y)

proc centerIn*(this: Uiobj, obj: Uiobj, offset: Vec2 = vec2(), xCenterAt: AnchorOffsetFrom, yCenterAt: AnchorOffsetFrom) =
  this.centerX = Anchor(obj: obj, offsetFrom: xCenterAt, offset: offset.x)
  this.centerY = Anchor(obj: obj, offsetFrom: yCenterAt, offset: offset.y)

proc fill*[T: Uiobj](this: Uiobj, obj: T, margin: float32 = 0) =
  this.fillHorizontal(obj, margin)
  this.fillVertical(obj, margin)

proc fill*[T: Uiobj](this: Uiobj, obj: T, marginX: float32, marginY: float32) =
  this.fillHorizontal(obj, marginX)
  this.fillVertical(obj, marginY)



#----- Layers -----

proc `=destroy`(l: LayerPinned) =
  if l.obj != nil:
    case l.order
    of before:
      l.obj.layering.before.makeCopy(l.obj.beforeCow)
      l.obj.layering.before.delete l.obj.layering.before.find(UiobjCursor(obj: l.this))
    
    of beforeChilds:
      l.obj.layering.beforeChilds.makeCopy(l.obj.beforeChildsCow)
      l.obj.layering.beforeChilds.delete l.obj.layering.beforeChilds.find(UiobjCursor(obj: l.this))
    
    of after:
      l.obj.layering.after.makeCopy(l.obj.afterCow)
      l.obj.layering.after.delete l.obj.layering.after.find(UiobjCursor(obj: l.this))

proc `=destroy`(l: Layering) =
  for x in l.before:
    x.obj.m_layer.obj = nil
    x.obj.m_layer = LayerPinned()
  for x in l.after:
    x.obj.m_layer.obj = nil
    x.obj.m_layer = LayerPinned()


proc before*(this: Uiobj): Layer =
  Layer(obj: this, order: LayerOrder.before)

proc beforeChilds*(this: Uiobj): Layer =
  Layer(obj: this, order: LayerOrder.beforeChilds)

proc after*(this: Uiobj): Layer =
  Layer(obj: this, order: LayerOrder.after)


proc `layer=`*(this: Uiobj, layer: typeof nil) =
  this.m_layer = LayerPinned()

proc `layer=`*(this: Uiobj, layer: Layer) =
  if this.m_layer.obj != nil: this.layer = nil
  if layer.obj == nil: return
  this.m_layer = LayerPinned(obj: layer.obj, order: layer.order, this: this)

  case layer.order
  of before:
    layer.obj.layering.before.makeCopy(layer.obj.beforeCow)
    layer.obj.layering.before.add UiobjCursor(obj: this)
  
  of beforeChilds:
    layer.obj.layering.beforeChilds.makeCopy(layer.obj.beforeChildsCow)
    layer.obj.layering.beforeChilds.add UiobjCursor(obj: this)
  
  of after:
    layer.obj.layering.after.makeCopy(layer.obj.afterCow)
    layer.obj.layering.after.add UiobjCursor(obj: this)


proc `drawLayer=`*(this: Uiobj, layer: typeof nil) {.deprecated: "use layer= instead".} =
  this.layer = nil

proc `drawLayer=`*(this: Uiobj, layer: Layer) {.deprecated: "use layer= instead".} =
  this.layer = layer



#----- Adding childs -----

method deteach*(this: Uiobj) {.base.}

proc deteachStatic[T: Uiobj](this: T) =
  if this == nil: return

  this.layer = nil
  this.isDeteached = true

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
  if this.parent != nil:
    this.parent.recieve(ChildRemoved(child: this))

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
    parent.childs.makeCopy(parent.childsCow)
    parent.childs.add child

    if child.isInitialized:
      child.recieve(ParentChanged(newParentInTree: parent))
      parent.recieve(ChildAdded(child: child))


proc `val=`*[T](p: var ChangableChild[T], v: T) =
  when T is Uiobj:
    if v == p.child: return
  else:
    if v.Uiobj == p.child: return
  
  let i = p.parent.childs.find(p.child)

  let oldChild = p.child

  if i == -1:
    delete oldChild
    p.parent.addChild(v)
  
  else:
    oldChild.parent = nil
    deteach oldChild
    p.parent.childs[i] = v
    v.parent = p.parent

    if v.isInitialized:
      v.recieve(ParentChanged(newParentInTree: p.parent))
      p.parent.recieve(ChildAdded(child: v))

  p.child = v
  emit(p.changed)

proc `[]=`*[T](p: var ChangableChild[T], v: T) {.inline.} = p.val = v

proc val*[T](p: ChangableChild[T]): T {.inline.} =
  result = p.child.T

proc val*(p: ChangableChild[Uiobj]): Uiobj {.inline.} =
  # we need this overload to avoid ConvFromXtoItselfNotNeeded warning
  result = p.child

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

    if child.isInitialized:
      child.recieve(ParentChanged(newParentInTree: parent))
      parent.recieve(ChildAdded(child: child))

    result = ChangableChild[Uiobj](parent: parent, child: child)


proc addChangableChild*[T: Uiobj](parent: Uiobj, child: T): ChangableChild[T] =
  parent.addChild(child)
  result = ChangableChild[T](parent: parent, child: child)


proc removeChild*(child: Uiobj) =
  ## only removes the parenting relation between `parent` and `child`
  ## does nothing if child has no parent
  if child.parent == nil: return
  child.parent.recieve(ChildRemoved(child: child))
  let i = child.parent.childs.find(child)
  if i != -1:
    child.parent.childs.makeCopy(child.parent.childsCow)
    child.parent.childs.delete i
  child.parent = nil


proc reparent*(child: Uiobj, newParent: Uiobj) =
  removeChild child
  newParent.addChild(child)


macro super*[T: Uiobj](obj: T): auto =
  var t = obj.getTypeImpl
  if t.kind == nnkRefTy and t[0].kind == nnkSym:
    t = t[0].getImpl
  
  if t.kind == nnkTypeDef and t[2].kind == nnkObjectTy and t[2][1].kind == nnkOfInherit:
    return nnkDotExpr.newTree(obj, t[2][1][0])
  else:
    error("unexpected type impl", obj)


proc markCompleted*(obj: Uiobj) =
  if obj.isCompleted: return
  obj.isCompleted = true
  obj.recieve(Completed())
  obj.completed.emit()


proc newUiobj*(): Uiobj = new result


template withRoot*(obj: Uiobj, rootVar: untyped, body: untyped) {.deprecated: "Ui objects always have a parent before initializing".} =
  proc bodyProc(rootVar {.inject.}: UiRoot) =
    body
  bodyProc(obj.root)


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
  # todo: this generates around 10% of binary size, used rarely for debugging. should be optimized
  {.push, warning[Deprecated]: off.}
  result.add "box: " & $rect(this.x, this.y, this.w, this.h)
  
  for k, v in this.fieldPairs:
    when k == "m_layer":
      if v.obj != nil:
        result.add "layer: " & $v.order & " " & v.obj.componentTypeName
    
    elif k in [
      "eventHandler", "parent", "childs", "x", "y", "w", "h", "globalX", "globalY",
      "isInitialized", "anchors", "layering", "isDeteached", "isCompleted"
    ] or k.startsWith("m_"):
      discard
    
    elif k == "root":
      if v == nil:
        result.add k & ": nil.UiRoot"
    
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
    var s = $x
    s = s.indent(2)
    s[0] = '-'
    result.add s.replace("  -", "- -")  # todo: optimize


proc `$`*(this: Uiobj): string =
  if this == nil: return "nil"
  result = this.componentTypeName & ":\n"
  result.add this.formatFields().join("\n").indent(2)
  if this.childs.len > 0:
    result.add "\n\n"
    result.add this.formatChilds()


macro declareComponentTypeName(t: typed) =
  let typename = newLit($t)

  result = quote do:
    method componentTypeName(this: `t`): string =
      `typename`


macro declareFormatFields(t: typed) =
  result = quote do:
    method formatFields(this: `t`): seq[string] =
      formatFieldsStatic(this[])



#----- reflection: registerComponent -----

macro registerComponent*(t: typed) =
  result = newStmtList()
  result.add nnkCall.newTree(bindSym("generateDeteachMethod"), t)
  result.add nnkCall.newTree(bindSym("generateConnectFirstHandHandlersMethod"), t)
  result.add nnkCall.newTree(bindSym("generateShouldAutoredrawMethod"), t)
  result.add nnkCall.newTree(bindSym("declareComponentTypeName"), t)
  result.add nnkCall.newTree(bindSym("declareFormatFields"), t)

template registerWidget*(t: typed) =
  registerComponent(t)

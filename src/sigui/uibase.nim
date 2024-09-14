import times, macros, tables, unicode, strutils
import vmath, bumpy, siwin, shady, fusion/[matching, astdsl], pixie, pixie/fileformats/svg
import ./[events, properties]
import ./render/[gl, contexts]
when hasImageman:
  import imageman except Rect, color, Color

export vmath, bumpy, gl, pixie, events, properties, tables, contexts

when defined(sigui_debug_useLogging):
  import logging


type
  Col* = pixie.Color

  AnchorOffsetFrom = enum
    start
    center
    `end`

  Anchor* = object
    obj: UiObj
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
    collapsed
  
  
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
    
    anchors: Anchors

    drawLayering: DrawLayering
    m_drawLayer: DrawLayer


  UiobjCursor = object
    obj {.cursor.}: Uiobj


  #--- Signals ---

  SubtreeSignal* = ref object of Signal
    ## signal sends to all childs recursively (by default)
  
  AttachedToWindow* = ref object of SubtreeSignal
    window*: UiWindow

  ParentChanged* = ref object of SubtreeSignal
    newParentInTree*: Uiobj

  ParentPositionChanged* = ref object of SubtreeSignal
    parent*: Uiobj
    position*: Vec2
  
  WindowEvent* = ref object of SubtreeSignal
    event*: ref AnyWindowEvent
    handled*: bool
    fake*: bool
  
  GetActiveCursor* = ref object of SubtreeSignal
    cursor*: ref Cursor
  
  VisibilityChanged* = ref object of SubtreeSignal
    visibility*: Visibility

  
  UptreeSignal* = ref object of Signal
    ## signal sends to all parents recursively (by default)
  
  ChildAdded* = ref object of UptreeSignal
    child*: Uiobj

  
  #--- Basic Components ---

  UiWindow* = ref object of Uiobj
    siwinWindow*: Window
    ctx*: DrawContext
    clearColor*: Col
    onTick*: Event[TickEvent]


  UiRect* = ref object of Uiobj
    color*: Property[Col] = color(0, 0, 0).property
    radius*: Property[float32]
    angle*: Property[float32]
  

  UiImage* = ref object of Uiobj
    radius*: Property[float32]
    blend*: Property[bool] = true.property
    tex: Texture
    imageWh*: Property[IVec2]
    angle*: Property[float32]
    color*: Property[Col] = color(1, 1, 1).property
    colorOverlay*: Property[bool]
      ## if true, image will have flat color, with image alpha working like a mask (useful for icons)

  UiIcon* {.deprecated: "use UiImage with .colorOverlay[]=true instead".} = ref object of UiImage

  UiSvgImage* = ref object of Uiobj
    ## pixel-perfect svg image
    ## expensive resize
    radius*: Property[float32]
    blend*: Property[bool] = true.property
    image*: Property[string]
    imageWh*: Property[IVec2]
    angle*: Property[float32]
    color*: Property[Col] = color(0, 0, 0).property
    tex: Texture

  UiRectBorder* = ref object of UiRect
    borderWidth*: Property[float32] = 1'f32.property
    tiled*: Property[bool]
    tileSize*: Property[Vec2] = vec2(4, 4).property
    tileSecondSize*: Property[Vec2] = vec2(2, 2).property
    secondColor*: Property[Col]

  UiRectStroke* {.deprecated: "renamed to UiRectBorder".} = UiRectBorder

  RectShadow* = ref object of UiRect
    blurRadius*: Property[float32]
  

  ClipRect* = ref object of Uiobj
    radius*: Property[float32]
    angle*: Property[float32]
    color*: Property[Col] = color(1, 1, 1).property
    fbo: FrameBuffers
    tex: Texture
    prevSize: IVec2
  

  UiText* = ref object of Uiobj
    text*: Property[string]
    font*: Property[Font]
    bounds*: Property[Vec2]
    hAlign*: Property[HorizontalAlignment]
    vAlign*: Property[VerticalAlignment]
    wrap*: Property[bool] = true.property
    angle*: Property[float32]
    color*: Property[Col] = color(0, 0, 0).property

    arrangement*: Property[Arrangement]
    roundPositionOnDraw*: Property[bool] = true.property
    tex: Texture
  
  BindingKind = enum
    bindProperty
    bindValue
    bindProc
  
  HasEventHandler* = concept x
    x.eventHandler is EventHandler


var globalDefaultFont* {.deprecated: "use styles instead".}: Font

var registredComponents {.compileTime.}: seq[NimNode]
  # type syms
var registredReflection {.compileTime.}: seq[tuple[f: NimNode, filter: NimNode]]
  # callable syms


var globalClipboard* = siwin.clipboard()


proc vec4*(color: Col): Vec4 =
  vec4(color.r, color.g, color.b, color.a)

proc color*(v: Vec4): Col =
  Col(r: v.x, g: v.y, b: v.z, a: v.w)

proc round*(v: Vec2): Vec2 =
  vec2(round(v.x), round(v.y))

proc ceil*(v: Vec2): Vec2 =
  vec2(ceil(v.x), ceil(v.y))

proc floor*(v: Vec2): Vec2 =
  vec2(floor(v.x), floor(v.y))


proc containsShift*(keyboardPressed: set[Key]): bool =
  Key.lshift in keyboardPressed or Key.rshift in keyboardPressed

proc containsControl*(keyboardPressed: set[Key]): bool =
  Key.lcontrol in keyboardPressed or Key.rcontrol in keyboardPressed

proc containsAlt*(keyboardPressed: set[Key]): bool =
  Key.lalt in keyboardPressed or Key.ralt in keyboardPressed

proc containsSystem*(keyboardPressed: set[Key]): bool =
  Key.lsystem in keyboardPressed or Key.rsystem in keyboardPressed



#* ------------- Uiobj ------------- *#


proc xy*(obj: Uiobj): CustomProperty[Vec2] =
  ##! never emits changed event
  CustomProperty[Vec2](
    get: proc(): Vec2 = vec2(obj.x[], obj.y[]),
    set: proc(v: Vec2) = obj.x[] = v.x; obj.y[] = v.y,
  )

proc wh*(obj: Uiobj): CustomProperty[Vec2] =
  ##! never emits changed event
  CustomProperty[Vec2](
    get: proc(): Vec2 = vec2(obj.w[], obj.h[]),
    set: proc(v: Vec2) = obj.w[] = v.x; obj.h[] = v.y,
  )


proc globalXy*(obj: Uiobj): CustomProperty[Vec2] =
  ##! never emits changed event
  CustomProperty[Vec2](
    get: proc(): Vec2 = vec2(obj.globalX[], obj.globalY[]),
    set: proc(v: Vec2) = obj.globalX[] = v.x; obj.globalY[] = v.y,
  )


method draw*(obj: Uiobj, ctx: DrawContext) {.base.}

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
  var sigui_debug_redrawInitiatedBy_formatFunction: proc(obj: Uiobj, alreadyRedrawing, hasWindow: bool): string =
    proc(obj: Uiobj, alreadyRedrawing, hasWindow: bool): string =
      if alreadyRedrawing:
        "redraw initiated (already redrawing)"
      else:
        "redraw initiated"

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


redrawUiobj = proc(obj: pointer) {.cdecl.} =
  redraw cast[Uiobj](obj)


proc posToLocal*(pos: Vec2, obj: Uiobj): Vec2 =
  result = pos
  var obj {.cursor.} = obj
  while true:
    if obj == nil: return
    result -= obj.xy[]
    if obj.globalTransform: return
    obj = obj.parent

proc posToGlobal*(pos: Vec2, obj: Uiobj): Vec2 =
  result = pos
  var obj {.cursor.} = obj
  while true:
    if obj == nil: return
    result += obj.xy[]
    if obj.globalTransform: return
    obj = obj.parent


proc posToObject*(fromObj, toObj: Uiobj, pos: Vec2): Vec2 =
  pos.posToGlobal(fromObj).posToLocal(toObj)

proc posToObject*(pos: Vec2, fromObj, toObj: Uiobj): Vec2 =
  pos.posToGlobal(fromObj).posToLocal(toObj)


proc pos*(anchor: Anchor, isY: bool): Vec2 =
  assert anchor.obj != nil
  let p = case anchor.offsetFrom
  of start:
    if isY:
      if anchor.obj.visibility == collapsed and anchor.obj.anchors.top.obj == nil and anchor.obj.anchors.bottom.obj != nil:
        anchor.obj.h[] + anchor.offset
      else:
        anchor.offset
    else:
      if anchor.obj.visibility == collapsed and anchor.obj.anchors.left.obj == nil and anchor.obj.anchors.right.obj != nil:
        anchor.obj.w[] + anchor.offset
      else:
        anchor.offset
  of `end`:
    if isY:
      if anchor.obj.visibility == collapsed and anchor.obj.anchors.top.obj != nil and anchor.obj.anchors.bottom.obj == nil:
        anchor.offset
      else:
        anchor.obj.h[] + anchor.offset
    else:
      if anchor.obj.visibility == collapsed and anchor.obj.anchors.left.obj != nil and anchor.obj.anchors.right.obj == nil:
        anchor.offset
      else:
        anchor.obj.w[] + anchor.offset
  of center:
    if isY:
      if anchor.obj.visibility == collapsed:
        if anchor.obj.anchors.top.obj == nil and anchor.obj.anchors.bottom.obj != nil:
          anchor.obj.h[] + anchor.offset
        else:
          anchor.offset
      else:
        anchor.obj.h[] / 2 + anchor.offset
    else:
      if anchor.obj.visibility == collapsed:
        if anchor.obj.anchors.left.obj == nil and anchor.obj.anchors.right.obj != nil:
          anchor.obj.w[] + anchor.offset
        else:
          anchor.offset
      else:
        anchor.obj.w[] / 2 + anchor.offset

  if isY: vec2(0, p).posToGlobal(anchor.obj)
  else: vec2(p, 0).posToGlobal(anchor.obj)


#--- Events connection ---

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


#--- Reposition ---

proc applyAnchors*(obj: Uiobj) =
  # x and w
  if obj.anchors.left.obj != nil:
    obj.x[] = obj.anchors.left.pos(isY=false).posToLocal(obj.parent).x
  
  if obj.anchors.right.obj != nil:
    if obj.anchors.left.obj != nil:
      obj.w[] = obj.anchors.right.pos(isY=false).posToLocal(obj.parent).x - obj.x[]
    else:
      obj.x[] = obj.anchors.right.pos(isY=false).posToLocal(obj.parent).x - obj.w[]
  
  if obj.anchors.centerX.obj != nil:
    obj.x[] = obj.anchors.centerX.pos(isY=false).posToLocal(obj.parent).x - obj.w[] / 2

  # y and h
  if obj.anchors.top.obj != nil:
    obj.y[] = obj.anchors.top.pos(isY=true).posToLocal(obj.parent).y
  
  if obj.anchors.bottom.obj != nil:
    if obj.anchors.top.obj != nil:
      obj.h[] = obj.anchors.bottom.pos(isY=true).posToLocal(obj.parent).y - obj.y[]
    else:
      obj.y[] = obj.anchors.bottom.pos(isY=true).posToLocal(obj.parent).y - obj.h[]
  
  if obj.anchors.centerY.obj != nil:
    obj.y[] = obj.anchors.centerY.pos(isY=true).posToLocal(obj.parent).y - obj.h[] / 2


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
  if anchor.obj == nil: return
  if not isY:
    case anchor.offsetFrom:
    of start:
      anchor.obj.globalX.changed.connectTo anchor: this.applyAnchors()
    of `end`:
      anchor.obj.globalX.changed.connectTo anchor: this.applyAnchors()
      anchor.obj.w.changed.connectTo anchor: this.applyAnchors()
    of center:
      anchor.obj.globalX.changed.connectTo anchor: this.applyAnchors()
      anchor.obj.w.changed.connectTo anchor: this.applyAnchors()
  else:
    case anchor.offsetFrom:
    of start:
      anchor.obj.globalY.changed.connectTo anchor: this.applyAnchors()
    of `end`:
      anchor.obj.globalY.changed.connectTo anchor: this.applyAnchors()
      anchor.obj.h.changed.connectTo anchor: this.applyAnchors()
    of center:
      anchor.obj.globalY.changed.connectTo anchor: this.applyAnchors()
      anchor.obj.h.changed.connectTo anchor: this.applyAnchors()
  anchor.obj.visibility.changed.connectTo anchor: this.applyAnchors()

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


method recieve*(obj: Uiobj, signal: Signal) {.base.} =
  if signal of AttachedToWindow:
    obj.attachedToWindow = true

  if signal of ParentPositionChanged:
    let p = vec2(obj.x[], obj.y[]).posToGlobal(obj.parent)
    obj.globalX[] = p.x
    obj.globalY[] = p.y

  obj.onSignal.emit signal

  if signal of SubtreeSignal:
    for x in obj.childs:
      x.recieve(signal)
  
  if signal of UptreeSignal:
    if obj.parent != nil:
      obj.parent.recieve(signal)


proc initRedrawWhenPropertyChangedStatic[T: UiObj](this: T) =
  {.push, warning[Deprecated]: off.}
  for name, x in this[].fieldPairs:
    when name == "visibility":
      x.changed.connectTo this: redraw(this, ifVisible=false)
    
    elif name == "globalX" or name == "globalY":
      discard  # will anyway be handled in parent

    elif x is Property or x is CustomProperty:
      when compiles(initRedrawWhenPropertyChanged_ignore(T, name)):
        when not initRedrawWhenPropertyChanged_ignore(T, name):
          x.changed.uiobj = cast[pointer](this)
      else:
        x.changed.uiobj = cast[pointer](this)
  {.pop.}


method initRedrawWhenPropertyChanged*(obj: Uiobj) {.base.} =
  initRedrawWhenPropertyChangedStatic(obj)


method init*(obj: Uiobj) {.base.} =
  initRedrawWhenPropertyChanged(obj)

  obj.visibility.changed.connectTo obj:
    obj.recieve(VisibilityChanged(sender: obj, visibility: obj.visibility))
  
  obj.w.changed.connectTo obj: obj.applyAnchors()
  obj.h.changed.connectTo obj: obj.applyAnchors()

  obj.x.changed.connectTo obj:
    obj.recieve(ParentPositionChanged(sender: obj, parent: obj, position: obj.xy[]))
  obj.y.changed.connectTo obj:
    obj.recieve(ParentPositionChanged(sender: obj, parent: obj, position: obj.xy[]))

  let p = vec2(obj.x[], obj.y[]).posToGlobal(obj.parent)
  obj.globalX[] = p.x
  obj.globalY[] = p.y
  
  if not obj.attachedToWindow:
    let win = obj.parentUiWindow
    if win != nil:
      obj.recieve(AttachedToWindow(window: win))

  obj.initialized = true

proc initIfNeeded*(obj: Uiobj) =
  if obj.initialized: return
  init(obj)

#--- Anchors ---

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


method deteach*(this: UiObj) {.base.}

proc deteachStatic[T: UiObj](this: T) =
  if this == nil: return

  disconnect this.eventHandler
  for x in this.childs: deteach(x)

  {.push, warning[Deprecated]: off.}
  for x in this[].fields:
    when x is Property or x is CustomProperty:
      disconnect x.changed
  {.pop.}


method deteach*(this: UiObj) {.base.} =
  ## disconnect all events
  deteachStatic(this)


proc delete*(this: UiObj) =
  deteach this
  if this.parent != nil:
    this.parent.childs.del this.parent.childs.find(this)
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
    child.recieve(ParentChanged(newParentInTree: parent))
    parent.recieve(ChildAdded(child: child))


method addChangableChildUntyped*(parent: Uiobj, child: Uiobj): CustomProperty[Uiobj] {.base.} =
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
    child.recieve(ParentChanged(newParentInTree: parent))
    parent.recieve(ChildAdded(child: child))

    let i = parent.childs.high
    result = CustomProperty[Uiobj](
      get: proc(): Uiobj = parent.childs[i],
      set: (proc(v: Uiobj) =
        parent.childs[i].parent = nil
        deteach parent.childs[i]
        parent.childs[i] = v
        v.parent = parent
        v.recieve(ParentChanged(newParentInTree: parent))
        parent.recieve(ChildAdded(child: v))
      ),
    )


proc addChangableChild*[T: UiObj](parent: Uiobj, child: T): CustomProperty[T] =
  var prop = parent.addChangableChildUntyped(child)
  cast[ptr CustomProperty[UiObj]](result.addr)[] = move prop



macro super*[T: Uiobj](obj: T): auto =
  var t = obj.getTypeImpl
  case t
  of RefTy[@sym is Sym()]:
    t = sym.getImpl
  case t
  of TypeDef[_, _, ObjectTy[_, OfInherit[@sup], .._]]:
    return buildAst(dotExpr):
      obj
      sup
  else: error("unexpected type impl", obj)



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



#----- DrawContext -----


proc roundRect(pos, size: Vec2, radius: float32): float32 =
  if radius == 0: return 1
  
  if pos.x < radius and pos.y < radius:
    let d = length(pos - vec2(radius, radius))
    return (radius - d + 0.5).max(0).min(1)
  
  elif pos.x > size.x - radius and pos.y < radius:
    let d = length(pos - vec2(size.x - radius, radius))
    return (radius - d + 0.5).max(0).min(1)
  
  elif pos.x < radius and pos.y > size.y - radius:
    let d = length(pos - vec2(radius, size.y - radius))
    return (radius - d + 0.5).max(0).min(1)
  
  elif pos.x > size.x - radius and pos.y > size.y - radius:
    let d = length(pos - vec2(size.x - radius, size.y - radius))
    return (radius - d + 0.5).max(0).min(1)

  return 1


proc drawRect*(ctx: DrawContext, pos: Vec2, size: Vec2, col: Vec4, radius: float32, blend: bool, angle: float32) =
  let shader = ctx.makeShader:
    proc vert(
      gl_Position: var Vec4,
      pos: var Vec2,
      ipos: Vec2,
      transform: Uniform[Mat4],
      size: Uniform[Vec2],
      px: Uniform[Vec2],
    ) =
      transformation(gl_Position, pos, size, px, ipos, transform)

    proc frag(
      glCol: var Vec4,
      pos: Vec2,
      radius: Uniform[float],
      size: Uniform[Vec2],
      color: Uniform[Vec4],
    ) =
      glCol = vec4(color.rgb * color.a, color.a) * roundRect(pos, size, radius)
  
  if blend:
    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

  use shader.shader
  ctx.passTransform(shader, pos=pos, size=size, angle=angle)
  shader.radius.uniform = radius
  shader.color.uniform = col
  draw ctx.rect
  if blend: glDisable(GlBlend)


proc drawRectStroke*(ctx: DrawContext, pos: Vec2, size: Vec2, col: Vec4, radius: float32, blend: bool, angle: float32, borderWidth: float32, tiled: bool, tileSize: Vec2, tileSecondSize: Vec2, secondColor: Vec4) =
  let shader = ctx.makeShader:
    proc roundRectStroke(pos, size: Vec2, radius: float32, borderWidth: float32): float32 =
      if pos.x < radius + borderWidth and pos.y < radius + borderWidth:
        let d = length(pos - vec2(radius, radius) - vec2(borderWidth, borderWidth))
        return (radius + borderWidth - d + 0.5).max(0).min(1) * (1 - (radius - d + 0.5).max(0).min(1))
      
      elif pos.x > size.x - radius - borderWidth and pos.y < radius + borderWidth:
        let d = length(pos - vec2(size.x - radius, radius) - vec2(-borderWidth, borderWidth))
        return (radius + borderWidth - d + 0.5).max(0).min(1) * (1 - (radius - d + 0.5).max(0).min(1))
      
      elif pos.x < radius + borderWidth and pos.y > size.y - radius - borderWidth:
        let d = length(pos - vec2(radius, size.y - radius) - vec2(borderWidth, -borderWidth))
        return (radius + borderWidth - d + 0.5).max(0).min(1) * (1 - (radius - d + 0.5).max(0).min(1))
      
      elif pos.x > size.x - radius - borderWidth and pos.y > size.y - radius - borderWidth:
        let d = length(pos - vec2(size.x - radius, size.y - radius) - vec2(-borderWidth, -borderWidth))
        return (radius + borderWidth - d + 0.5).max(0).min(1) * (1 - (radius - d + 0.5).max(0).min(1))

      elif pos.x < borderWidth: return 1
      elif pos.y < borderWidth: return 1
      elif pos.x > size.x - borderWidth: return 1
      elif pos.y > size.y - borderWidth: return 1
      return 0

    proc strokeTiling(pos, size, tileSize, tileSecondSize: Vec2, radius, borderWidth: float32): float32 =
      if tileSize == size: return 0

      if (
        (pos.x < radius + borderWidth and pos.y < radius + borderWidth) or
        (pos.x > size.x - radius - borderWidth and pos.y < radius + borderWidth) or
        (pos.x < radius + borderWidth and pos.y > size.y - radius - borderWidth) or
        (pos.x > size.x - radius - borderWidth and pos.y > size.y - radius - borderWidth)
      ):
        return 0
      else:
        if pos.x <= borderWidth or pos.x >= size.x - borderWidth:
          var y = pos.y
          while y > 0:
            if y < tileSize.y: return 0
            y -= tileSize.y
            if y < tileSecondSize.y: return 1
            y -= tileSecondSize.y
        else:
          var x = pos.x
          while x > 0:
            if x < tileSize.x: return 0
            x -= tileSize.x
            if x < tileSecondSize.x: return 1
            x -= tileSecondSize.x
        return 1


    proc vert(
      gl_Position: var Vec4,
      pos: var Vec2,
      ipos: Vec2,
      transform: Uniform[Mat4],
      size: Uniform[Vec2],
      px: Uniform[Vec2],
    ) =
      transformation(gl_Position, pos, size, px, ipos, transform)

    proc frag(
      glCol: var Vec4,
      pos: Vec2,
      radius: Uniform[float],
      size: Uniform[Vec2],
      color: Uniform[Vec4],
      borderWidth: Uniform[float],
      tileSize: Uniform[Vec2],
      tileSecondSize: Uniform[Vec2],
      secondColor: Uniform[Vec4],
    ) =
      if strokeTiling(pos, size, tileSize, tileSecondSize, radius, borderWidth) > 0:
        glCol =
          vec4(secondColor.rgb * secondColor.a, secondColor.a) *
          roundRectStroke(pos, size, radius, borderWidth)
      else:
        glCol =
          vec4(color.rgb * color.a, color.a) *
          roundRectStroke(pos, size, radius, borderWidth)
  
  if blend:
    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

  use shader.shader
  ctx.passTransform(shader, pos=pos, size=size, angle=angle)
  shader.radius.uniform = radius
  shader.color.uniform = col
  shader.borderWidth.uniform = borderWidth
  if tiled:
    shader.tileSize.uniform = tileSize
    shader.tileSecondSize.uniform = tileSecondSize
  else:
    shader.tileSize.uniform = size
    shader.tileSecondSize.uniform = vec2(0, 0)
  shader.secondColor.uniform = secondColor
  draw ctx.rect
  if blend: glDisable(GlBlend)


proc drawImage*(ctx: DrawContext, pos: Vec2, size: Vec2, tex: GlUint, color: Vec4, radius: float32, blend: bool, angle: float32, flipY = false) =
  let shader = ctx.makeShader:
    proc vert(
      gl_Position: var Vec4,
      pos: var Vec2,
      uv: var Vec2,
      ipos: Vec2,
      transform: Uniform[Mat4],
      size: Uniform[Vec2],
      px: Uniform[Vec2],
    ) =
      transformation(gl_Position, pos, size, px, ipos, transform)
      uv = ipos

    proc frag(
      glCol: var Vec4,
      pos: Vec2,
      uv: Vec2,
      radius: Uniform[float],
      size: Uniform[Vec2],
      color: Uniform[Vec4],
    ) =
      let c = gltex.texture(uv)
      glCol = vec4(c.rgb, c.a) * roundRect(pos, size, radius) * vec4(color.rgb * color.a, color.a)

  if blend:
    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)
  
  use shader.shader
  ctx.passTransform(shader, pos=pos, size=size, angle=angle, flipY=flipY)
  shader.radius.uniform = radius
  shader.color.uniform = color
  glBindTexture(GlTexture2d, tex)
  draw ctx.rect
  glBindTexture(GlTexture2d, 0)
  if blend: glDisable(GlBlend)


proc drawIcon*(ctx: DrawContext, pos: Vec2, size: Vec2, tex: GlUint, col: Vec4, radius: float32, blend: bool, angle: float32) =
  # draw image (with solid color)
  let shader = ctx.makeShader:
    proc vert(
      gl_Position: var Vec4,
      pos: var Vec2,
      uv: var Vec2,
      ipos: Vec2,
      transform: Uniform[Mat4],
      size: Uniform[Vec2],
      px: Uniform[Vec2],
    ) =
      transformation(gl_Position, pos, size, px, ipos, transform)
      uv = ipos

    proc frag(
      glCol: var Vec4,
      pos: Vec2,
      uv: Vec2,
      radius: Uniform[float],
      size: Uniform[Vec2],
      color: Uniform[Vec4],
    ) =
      let col = gltex.texture(uv)
      glCol = vec4(color.rgb * color.a, color.a) * col.a * roundRect(pos, size, radius)

  if blend:
    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

  use shader.shader
  ctx.passTransform(shader, pos=pos, size=size, angle=angle)
  shader.radius.uniform = radius
  shader.color.uniform = col
  glBindTexture(GlTexture2d, tex)
  draw ctx.rect
  glBindTexture(GlTexture2d, 0)
  if blend: glDisable(GlBlend)


proc drawShadowRect*(ctx: DrawContext, pos: Vec2, size: Vec2, col: Vec4, radius: float32, blend: bool, blurRadius: float32, angle: float32) =
  let shader = ctx.makeShader:
    proc distanceRoundRect(pos, size: Vec2, radius: float32, blurRadius: float32): float32 =
      if pos.x < radius + blurRadius and pos.y < radius + blurRadius:
        let d = length(pos - vec2(radius + blurRadius, radius + blurRadius))
        result = ((radius + blurRadius - d) / blurRadius).max(0).min(1)
      
      elif pos.x > size.x - radius - blurRadius and pos.y < radius + blurRadius:
        let d = length(pos - vec2(size.x - radius - blurRadius, radius + blurRadius))
        result = ((radius + blurRadius - d) / blurRadius).max(0).min(1)
      
      elif pos.x < radius + blurRadius and pos.y > size.y - radius - blurRadius:
        let d = length(pos - vec2(radius + blurRadius, size.y - radius - blurRadius))
        result = ((radius + blurRadius - d) / blurRadius).max(0).min(1)
      
      elif pos.x > size.x - radius - blurRadius and pos.y > size.y - radius - blurRadius:
        let d = length(pos - vec2(size.x - radius - blurRadius, size.y - radius - blurRadius))
        result = ((radius + blurRadius - d) / blurRadius).max(0).min(1)
      
      elif pos.x < blurRadius:
        result = (pos.x / blurRadius).max(0).min(1)

      elif pos.y < blurRadius:
        result = (pos.y / blurRadius).max(0).min(1)
      
      elif pos.x > size.x - blurRadius:
        result = ((size.x - pos.x) / blurRadius).max(0).min(1)

      elif pos.y > size.y - blurRadius:
        result = ((size.y - pos.y) / blurRadius).max(0).min(1)
      
      else:
        result = 1
      
      result *= result

    proc vert(
      gl_Position: var Vec4,
      pos: var Vec2,
      ipos: Vec2,
      transform: Uniform[Mat4],
      size: Uniform[Vec2],
      px: Uniform[Vec2],
    ) =
      transformation(gl_Position, pos, size, px, ipos, transform)

    proc frag(
      glCol: var Vec4,
      pos: Vec2,
      radius: Uniform[float],
      blurRadius: Uniform[float],
      size: Uniform[Vec2],
      color: Uniform[Vec4],
    ) =
      glCol = vec4(color.rgb * color.a, color.a) * distanceRoundRect(pos, size, radius, blurRadius)

  if blend:
    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)
  
  use shader.shader
  ctx.passTransform(shader, pos=pos, size=size, angle=angle)
  shader.radius.uniform = radius
  shader.color.uniform = col
  shader.blurRadius.uniform = blurRadius
  draw ctx.rect
  if blend: glDisable(GlBlend)



#----- Basic Components -----

{.push, warning[Deprecated]: off.}

method init*(this: UiIcon) =
  procCall this.super.init
  this.colorOverlay[] = true

{.pop.}


proc `image=`*(obj: UiImage, img: pixie.Image) =
  if img != nil:
    if obj.tex == nil: obj.tex = newTexture()
    obj.tex.load(img)
    if obj.wh[] == vec2():
      obj.wh[] = vec2(img.width.float32, img.height.float32)
    obj.imageWh[] = ivec2(img.width.int32, img.height.int32)

when hasImageman:
  proc `image=`*(obj: UiImage, img: imageman.Image[ColorRGBAU]) =
    if obj.tex == nil: obj.tex = newTexture()
    obj.tex.load(img)
    if obj.wh[] == vec2():
      obj.wh[] = vec2(img.width.float32, img.height.float32)
    obj.imageWh[] = ivec2(img.width.int32, img.height.int32)


method draw*(rect: UiRect, ctx: DrawContext) =
  rect.drawBefore(ctx)
  if rect.visibility[] == visible:
    ctx.drawRect((rect.xy[].posToGlobal(rect.parent) + ctx.offset).round, rect.wh[], rect.color.vec4, rect.radius, rect.color[].a != 1 or rect.radius != 0, rect.angle)
  rect.drawAfter(ctx)


method draw*(this: UiImage, ctx: DrawContext) =
  this.drawBefore(ctx)
  if this.visibility[] == visible and this.tex != nil:
    if this.colorOverlay[]:
      ctx.drawIcon(
        (this.xy[].posToGlobal(this.parent) + ctx.offset).round, this.wh[], this.tex.raw,
        this.color.vec4, this.radius, this.blend or this.radius != 0, this.angle
      )
    else:
      ctx.drawImage(
        (this.xy[].posToGlobal(this.parent) + ctx.offset).round, this.wh[], this.tex.raw,
        this.color.vec4, this.radius, this.blend or this.radius != 0, this.angle
      )
  this.drawAfter(ctx)


method init*(this: UiSvgImage) =
  procCall this.super.init

  var prevSize = ivec2(0, 0)
  proc updateTexture(size = ivec2()) =
    let sz =
      if size.x > 0 and size.y > 0: size
      elif this.w[].int32 > 0 and this.h[].int32 > 0: this.wh[].ivec2
      else: ivec2(0, 0)
    
    prevSize = size
    
    if this.image[] != "":
      
      var img = this.image[].parseSvg(sz.x, sz.y).newImage
      
      if this.tex == nil: this.tex = newTexture()
      this.tex.load(img)
      if this.wh[] == vec2():
        this.wh[] = vec2(img.width.float32, img.height.float32)
      if size == ivec2():
        this.imageWh[] = ivec2(img.width.int32, img.height.int32)
    else:
      this.imageWh[] = ivec2()

  this.image.changed.connectTo this: updateTexture()
  this.w.changed.connectTo this: updateTexture(this.wh[].ceil.ivec2)
  this.h.changed.connectTo this: updateTexture(this.wh[].ceil.ivec2)


method draw*(ico: UiSvgImage, ctx: DrawContext) =
  ico.drawBefore(ctx)
  if ico.visibility[] == visible and ico.tex != nil:
    ctx.drawIcon((ico.xy[].posToGlobal(ico.parent) + ctx.offset).round, ico.wh[].ceil, ico.tex.raw, ico.color.vec4, ico.radius, ico.blend or ico.radius != 0, ico.angle)
  ico.drawAfter(ctx)


proc `fontSize=`*(this: UiText, size: float32) =
  this.font[].size = size
  this.font.changed.emit()

method init*(this: UiText) =
  procCall this.super.init

  this.arrangement.changed.connectTo this:
    if this.tex == nil: this.tex = newTexture()
    if this.arrangement[] != nil:
      let bounds = this.arrangement[].layoutBounds
      this.wh[] = bounds
      if bounds.x == 0 or bounds.y == 0: return
      let image = newImage(bounds.x.ceil.int32, bounds.y.ceil.int32)
      image.fillText(this.arrangement[])
      this.tex.load(image)
      # todo: reposition
    else:
      this.wh[] = vec2()

  template newArrangement: Arrangement =
    if this.text[] != "" and this.font != nil:
      typeset(this.font[], this.text[], this.bounds[], this.hAlign[], this.vAlign[], this.wrap[])
    else: nil

  this.text.changed.connectTo this: this.arrangement[] = newArrangement
  this.font.changed.connectTo this: this.arrangement[] = newArrangement
  this.bounds.changed.connectTo this: this.arrangement[] = newArrangement
  this.hAlign.changed.connectTo this: this.arrangement[] = newArrangement
  this.vAlign.changed.connectTo this: this.arrangement[] = newArrangement
  this.wrap.changed.connectTo this: this.arrangement[] = newArrangement


method draw*(text: UiText, ctx: DrawContext) =
  text.drawBefore(ctx)
  let pos =
    if text.roundPositionOnDraw[]:
      (text.xy[].posToGlobal(text.parent) + ctx.offset).round
    else:
      text.xy[].posToGlobal(text.parent) + ctx.offset

  if text.visibility[] == visible and text.tex != nil:
    ctx.drawIcon(pos, text.wh[], text.tex.raw, text.color.vec4, 0, true, text.angle)
  text.drawAfter(ctx)


method draw*(rect: UiRectBorder, ctx: DrawContext) =
  rect.drawBefore(ctx)
  if rect.visibility[] == visible:
    ctx.drawRectStroke((rect.xy[].posToGlobal(rect.parent) + ctx.offset).round, rect.wh[], rect.color.vec4, rect.radius, true, rect.angle, rect.borderWidth[], rect.tiled[], rect.tileSize[], rect.tileSecondSize[], rect.secondColor[].vec4)
  rect.drawAfter(ctx)


method draw*(rect: RectShadow, ctx: DrawContext) =
  rect.drawBefore(ctx)
  if rect.visibility[] == visible:
    ctx.drawShadowRect((rect.xy[].posToGlobal(rect.parent) + ctx.offset).round, rect.wh[], rect.color.vec4, rect.radius, true, rect.blurRadius, rect.angle)
  rect.drawAfter(ctx)


method draw*(this: ClipRect, ctx: DrawContext) =
  this.drawBefore(ctx)
  if this.visibility == visible:
    if this.w[] <= 0 or this.h[] <= 0: return
    if this.fbo == nil: this.fbo = newFrameBuffers(1)

    let size = ivec2(this.w[].round.int32, this.h[].round.int32)

    ctx.frameBufferHierarchy.add (this.fbo[0], size)
    glBindFramebuffer(GlFramebuffer, this.fbo[0])
    
    if this.prevSize != size or this.tex == nil:
      this.prevSize = size
      this.tex = newTexture()
      glBindTexture(GlTexture2d, this.tex.raw)
      glTexImage2D(GlTexture2d, 0, GlRgba.Glint, size.x, size.y, 0, GlRgba, GlUnsignedByte, nil)
      glTexParameteri(GlTexture2d, GlTextureMinFilter, GlNearest)
      glTexParameteri(GlTexture2d, GlTextureMagFilter, GlNearest)
      glFramebufferTexture2D(GlFramebuffer, GlColorAttachment0, GlTexture2d, this.tex.raw, 0)
    else:
      glBindTexture(GlTexture2d, this.tex.raw)
    
    glClearColor(0, 0, 0, 0)
    glClear(GlColorBufferBit)
    
    glViewport 0, 0, size.x.GLsizei, size.y.GLsizei
    ctx.updateDrawingAreaSize(size)

    let offset = block:
      var xy = this.xy[]
      var obj = this.parent
      while obj != nil and not(obj of ClipRect):
        xy.x += obj.x[]
        xy.y += obj.y[]
        obj = obj.parent
      xy
    ctx.offset -= offset
    try:
      this.drawBeforeChilds(ctx)
      this.drawChilds(ctx)
    
    finally:
      ctx.frameBufferHierarchy.del ctx.frameBufferHierarchy.high
      ctx.offset += offset

      glBindFramebuffer(GlFramebuffer, if ctx.frameBufferHierarchy.len == 0: 0.GlUint else: ctx.frameBufferHierarchy[^1].fbo)

      let size =
        if ctx.frameBufferHierarchy.len == 0:
          let win = this.parentWindow
          if win == nil: this.lastParent.wh[].ivec2 else: win.size
        else: ctx.frameBufferHierarchy[^1].size
      glViewport 0, 0, size.x.GLsizei, size.y.GLsizei
      ctx.updateDrawingAreaSize(size)
      
      ctx.drawImage((this.xy[].posToGlobal(this.parent) + ctx.offset).round, this.wh[], this.tex.raw, this.color.vec4, this.radius, true, this.angle, flipY=true)
  else:
    this.drawBeforeChilds(ctx)
    this.drawChilds(ctx)
  this.drawAfterLayer(ctx)


method draw*(win: UiWindow, ctx: DrawContext) =
  glClearColor(win.clearColor.r, win.clearColor.g, win.clearColor.b, win.clearColor.a)
  glClear(GlColorBufferBit or GlDepthBufferBit)
  win.drawBefore(ctx)
  win.drawAfter(ctx)


method recieve*(this: UiWindow, signal: Signal) =
  if signal of WindowEvent and signal.WindowEvent.event of ResizeEvent:
    let e = (ref ResizeEvent)signal.WindowEvent.event
    this.wh[] = e.size.vec2
    glViewport 0, 0, e.size.x.GLsizei, e.size.y.GLsizei
    this.ctx.updateDrawingAreaSize(e.size)

  elif signal of WindowEvent and signal.WindowEvent.event of RenderEvent:
    draw(this, this.ctx)

  elif signal of WindowEvent and signal.WindowEvent.event of StateBoolChangedEvent:
    redraw this.siwinWindow

  procCall this.super.recieve(signal)


proc setupEventsHandling*(win: UiWindow) =
  proc toRef[T](e: T): ref AnyWindowEvent =
    result = (ref T)()
    (ref T)(result)[] = e

  win.siwinWindow.eventsHandler = WindowEventsHandler(
    onClose:       proc(e: CloseEvent) = win.recieve(WindowEvent(sender: win, event: e.toRef)),
    onRender:      proc(e: RenderEvent) =
      win.recieve(WindowEvent(sender: win, event: e.toRef))
      
      var cursor = GetActiveCursor()
      win.recieve(cursor)
      if cursor.cursor == nil:
        win.siwinWindow.cursor = Cursor()
      else:
        win.siwinWindow.cursor = cursor.cursor[]
    ,
    onTick:        proc(e: TickEvent) = win.onTick.emit(e),
    onResize:      proc(e: ResizeEvent) = win.recieve(WindowEvent(sender: win, event: e.toRef)),
    onWindowMove:  proc(e: WindowMoveEvent) = win.recieve(WindowEvent(sender: win, event: e.toRef)),

    onStateBoolChanged:   proc(e: StateBoolChangedEvent) = win.recieve(WindowEvent(sender: win, event: e.toRef)),

    onMouseMove:    proc(e: MouseMoveEvent) =
      win.recieve(WindowEvent(sender: win, event: e.toRef))
    
      var cursor = GetActiveCursor()
      win.recieve(cursor)
      if cursor.cursor == nil:
        win.siwinWindow.cursor = Cursor()
      else:
        win.siwinWindow.cursor = cursor.cursor[]
    ,
    onMouseButton:  proc(e: MouseButtonEvent) = win.recieve(WindowEvent(sender: win, event: e.toRef)),
    onScroll:       proc(e: ScrollEvent) = win.recieve(WindowEvent(sender: win, event: e.toRef)),
    onClick:        proc(e: ClickEvent) = win.recieve(WindowEvent(sender: win, event: e.toRef)),

    onKey:   proc(e: KeyEvent) = win.recieve(WindowEvent(sender: win, event: e.toRef)),
    onTextInput:  proc(e: TextInputEvent) = win.recieve(WindowEvent(sender: win, event: e.toRef)),
  )

proc newUiWindow*(siwinWindow: Window): UiWindow =
  result = UiWindow(siwinWindow: siwinWindow)
  loadExtensions()
  result.setupEventsHandling
  result.ctx = newDrawContext()


method addChild*(this: UiWindow, child: Uiobj) =
  procCall this.super.addChild(child)
  child.recieve(AttachedToWindow(window: this))
        


proc newUiobj*(): Uiobj = new result
proc newUiWindow*(): UiWindow = new result
proc newUiImage*(): UiImage = new result
proc newUiIcon*(): UiImage {.deprecated: "use UiImage with .colorOverlay[]=true instead".} =
  new result
  result.colorOverlay[] = true
proc newUiSvgImage*(): UiSvgImage = new result
proc newUiText*(): UiText = new result
proc newUiRect*(): UiRect = new result
proc newUiRectStroke*(): UiRectBorder {.deprecated: "renamed to newUiRectBorder".} = new result
proc newUiRectBorder*(): UiRectBorder = new result
proc newClipRect*(): ClipRect = new result
proc newRectShadow*(): RectShadow = new result


#----- Macros -----



proc bindingImpl*(obj: NimNode, target: NimNode, body: NimNode, afterUpdate: NimNode, init: bool, kind: BindingKind): NimNode =
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
  ## convers to (roughly):
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
    case body
    of in alreadyBinded: return
    of Call[Sym(strVal: "[]"), @exp]:
      stmts.add: buildAst(call):
        ident "connectTo"
        dotExpr(exp, ident "changed")
        objCursor
        call updateProc:
          objCursor
      alreadyBinded.add body
      impl(stmts, exp)

    else:
      for x in body: impl(stmts, x)
  
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
              body
          of bindValue:
            asgn:
              target
              body
          of bindProc:
            call:
              target
              thisInProc
              body
          
          case afterUpdate
          of Call[Sym(strVal: "newStmtList"), HiddenStdConv[Empty(), Bracket()]]: discard
          else: afterUpdate
      
      var stmts: seq[NimNode]
      (impl(stmts, body))
      for x in stmts: x

      if init:
        call updateProc, objCursor


macro binding*(obj: EventHandler, target: untyped, body: typed, afterUpdate: typed = newStmtList(), init: static bool = true): untyped =
  bindingImpl(obj, target, body, afterUpdate, init, bindProperty)

macro bindingValue*(obj: EventHandler, target: untyped, body: typed, afterUpdate: typed = newStmtList(), init: static bool = true): untyped =
  bindingImpl(obj, target, body, afterUpdate, init, bindValue)

macro bindingProc*(obj: EventHandler, target: untyped, body: typed, afterUpdate: typed = newStmtList(), init: static bool = true): untyped =
  bindingImpl(obj, target, body, afterUpdate, init, bindProc)


macro binding*[T: HasEventHandler](obj: T, target: untyped, body: typed, afterUpdate: typed = newStmtList(), init: static bool = true): untyped =
  bindingImpl(obj, target, body, afterUpdate, init, bindProperty)

macro bindingValue*[T: HasEventHandler](obj: T, target: untyped, body: typed, afterUpdate: typed = newStmtList(), init: static bool = true): untyped =
  bindingImpl(obj, target, body, afterUpdate, init, bindValue)

macro bindingProc*[T: HasEventHandler](obj: T, target: untyped, body: typed, afterUpdate: typed = newStmtList(), init: static bool = true): untyped =
  bindingImpl(obj, target, body, afterUpdate, init, bindProc)


macro binding*(obj: EventHandler, target: untyped, body: typed, afterUpdate: typed = newStmtList(), redraw: static bool, init: static bool = true): untyped {.deprecated: "there is no more need to manually call redraw".} =
  bindingImpl(obj, target, body, afterUpdate, init, bindProperty)

macro bindingValue*(obj: EventHandler, target: untyped, body: typed, afterUpdate: typed = newStmtList(), redraw: static bool, init: static bool = true): untyped {.deprecated: "there is no more need to manually call redraw".} =
  bindingImpl(obj, target, body, afterUpdate, init, bindValue)

macro bindingProc*(obj: EventHandler, target: untyped, body: typed, afterUpdate: typed = newStmtList(), redraw: static bool, init: static bool = true): untyped {.deprecated: "there is no more need to manually call redraw".} =
  bindingImpl(obj, target, body, afterUpdate, init, bindProc)


macro binding*[T: HasEventHandler](obj: T, target: untyped, body: typed, afterUpdate: typed = newStmtList(), redraw: static bool, init: static bool = true): untyped {.deprecated: "there is no more need to manually call redraw".} =
  bindingImpl(obj, target, body, afterUpdate, init, bindProperty)

macro bindingValue*[T: HasEventHandler](obj: T, target: untyped, body: typed, afterUpdate: typed = newStmtList(), redraw: static bool, init: static bool = true): untyped {.deprecated: "there is no more need to manually call redraw".} =
  bindingImpl(obj, target, body, afterUpdate, init, bindValue)

macro bindingProc*[T: HasEventHandler](obj: T, target: untyped, body: typed, afterUpdate: typed = newStmtList(), redraw: static bool, init: static bool = true): untyped {.deprecated: "there is no more need to manually call redraw".} =
  bindingImpl(obj, target, body, afterUpdate, init, bindProc)



macro makeLayout*(obj: Uiobj, body: untyped) =
  ## tip: use a.makeLauyout(-soMeFuN()) instead of (let b = soMeFuN(); a.addChild(b); init b)
  runnableExamples:
    let a = UiRect()
    let b = UiRect()
    let c = UiRect()
    var ooo: CustomProperty[UiRect]
    a.makeLayout:
      - RectShadow(radius: 7.5'f32.property, blurRadius: 10'f32.property, color: color(0, 0, 0, 0.3).property) as shadowEffect

      - newUiRect():
        this.fill(parent)
        echo shadowEffect.radius
        doassert parent.Uiobj == this.parent

        - ClipRect():
          this.radius[] = 7.5
          this.fill(parent, 10)
          doassert root.Uiobj == this.parent.parent

          ooo --- UiRect():  # add changable child
            this.fill(parent)

          - b
          - UiRect()

      - c:
        this.fill(parent)


  proc implFwd(body: NimNode, res: var seq[NimNode]) =
    for x in body:
      case x
      of Prefix[Ident(strVal: "-"), @ctor]:
        discard

      of Prefix[Ident(strVal: "-"), @ctor, @body is StmtList()]:
        implFwd(body, res)

      of Infix[Ident(strVal: "as"), Prefix[Ident(strVal: "-"), @ctor], @s]:
        res.add: buildAst:
          identDefs(s, empty(), ctor)

      of Infix[Ident(strVal: "as"), Prefix[Ident(strVal: "-"), @ctor], @s, @body is StmtList()]:
        res.add: buildAst:
          identDefs(s, empty(), ctor)
        implFwd(body, res)

      else: discard

  proc impl(parent: NimNode, obj: NimNode, body: NimNode): NimNode =
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
            
            proc checkCtor(ctor: NimNode): bool =
              if ctor == ident "root": warning("adding root to itself causes recursion", ctor)
              if ctor == ident "this": warning("adding this to itself causes recursion", ctor)
              if ctor == ident "parent": warning("adding parent to itself causes recursion", ctor)

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
                        if body != nil: impl(ident"parent", ident"this", body)

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


            for x in body:
              case x
              of Prefix[Ident(strVal: "-"), @ctor]:
                discard checkCtor ctor
                let s = genSym(nskLet)
                letSection:
                  identDefs(s, empty(), ctor)
                call(ident"addChild", ident "this", s)
                call(ident"initIfNeeded", s)

              of Prefix[Ident(strVal: "-"), @ctor, @body is StmtList()]:
                discard checkCtor ctor
                let s = genSym(nskLet)
                letSection:
                  identDefs(s, empty(), ctor)
                call(ident"addChild", ident "this", s)
                impl(ident "this", s, body)

              of Infix[Ident(strVal: "as"), Prefix[Ident(strVal: "-"), @ctor], @s]:
                discard checkCtor ctor
                call(ident"addChild", ident "this", s)
                call(ident"initIfNeeded", s)

              of Infix[Ident(strVal: "as"), Prefix[Ident(strVal: "-"), @ctor], @s, @body is StmtList()]:
                discard checkCtor ctor
                call(ident"addChild", ident "this", s)
                impl(ident "this", s, body)

              of Infix[Ident(strVal: "---"), @to, @ctor]:
                changableImpl(to, ctor, nil)

              of Infix[Ident(strVal: "---"), @to, @ctor, @body is StmtList()]:
                changableImpl(to, ctor, body)
              
              of
                Infix[Ident(strVal: ":="), @name, @val],
                Asgn[@name is Ident(), Command[Ident(strVal: "binding"), @val]],
                Asgn[@name is Ident(), Call[Ident(strVal: "binding"), @val]]:

                whenStmt:
                  elifBranch:
                    call bindSym"compiles":
                      call ident"[]=":
                        dotExpr(ident "this", name)
                        val
                    call bindSym"bindingValue":
                      ident "this"
                      bracketExpr:
                        dotExpr(ident "this", name)
                      val
                  Else:
                    call bindSym"bindingValue":
                      ident "this"
                      name
                      val
              
              of Asgn[@name is Ident(), @val]:
                whenStmt:
                  elifBranch:
                    call bindSym"compiles":
                      call ident"[]=":
                        dotExpr(ident "this", name)
                        val
                    call ident"[]=":
                      dotExpr(ident "this", name)
                      val
                  elifBranch:
                    call bindSym"compiles":
                      call ident($name & "="):
                        ident "this"
                        val
                    call ident($name & "="):
                      ident "this"
                      val
                  Else: asgn(name, val)
              
              of ForStmt():
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
                          impl(ident "parent", ident "this", x[^1])
                    
                    for param in x[0..^3]:
                      param
              
              of IfStmt[all @branches]:
                ifStmt:
                  for x in branches:
                    x[^1] = buildAst:
                      stmtList:
                        letSection:
                          var fwd: seq[NimNode]
                          (implFwd(x[^1], fwd))
                          for x in fwd: x
                        impl(ident "parent", ident "this", x[^1])
                    x

              else: x
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
      
      impl(nnkDotExpr.newTree(ident "root", ident "parent"), ident "root", if body.kind == nnkStmtList: body else: newStmtList(body))


proc withSize*(typeface: Typeface, size: float): Font =
  result = newFont(typeface)
  result.size = size


template withWindow*(obj: UiObj, winVar: untyped, body: untyped) =
  proc bodyProc(winVar {.inject.}: UiWindow) =
    body
  if obj.attachedToWindow:
    bodyProc(obj.parentUiWindow)
  obj.onSignal.connect obj.eventHandler, proc(e: Signal) =
    if e of AttachedToWindow:
      bodyProc(obj.parentUiWindow)


proc preview*(size = ivec2(), clearColor = color(0, 0, 0, 0), margin = 10'f32, transparent = false, withWindow: proc(): Uiobj) =
  let win = newOpenglWindow(
    size =
      if size != ivec2(): size
      else: ivec2(100, 100),
    transparent = transparent
  ).newUiWindow
  let obj = withWindow()

  if size == ivec2() and obj.wh[] != vec2():
    win.siwinWindow.size = (obj.wh[] + margin * 2).ivec2

  win.clearColor = clearColor
  win.makeLayout:
    - obj:
      this.fill(parent, margin)
  
  run win.siwinWindow


proc invokeReflection(refl: NimNode, filter: NimNode, t: NimNode): NimNode =
  proc replaceTree(x, a, to: NimNode): NimNode =
    if x == a: return to
    else:
      result = copy x
      for i, x in result:
        result[i] = replaceTree(x, a, to)

  buildAst:
    whenStmt:
      elifBranch:
        filter.replaceTree(ident"T", t).replaceTree(ident"t", newLit t.repr)
        stmtList:
          call(refl, t)


macro registerComponent*(t: type) =
  registredComponents.add t
  result = buildAst(stmtList):
    for x in registredReflection:
      invokeReflection(x.f, x.filter, t)


macro registerReflection*(x: typed, filter: untyped = true) =
  registredReflection.add (x, filter)
  result = buildAst(stmtList):
    for t in registredComponents:
      invokeReflection(x, filter, t)


registerComponent Uiobj
registerComponent UiWindow
registerComponent UiRect
registerComponent UiImage
registerComponent UiSvgImage
registerComponent UiRectBorder
registerComponent RectShadow
registerComponent ClipRect
registerComponent UiText


macro generateDeteachMethod(t: typed) =
  nnkMethodDef.newTree(
    nnkPostfix.newTree(
      ident("*"),
      ident("deteach")
    ),
    newEmptyNode(),
    newEmptyNode(),
    nnkFormalParams.newTree(
      newEmptyNode(),
      nnkIdentDefs.newTree(
        ident("this"),
        t,
        newEmptyNode()
      )
    ),
    newEmptyNode(),
    newEmptyNode(),
    nnkStmtList.newTree(
      nnkCall.newTree(
        bindSym("deteachStatic"),
        ident("this")
      )
    )
  )

registerReflection generateDeteachMethod, T is Uiobj and t != "Uiobj"


macro generateInitRedrawWhenPropertyChangedMethod(t: typed) =
  nnkMethodDef.newTree(
    nnkPostfix.newTree(
      ident("*"),
      ident("initRedrawWhenPropertyChanged")
    ),
    newEmptyNode(),
    newEmptyNode(),
    nnkFormalParams.newTree(
      newEmptyNode(),
      nnkIdentDefs.newTree(
        ident("this"),
        t,
        newEmptyNode()
      )
    ),
    newEmptyNode(),
    newEmptyNode(),
    nnkStmtList.newTree(
      nnkCall.newTree(
        bindSym("initRedrawWhenPropertyChangedStatic"),
        ident("this")
      )
    )
  )

registerReflection generateInitRedrawWhenPropertyChangedMethod, T is Uiobj and t != "Uiobj"


converter toColor*(s: string{lit}): chroma.Color =
  case s.len
  of 3:
    result = chroma.Color(
      r: ($s[0]).parseHexInt.float32 / 15.0,
      g: ($s[1]).parseHexInt.float32 / 15.0,
      b: ($s[2]).parseHexInt.float32 / 15.0,
      a: 1,
    )
  of 4:
    result = chroma.Color(
      r: ($s[0]).parseHexInt.float32 / 15.0,
      g: ($s[1]).parseHexInt.float32 / 15.0,
      b: ($s[2]).parseHexInt.float32 / 15.0,
      a: ($s[3]).parseHexInt.float32 / 15.0,
    )
  of 6:
    result = chroma.Color(
      r: (s[0..1].parseHexInt.float32) / 255.0,
      g: (s[2..3].parseHexInt.float32) / 255.0,
      b: (s[4..5].parseHexInt.float32) / 255.0,
      a: 1,
    )
  of 8:
    result = chroma.Color(
      r: (s[0..1].parseHexInt.float32) / 255.0,
      g: (s[2..3].parseHexInt.float32) / 255.0,
      b: (s[4..5].parseHexInt.float32) / 255.0,
      a: (s[6..7].parseHexInt.float32) / 255.0,
    )
  else:
    raise ValueError.newException("invalid color: " & s)

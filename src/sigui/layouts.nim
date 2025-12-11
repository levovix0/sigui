import std/[sequtils, importutils]
import pkg/[vmath]
import ./[uiobj {.all.}, properties, events]
import ./render/[contexts]

type
  LayoutOrientation* = enum
    horizontal
    vertical

  LayoutAlignment* = enum
    start
    center
    `end`

  Layout* = ref object of Uiobj
    orientation*: Property[LayoutOrientation]

    hugContent*: Property[bool] = true.property
    wrapHugContent*: Property[bool] = true.property
    
    align*: Property[LayoutAlignment]
      ## the baseline for aligning each individual element, can be replaced for with InLayout.align
    fillContainer*: Property[bool]
      ## if true, all elements will have same size on second axis (width for vertical layout, height for horizontal layout)

    alignContent*, wrapAlignContent*: Property[LayoutAlignment]
      ## align whole content of layout in main/wrap axis of layout (when layout is not hugging it's contents)
      ## can be thought like a justify property in css

    gap*, wrapGap*: Property[float32]
    fillWithSpaces*, wrapFillWithSpaces*: Property[bool]
    consistentSpacing*: Property[bool]
      ## if true, last wrapped row will have same spacing as previous row
    
    wrap*: Property[bool]
      ## become "grid"
    elementsBeforeWrap*: Property[int]
    lengthBeforeWrap*: Property[float32]

    assumeChildsClipped*: Property[bool] = true.property
      ## for optimization, if true, assume for all children, that every child's tree is contained in that child (xy >= 0, wh <= parent wh)

    padding*: Property[SideOffsets]

    lockFromReposition: bool = true
    inRepositionProcess: bool
  

  InLayout* = ref object of Uiobj
    align*: Property[LayoutAlignment]
    fillContainer*: Property[bool]
    grow*: Property[int]
      ## if >0, element will grow on main axis (width for horizontal layout, height for vertical layout)
      ## if more than one element has grow >0, they will share free space, proportionally to their grow value
    minSize*: Property[float32]
      ## if grow >0, element will not be smaller than this value on main axis (width for horizontal layout, height for vertical layout)
      ## if 0, this constraint don't apply
    maxSize*: Property[float32]
      ## if grow >0, element will not be bigger than this value on main axis (width for horizontal layout, height for vertical layout)
      ## if 0, this constraint don't apply
    
    isChangingW, isChangingH: bool
  
  LayoutGap* = ref object of Uiobj
    ## component that replaces gap in Layout



registerComponent Layout
registerComponent InLayout
registerComponent LayoutGap

proc reposition(this: Layout)


iterator potentially_visible_childs*(this: Layout): Uiobj =
  block notOptimized:
    block optimized:
      if this.lengthBeforeWrap[] == 0 and this.elementsBeforeWrap[] == 0 and this.assumeChildsClipped[]:
        let win = this.parentUiRoot
        if win != nil:
          let boundsXy = vec2(0, 0)
          let boundsWh = win.wh

          case this.orientation[]
          of horizontal:
            for child in this.childs:
              if child.globalX[] + child.w[] < boundsXy.x:
                continue
              if child.globalX > boundsXy.x + boundsWh.x:
                break
              yield child

          of vertical:
            for child in this.childs:
              if child.globalY[] + child.h[] < boundsXy.y:
                continue
              if child.globalY > boundsXy.y + boundsWh.y:
                break
              yield child

        else: break optimized
      else: break optimized
      break notOptimized
    
    for child in this.childs:
      yield child


method draw*(obj: Layout, ctx: DrawContext) =
  privateAccess Uiobj
  privateAccess DrawLayering
  privateAccess DrawLayer
  privateAccess UiobjCursor

  for x in obj.drawLayering.before:
    draw(x.obj, ctx)
  for x in obj.drawLayering.beforeChilds:
    draw(x.obj, ctx)
  
  if obj.visibility notin {hiddenTree, collapsed}:
    for child in obj.potentially_visible_childs:
      if child.m_drawLayer.obj == nil:
        draw(child, ctx)

  for x in obj.drawLayering.after:
    draw(x.obj, ctx)



method recieve*(this: Layout, signal: Signal) =
  if signal of AttachedToRoot:
    this.root = signal.AttachedToRoot.root

  if signal of Completed:
    if this.lockFromReposition:
      this.lockFromReposition = false
      reposition(this)
  
  if signal of WindowEvent:
    if this.lockFromReposition:  # this may happen if Layout was not created inside makeLayout. better late than never
      this.lockFromReposition = false
      reposition(this)
  
  if signal of ChildRemoved:
    if signal.ChildRemoved.child.parent == this:
      disconnect(signal.ChildRemoved.child.w.changed, this.eventHandler)
      disconnect(signal.ChildRemoved.child.h.changed, this.eventHandler)

  this.onSignal.emit signal

  if signal of SubtreeSignal:
    for x in this.potentially_visible_childs:
      x.recieve(signal)
  
  if signal of UptreeSignal:
    if this.parent != nil:
      this.parent.recieve(signal)



proc doReposition(this: Layout) =
  template makeGetAndSet(get, set, horz, vert, paddingHorz, paddingVert) =
    proc get(child: Uiobj): float32 =
      case this.orientation[]
      of horizontal: child.horz[] - paddingHorz
      of vertical: child.vert[] - paddingVert

    proc set(child: Uiobj, v: float32) =
      case this.orientation[]
      of horizontal: child.horz[] = v + paddingHorz
      of vertical: child.vert[] = v + paddingVert

  makeGetAndSet(get_x, set_x, x, y, this.padding[].left, this.padding[].top)
  makeGetAndSet(get_y, set_y, y, x, this.padding[].top, this.padding[].left)
  makeGetAndSet(get_w, set_w, w, h, 0, 0)
  makeGetAndSet(get_h, set_h, h, w, 0, 0)
  makeGetAndSet(get_this_w, set_this_w, w, h, this.padding[].left + this.padding[].right, this.padding[].top + this.padding[].bottom)
  makeGetAndSet(get_this_h, set_this_h, h, w, this.padding[].top + this.padding[].bottom, this.padding[].left + this.padding[].right)

  var rows: seq[tuple[childs: seq[Uiobj]; freeSpace, spaceBetween, h: float32]] =
    @[(@[], this.get_this_w, 0'f32, 0'f32)]

  block:
    var
      i = 0
      x = 0'f32
      h = 0'f32
      shouldMakeGap = false

    for child in this.childs:
      if child.visibility == collapsed: continue
      if shouldMakeGap and not(child of LayoutGap):
        x += this.gap[]
        rows[^1].freeSpace -= this.gap[]

      x += child.get_w
      inc i

      if (
        this.wrap[] and
        (
          (this.elementsBeforeWrap[] > 0 and i > this.elementsBeforeWrap[]) or
          (this.lengthBeforeWrap[] > 0 and x > this.lengthBeforeWrap[])
        )
      ):
        if shouldMakeGap and not(child of LayoutGap):
          rows[^1].freeSpace += this.gap[]
        rows[^1].h = h
        i = 1
        x = child.get_w
        h = 0
        rows.add (@[], this.get_this_w, 0'f32, 0'f32)
      
      rows[^1].childs.add child
      if not(child of InLayout and child.InLayout.fillContainer[]):
        h = max(h, child.get_h)
      rows[^1].freeSpace -= child.get_w

      shouldMakeGap = not(child of LayoutGap)
    
    if not this.wrapHugContent[]:
      h = this.get_this_h
    
    rows[^1].h = h
  
  
  for x in rows.mitems:
    var elementCount = 0
    for child in x.childs:
      if not(child of LayoutGap):
        inc elementCount

    x.spaceBetween =
      if elementCount > 1: x.freeSpace / (elementCount - 1).float32
      else: 0
    
    let growSpace =
      if x.childs.len > 1: x.spaceBetween - this.gap[]
      elif x.childs.len > 0: this.get_this_w - x.childs[0].get_w
      else: 0
    
    if growSpace > 0:
      var totalGrow = 0
      for child in x.childs:
        if child of InLayout and child.InLayout.grow[] > 0:
          totalGrow += child.InLayout.grow[]
      
      if totalGrow > 0:
        if this.childs.len > 1:
          x.spaceBetween = this.gap[]
        x.freeSpace = this.gap[] * (elementCount - 1).float32

        var growSpaceTaken = 0
        var lastGrowingChild: Uiobj

        for child in x.childs:
          if child of InLayout and child.InLayout.grow[] > 0:
            let grow = child.InLayout.grow[]
            let growAmmount = (growSpace * (grow / totalGrow)).int
            child.set_w(child.get_w + growAmmount.float32)
            growSpaceTaken += growAmmount
            lastGrowingChild = child

        lastGrowingChild.set_w(lastGrowingChild.get_w + growSpace - growSpaceTaken.float32)

  if this.consistentSpacing[] and rows.len > 1:
    rows[^1].spaceBetween = rows[^2].spaceBetween

  block:
    let freeYSpace =
      if this.wrapFillWithSpaces[]: rows.mapit(it.h).foldl(a + this.wrapGap[] + b)
      else: 0'f32

    var y =
      if this.wrapfillWithSpaces[]: 0'f32
      else:
        case this.wrapAlignContent[]
        of start: 0'f32
        of center: freeYSpace / 2
        of `end`: freeYSpace
    
    for (row, freeSpace, spaceBetween, h) in rows:
      var
        x =
          if this.fillWithSpaces[]: 0'f32
          else:
            case this.alignContent[]
            of start: 0'f32
            of center: freeSpace / 2
            of `end`: freeSpace
        shouldMakeGap = false

      let spaceBetween =
        if this.fillWithSpaces[]: spaceBetween
        else: 0'f32
      
      for childI, child in row:
        if shouldMakeGap and not(child of LayoutGap):
          x += this.gap[] + spaceBetween

        child.set_x(x)
        
        let fillContainer =
          if child of InLayout: child.InLayout.fillContainer[]
          else: this.fillContainer[]
        
        let align =
          if child of InLayout: child.InLayout.align[]
          else: this.align[]
        
        if fillContainer:
          if child of InLayout:
            for child in child.childs:
              child.set_h(this.get_this_h)
          else:
            child.set_h(this.get_this_h)

          child.set_y(0)

        else:
          case align
          of start:
            child.set_y(y)
          of center:
            child.set_y(y + h / 2 - child.get_h / 2)
          of `end`:
            child.set_y(y + h - child.get_h)
        
        x += child.get_w

        shouldMakeGap = not(child of LayoutGap)
      
      y += h + this.wrapGap[] + (if rows.len > 1: freeYSpace / (rows.len.float32 - 1) else: 0)
  
  if this.hugContent[]:
    if this.childs.len > 0:
      var maxX = 0'f32
      for row in rows:
        maxX = max(maxX, row.childs[^1].get_x + row.childs[^1].get_w)
      this.set_this_w(maxX)
    else:
      discard

  if this.wrapHugContent[]:
    if this.childs.len > 0:
      var maxY = 0'f32
      for row in rows:
        maxY = max(maxY, row.childs[^1].get_y + row.childs[^1].get_h)
      this.set_this_h(maxY)
    else:
      discard



proc reposition(this: Layout) =
  # todo: somehow detect situation when children's h is dependant on layout's h, but wrapHugContent is enabled, throw an exception to tell usercode to disable wrapHugContent. or adapt.
  if this.lockFromReposition: return
  if this.inRepositionProcess: return

  this.inRepositionProcess = true
  try:
    this.doReposition()
  finally:
    this.inRepositionProcess = false


template spacing*(this: Layout): Property[float32] = this.gap
template wrapSpacing*(this: Layout): Property[float32] = this.wrapGap
template alignment*(this: Layout): Property[LayoutAlignment] = this.align
template justify*(this: Layout): Property[LayoutAlignment] = this.wrapAlign
template justifyContent*(this: Layout): Property[LayoutAlignment] = this.wrapAlignContent

template alignment*(this: InLayout): Property[LayoutAlignment] = this.align


method addChild*(this: Layout, child: Uiobj) =
  if this.newChildsObject != nil:
    this.newChildsObject.addChild(child)
    return
  
  procCall this.super.addChild(child)
  
  child.w.changed.connectTo this: reposition(this)
  child.h.changed.connectTo this: reposition(this)

  if child of InLayout:
    child.InLayout.align.changed.connectTo this: reposition(this)
    child.InLayout.fillContainer.changed.connectTo this: reposition(this)
    child.InLayout.grow.changed.connectTo this: reposition(this)
    child.InLayout.minSize.changed.connectTo this: reposition(this)
    child.InLayout.maxSize.changed.connectTo this: reposition(this)
  
  reposition(this)


method addChild*(this: InLayout, child: Uiobj) =
  if this.newChildsObject != nil:
    this.newChildsObject.addChild(child)
    return

  procCall this.super.addChild(child)
  
  child.w.changed.connectTo this:
    if not this.isChangingW:
      this.isChangingW = true
      this.w[] = child.w[]
      this.isChangingW = false
  this.w[] = child.w[]
  
  child.h.changed.connectTo this:
    if not this.isChangingH:
      this.isChangingH = true
      this.h[] = child.h[]
      this.isChangingH = false
  this.w[] = child.w[]


method init*(this: Layout) =
  if this.initialized: return
  procCall this.super.init

  template doRepositionWhenChanged(prop) =
    this.prop.changed.connectTo this: reposition(this)

  doRepositionWhenChanged w
  doRepositionWhenChanged h
  
  doRepositionWhenChanged hugContent
  doRepositionWhenChanged wrapHugContent
  
  doRepositionWhenChanged align
  doRepositionWhenChanged fillContainer

  doRepositionWhenChanged alignContent
  doRepositionWhenChanged wrapAlignContent

  doRepositionWhenChanged gap
  doRepositionWhenChanged wrapGap
  doRepositionWhenChanged fillWithSpaces
  doRepositionWhenChanged wrapFillWithSpaces
  doRepositionWhenChanged consistentSpacing
  
  doRepositionWhenChanged wrap
  doRepositionWhenChanged elementsBeforeWrap
  doRepositionWhenChanged lengthBeforeWrap
  
  doRepositionWhenChanged padding



proc row*(this: Layout, gap: float32 = 0) =
  ## horizontal layout, size of which depends of clidren
  this.gap{} = gap
  this.orientation{} = LayoutOrientation.horizontal

proc col*(this: Layout, gap: float32 = 0) =
  ## vertical layout, size of which depends of clidren
  this.gap{} = gap
  this.orientation{} = LayoutOrientation.vertical


proc hbox*(this: Layout, gap: float32 = 0, fillWithSpaces: bool = false) =
  ## horizontal layout, size of which is fixed
  this.gap{} = gap
  this.orientation{} = LayoutOrientation.horizontal
  this.hugContent{} = false
  this.fillWithSpaces{} = fillWithSpaces

proc vbox*(this: Layout, gap: float32 = 0, fillWithSpaces: bool = false) =
  ## vertical layout, size of which is fixed
  this.gap{} = gap
  this.orientation{} = LayoutOrientation.vertical
  this.hugContent{} = false
  this.fillWithSpaces{} = fillWithSpaces


proc grid*(this: Layout, columns: int, gap: float32 = 0) =
  ## horizontal + vertical when overflow layout, size of which depends of clidren
  this.gap{} = gap
  this.orientation{} = LayoutOrientation.horizontal
  this.wrap{} = true
  this.elementsBeforeWrap{} = columns



proc row*(typ: typedesc[Layout], gap: float32 = 0): Layout =
  new result
  result.row(gap)

proc col*(typ: typedesc[Layout], gap: float32 = 0): Layout =
  new result
  result.col(gap)


proc hbox*(typ: typedesc[Layout], gap: float32 = 0, fillWithSpaces: bool = false): Layout =
  new result
  result.hbox(gap, fillWithSpaces)

proc vbox*(typ: typedesc[Layout], gap: float32 = 0, fillWithSpaces: bool = false): Layout =
  new result
  result.vbox(gap, fillWithSpaces)


proc grid*(typ: typedesc[Layout], columns: int, gap: float32 = 0): Layout =
  new result
  result.grid(columns, gap)



when isMainModule:
  import ./uibase

  let win = newUiWindow(size = ivec2(600, 700))

  win.makeLayout:
    this.clearColor = "202020".color

    - Layout.col(gap = 25):  # positions elements vertically with gap between them, use Layout.row() for horizontal
      - UiRect.new:
        w = 200
        h = 200
        color = "ff4040".color

      - UiRect.new:
        w = 300
        h = 100
        color = "40ff40".color

      - UiRect.new:
        w = 100
        h = 300
        color = "4040ff".color
      
      echo "w: ", this.w[], ", h: ", this.h[]  # already non-zero!
  
  run win

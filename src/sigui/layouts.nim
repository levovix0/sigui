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
    fillContainer*: Property[bool]
      ## if true, all elements will have same size on second axis (width for vertical layout, height for horizontal layout)

    alignContent*, wrapAlignContent*: Property[LayoutAlignment]

    gap*, wrapGap*: Property[float32]
    fillWithSpaces*, wrapFillWithSpaces*: Property[bool]
    consistentSpacing*: Property[bool]
      ## if true, last wrapped row will have same spacing as previous row
    
    wrap*: Property[bool]
      ## become "grid"
    elementsBeforeWrap*: Property[int]
    lengthBeforeWrap*: Property[float32]

    assumeChildsClipped*: Property[bool] = true.property
      ## for optimization, if true, assume for all children, that child's tree are contained in that child (xy >= 0, wh <= parent wh)

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

registerComponent Layout
registerComponent InLayout


iterator potentially_visible_childs*(this: Layout): Uiobj =
  block notOptimized:
    block optimized:
      if this.lengthBeforeWrap[] == 0 and this.elementsBeforeWrap[] == 0 and this.assumeChildsClipped[]:
        let win = this.parentUiWindow
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



method recieve*(obj: Layout, signal: Signal) =
  if signal of AttachedToWindow:
    obj.attachedToWindow = true

  obj.onSignal.emit signal

  if signal of SubtreeSignal:
    for x in obj.potentially_visible_childs:
      x.recieve(signal)
  
  if signal of UptreeSignal:
    if obj.parent != nil:
      obj.parent.recieve(signal)



proc reposition_old(this: Layout) {.used.} =
  if this.inRepositionProcess: return
  this.inRepositionProcess = true
  defer: this.inRepositionProcess = false

  template makeGetAndSet(get, set, horz, vert) =
    proc get(child: Uiobj): float32 =
      case this.orientation[]
      of horizontal: child.horz[]
      of vertical: child.vert[]

    proc set(child: Uiobj, v: float32) =
      case this.orientation[]
      of horizontal: child.horz[] = v
      of vertical: child.vert[] = v

  makeGetAndSet(get_x, set_x, x, y)
  makeGetAndSet(get_y, set_y, y, x)
  makeGetAndSet(get_w, set_w, w, h)
  makeGetAndSet(get_h, set_h, h, w)

  var rows: seq[tuple[childs: seq[Uiobj]; freeSpace, spaceBetween, h: float32]] = @[(@[], this.get_w, 0'f32, 0'f32)]

  block:
    var
      i = 0
      x = 0'f32
      h = 0'f32

    for child in this.childs:
      if child.visibility == collapsed: continue
      if x != 0:
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
        rows[^1].freeSpace += this.gap[]
        rows[^1].h = h
        i = 1
        x = child.get_w
        h = 0
        rows.add (@[], this.get_w, 0'f32, 0'f32)
      
      rows[^1].childs.add child
      if not(child of InLayout) or not(child.InLayout.fillContainer[]):
        h = max(h, child.get_h)
      rows[^1].freeSpace -= child.get_w
    
    if not this.wrapHugContent[]:
      h = this.get_h
    
    rows[^1].h = h
  
  
  for x in rows.mitems:
    x.spaceBetween =
      if x.childs.len > 1: x.freeSpace / (x.childs.len - 1).float32
      else: 0
    
    let growSpace =
      if x.childs.len > 1: x.spaceBetween - this.gap[]
      elif x.childs.len > 0: this.get_w - x.childs[0].get_w
      else: 0
    
    if growSpace > 0:
      var totalGrow = 0
      for child in x.childs:
        if child of InLayout and child.InLayout.grow[] > 0:
          totalGrow += child.InLayout.grow[]
      
      if totalGrow > 0:
        if this.childs.len > 1:
          x.spaceBetween = this.gap[]
        x.freeSpace = this.gap[] * (x.childs.len - 1).float32

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

      let spaceBetween =
        if this.fillWithSpaces[]: spaceBetween
        else: 0'f32
      
      for child in row:
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
              child.set_h(this.get_h)
          else:
            child.set_h(this.get_h)

          child.set_y(0)

        else:
          case align
          of start:
            child.set_y(y)
          of center:
            child.set_y(y + h / 2 - child.get_h / 2)
          of `end`:
            child.set_y(y + h - child.get_h)
        
        x += child.get_w + this.gap[] + spaceBetween
      
      y += h + this.wrapGap[] + (if rows.len > 1: freeYSpace / (rows.len.float32 - 1) else: 0)
  
  if this.hugContent[]:
    if this.childs.len > 0:
      this.set_w(rows.mapit(it.childs[^1].get_x + it.childs[^1].get_w).foldl(max(a, b), 0'f32))
    else:
      this.set_w(0)

  if this.wrapHugContent[]:
    if this.childs.len > 0:
      this.set_h(rows[^1].childs.mapit(it.get_y + it.get_h).foldl(max(a, b), 0'f32))
    else:
      this.set_h(0)


proc doReposition(this: Layout) =
  template makeGetAndSet(get, set, horz, vert) =
    proc get(child: Uiobj): float32 =
      case this.orientation[]
      of horizontal: child.horz[]
      of vertical: child.vert[]

    proc set(child: Uiobj, v: float32) =
      case this.orientation[]
      of horizontal: child.horz[] = v
      of vertical: child.vert[] = v

  makeGetAndSet(get_x, set_x, x, y)
  makeGetAndSet(get_y, set_y, y, x)
  makeGetAndSet(get_w, set_w, w, h)
  makeGetAndSet(get_h, set_h, h, w)

  var rows: seq[tuple[
    elements: seq[Uiobj],
    height: float32,
  ]]

  block split_into_rows:
    rows.setLen 1

    var count_elements = 0
    var count_width = 0'f32

    if not this.wrap[] or (this.elementsBeforeWrap[] == 0 and this.lengthBeforeWrap[] == 0):
      rows[0].elements.add this.childs
      break split_into_rows

    for child in this.childs:
      if child.visibility[] == collapsed: continue

      let w =
        if child of InLayout and child.InLayout.grow[] > 0:
          if child.InLayout.minSize[] != 0:
            child.InLayout.minSize[]
          else:
            0
        else:
          child.get_w

      inc count_elements
      count_width += w

      var do_wrap = false
      
      if this.elementsBeforeWrap[] != 0:
        do_wrap = do_wrap or count_elements >= this.elementsBeforeWrap[]
      
      if this.lengthBeforeWrap[] != 0:
        do_wrap = do_wrap or count_width + w > this.lengthBeforeWrap[]
      
      if do_wrap:
        rows[^1].elements.add child
        rows.add rows[0].typeof.default
        count_width = w
        count_elements = 1
      else:
        rows[^1].elements.add child
        count_width += this.gap[]

  block get_height_per_row:
    for row in rows.mitems:
      for child in row.elements:
        let h =
          if this.fillContainer[]:
            0'f32
          elif child of InLayout and child.InLayout.fillContainer[]:
            0
          else:
            child.get_h

        row.height = max(row.height, h)
      
      if row.height == 0 and row.elements.len > 0:
        row.height = row.elements[0].get_h
        
        for child in row.elements:
          row.height = min(row.height, child.get_h)

  block set_y_and_h:
    ## todo



proc reposition(this: Layout) =
  this.reposition_old()
  # if this.inRepositionProcess: return
  # this.inRepositionProcess = true
  # this.doReposition()
  # this.inRepositionProcess = false


template spacing*(this: Layout): Property[float32] = this.gap
template wrapSpacing*(this: Layout): Property[float32] = this.wrapGap
template alignment*(this: Layout): Property[float32] = this.alignContent
template wrapAlignment*(this: Layout): Property[float32] = this.wrapAlignContent

template alignment*(this: InLayout): Property[float32] = this.align


method addChild*(this: Layout, child: Uiobj) =
  if this.newChildsObject != nil:
    this.newChildsObject.addChild(child)
    return
  
  procCall this.super.addChild(child)
  
  child.w.changed.connectTo this: reposition(this)
  child.h.changed.connectTo this: reposition(this)
  # todo: disconnect if child is no loger child

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



proc row*(this: Layout, gap: float32 = 0) =
  this.gap{} = gap
  this.orientation{} = LayoutOrientation.horizontal

proc col*(this: Layout, gap: float32 = 0) =
  this.gap{} = gap
  this.orientation{} = LayoutOrientation.vertical


proc hbox*(this: Layout, gap: float32 = 0) =
  this.orientation{} = LayoutOrientation.horizontal
  this.hugContent{} = false

proc vbox*(this: Layout, gap: float32 = 0) =
  this.gap{} = gap
  this.orientation{} = LayoutOrientation.vertical
  this.hugContent{} = false


proc grid*(this: Layout, columns: int, gap: float32 = 0) =
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


proc hbox*(typ: typedesc[Layout], gap: float32 = 0): Layout =
  new result
  result.hbox(gap)

proc vbox*(typ: typedesc[Layout], gap: float32 = 0): Layout =
  new result
  result.vbox(gap)


proc grid*(typ: typedesc[Layout], columns: int, gap: float32 = 0): Layout =
  new result
  result.grid(columns, gap)


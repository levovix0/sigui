import sequtils
import uibase

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

    alignContent*, wrapAlignContent*: Property[LayoutAlignment]

    gap*, wrapGap*: Property[float32]
    fillWithSpaces*, wrapFillWithSpaces*: Property[bool]
    consistentSpacing*: Property[bool]
    
    wrap*: Property[bool]
      ## become "grid"
    elementsBeforeWrap*: Property[int]
    lengthBeforeWrap*: Property[float32]

    inRepositionProcess: bool
  
  InLayout* = ref object of Uiobj
    align*: Property[LayoutAlignment]
    fillContainer*: Property[bool]
    
    isChangingW, isChangingH: bool

registerComponent Layout
registerComponent InLayout


proc reposition(this: Layout) =
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

  var rows: seq[tuple[childs: seq[Uiobj], freeSpace: float32, spaceBetween: float32, h: float32]] = @[(@[], this.get_w, 0'f32, 0'f32)]

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
    rows[^1].h = h
  
  for x in rows.mitems:
    x.spaceBetween =
      if this.childs.len > 1: x.freeSpace / (x.childs.len - 1).float32
      else: 0

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

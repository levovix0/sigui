import pkg/[siwin, vmath]
import ./[events {.all.}, properties, uiobj {.all.}]
export MouseButton, MouseMoveEvent

type
  MouseArea* = ref object of Uiobj
    acceptedButtons*: Property[set[MouseButton]] = {MouseButton.left}.property
      ## handle only events of these buttons
    
    pressed*: Property[bool]
      ## is mouse button (any of accepted) pressed inside this area (or was pressed inside) and is pressed now
    
    hovered*: Property[bool]
      ## is mouse over this area now

    mouseX*, mouseY*: Property[float32]
      ## current mouse position, relative to this area (see also: mouseXy)

    grabbed*: Property[bool]
      ## sets to true when mouse was pressed inside and started moving while in this area
      ## emits start position (relative to screen)
      ## sets to false when mouse was released

    mouseButton*: Event[MouseButtonEvent]
      ## mouse pressed or released inside this area (doesn't require pressed[] to be true)

    clicked*: Event[ClickEvent]
      ## mouse pressed and released without movement

    mouseDownAndUpInside*: Event[void]
      ## mouse button pressed and released inside this area (also if pressed, leaved, re-entered and released)
    
    scrolled*: Event[Vec2]
      ## mouse scrolled inside this area
      ## emits scroll delta (both x and y)
      ## y > 0 - scroll down (clockwise on default mouse wheel, looking from left side)
      ## y < 0 - scroll up (anti-clockwise on default mouse wheel, looking from left side)
      ## x > 0 - scroll right
      ## x < 0 - scroll left
      ## scroll delta is usualy -1, 0, or 1

    cursor*: Property[ref Cursor]
      ## cursor for mouse when inside this area
    
    allowEventFallthrough*: Property[bool]
      ## if true, this mouse area will not mark MouseButton window events as handled
    
    pressedButtons*: set[MouseButton]
    pressWindowPos*: Vec2  # press pos relative to window


proc handleMouseMoveEvent(this: MouseArea, e: MouseMoveEvent, signal: Signal)


disableAutoRedrawHook MouseArea

addFirstHandHandler MouseArea, "globalX":
  handleMouseMoveEvent(this, MouseMoveEvent(pos: this.parentUiWindow.siwinWindow.mouse.pos), nil)
  superHook()

addFirstHandHandler MouseArea, "globalY":
  handleMouseMoveEvent(this, MouseMoveEvent(pos: this.parentUiWindow.siwinWindow.mouse.pos), nil)
  superHook()

proc onHoveredOrCursorChanged(this: MouseArea)

addFirstHandHandler MouseArea, "hovered":
  onHoveredOrCursorChanged(this)
  autoredraw(this)

addFirstHandHandler MouseArea, "cursor":
  onHoveredOrCursorChanged(this)
  autoredraw(this)
  
addFirstHandHandler MouseArea, "visibility":
  if this.visibility[] == collapsed:
    this.pressed[] = false
    this.hovered[] = false
    this.grabbed[] = false
  superHook()


registerComponent MouseArea


proc mouseXy*(this: MouseArea): CustomProperty[Vec2] =
  CustomProperty[Vec2](
    get: proc(): Vec2 = vec2(this.mouseX[], this.mouseY[]),
    set: proc(v: Vec2) = this.mouseX[] = v.x; this.mouseY[] = v.y,
  )


proc handleMouseMoveEvent(this: MouseArea, e: MouseMoveEvent, signal: Signal) =
  let pos = this.globalXy
  if e.pos.x.float32 in pos.x..(pos.x + this.w[]) and e.pos.y.float32 in pos.y..(pos.y + this.h[]):
    this.hovered[] = true
  else:
    this.hovered[] = false

  let d = this.globalXy

  let xChanged = this.mouseX[] != e.pos.x.float32 - d.x
  let yChanged = this.mouseY[] != e.pos.y.float32 - d.y

  this.mouseX{} = e.pos.x.float32 - d.x
  this.mouseY{} = e.pos.y.float32 - d.y

  if signal != nil and signal.WindowEvent.handled == false and signal.WindowEvent.fake == false:
    if this.pressed[]:
      if not this.grabbed[]:
        this.grabbed[] = true
        if not this.allowEventFallthrough[]:
          signal.WindowEvent.handled = true

  if xChanged: this.mouseX.changed.emit()
  if yChanged: this.mouseY.changed.emit()


proc handleMouseButtonEvent(this: MouseArea, e: MouseButtonEvent, signal: Signal) =
  if e.button in this.acceptedButtons[]:
    if e.pressed and signal.WindowEvent.handled == false:
      if this.hovered[]:
        this.pressedButtons.incl e.button
        this.pressed[] = true
        this.pressWindowPos = e.window.mouse.pos
        if not this.allowEventFallthrough[]:
          signal.WindowEvent.handled = true
    else:
      this.pressedButtons.excl e.button
      if this.pressedButtons == {}:
        if this.pressed[]:
          this.pressed[] = false
          this.grabbed[] = false
          
          if (
            signal.WindowEvent.handled == false and
            this.hovered[] and
            not e.generated
          ):
            this.mouseDownAndUpInside.emit()
          
          if this.hovered[] and not this.allowEventFallthrough[]:
            signal.WindowEvent.handled = true


proc onHoveredOrCursorChanged(this: MouseArea) =
  if (let win = this.parentUiWindow; win != nil):
    var cursor = GetActiveCursor()
    win.recieve(cursor)
    if cursor.handled and cursor.cursor != nil:
      win.siwinWindow.cursor = cursor.cursor[]
    else:
      win.siwinWindow.cursor = Cursor()


method recieve*(this: MouseArea, signal: Signal) =
  procCall this.super.recieve(signal)

  if this.visibility != collapsed:
    if signal of WindowEvent and signal.WindowEvent.event of MouseButtonEvent:
      handleMouseButtonEvent(this, ((ref MouseButtonEvent)signal.WindowEvent.event)[], signal)
      if this.hovered[]: this.mouseButton.emit(((ref MouseButtonEvent)signal.WindowEvent.event)[])
    

    elif signal of WindowEvent and signal.WindowEvent.event of ClickEvent:
      if this.hovered[]: this.clicked.emit(((ref ClickEvent)signal.WindowEvent.event)[])
    

    elif signal of WindowEvent and signal.WindowEvent.event of MouseMoveEvent:
      handleMouseMoveEvent(this, ((ref MouseMoveEvent)signal.WindowEvent.event)[], signal)


    elif signal of WindowEvent and signal.WindowEvent.event of ScrollEvent:
      if signal.WindowEvent.handled == false:
        if this.visibility != collapsed:
          let e = (ref ScrollEvent)signal.WindowEvent.event
          if this.hovered[]:
            this.scrolled.emit(vec2(e.deltaX, e.delta))
    

    elif signal of GetActiveCursor:
      if not signal.GetActiveCursor.handled and this.hovered[]:
        signal.GetActiveCursor.cursor = this.cursor[]
        if not this.allowEventFallthrough[]:
          signal.GetActiveCursor.handled = true
  

  if signal of VisibilityChanged:
    if signal.VisibilityChanged.visibility == collapsed:
      this.hovered[] = false


proc newMouseArea*(): MouseArea = new result

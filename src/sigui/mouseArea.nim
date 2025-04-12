import pkg/[siwin, vmath]
import ./[events {.all.}, properties, uiobj]
export MouseButton, MouseMoveEvent

type
  MouseArea* = ref object of Uiobj
    acceptedButtons*: Property[set[MouseButton]] = {MouseButton.left}.property
      ## handle only events of these buttons
    ignoreHandling*: Property[bool]
      ## don't stop propogating signals even they are handled
    
    pressed*: Property[bool]
      ## is mouse button pressed inside this area (or was pressed inside) and is pressed now
    
    hovered*: Property[bool]
      ## is mouse button pressed inside this area now

    mouseX*, mouseY*: Property[float32]
      ## current mouse position, relative to this area (see also: mouseXy)

    mouseButton* {.deprecated #[don't use it]#.}: Event[MouseButtonEvent]

    clicked*: Event[ClickEvent]
      ## mouse pressed and released without movement

    mouseDownAndUpInside*: Event[void]
      ## mouse button pressed and released inside this area (also if pressed, leaved, re-entered and released)

    dragged* {.deprecated #[use grabbed instead]#.}: Event[IVec2]
    grabbed*: Event[Vec2]
      ## mouse pressed and started moving while in this area
      ## emits start position (relative to screen)
      ## see mouseX and mouseY for current position
    
    scrolled*: Event[Vec2]
      ## mouse scrolled inside this area
      ## emits scroll delta (both x and y)
      ## y > 0 - scroll down (clockwise on default mouse wheel, looking from left side)
      ## y < 0 - scroll up (anti-clockwise on default mouse wheel, looking from left side)
      ## x > 0 - scroll right
      ## x < 0 - scroll left
      ## scroll delta is usualy -1, 0, or 1

    cursor*: ref Cursor
      ## cursor for mouse when inside this area
    
    pressedButtons: set[MouseButton]
    pressedPos: Vec2
    grabStarted: bool

proc initRedrawWhenPropertyChanged_ignore(t: type MouseArea, name: string): bool {.used.} =
  name notin ["x", "y"]  # MouseArea doesn't draw anything

registerComponent MouseArea


proc mouseXy*(this: MouseArea): CustomProperty[Vec2] =
  CustomProperty[Vec2](
    get: proc(): Vec2 = vec2(this.mouseX[], this.mouseY[]),
    set: proc(v: Vec2) = this.mouseX[] = v.x; this.mouseY[] = v.y,
  )


method init*(this: MouseArea) =
  procCall this.super.init()

  this.visibility.changed.connect this.eventHandler, flags = {EventConnectionFlag.internal}, f = proc =
    if this.visibility[] == collapsed:
      this.pressed[] = false
      this.hovered[] = false


method recieve*(this: MouseArea, signal: Signal) =
  procCall this.super.recieve(signal)

  if this.visibility != collapsed:
    template handlePositionalEvent(ev, ev2) =
      let e {.cursor.} = (ref ev)signal.WindowEvent.event
      let pos = this.xy.posToGlobal(this.parent)
      if e.window.mouse.pos.x.float32 in pos.x..(pos.x + this.w[]) and e.window.mouse.pos.y.float32 in pos.y..(pos.y + this.h[]):
        this.ev2.emit e[]
    

    if signal of WindowEvent and signal.WindowEvent.event of MouseButtonEvent:
      {.push, warning[Deprecated]: off.}
      handlePositionalEvent MouseButtonEvent, mouseButton
      {.pop.}
    

    elif signal of WindowEvent and signal.WindowEvent.event of ClickEvent:
      handlePositionalEvent ClickEvent, clicked
    

    elif signal of WindowEvent and signal.WindowEvent.event of MouseMoveEvent:
      let e {.cursor.} = (ref MouseMoveEvent)signal.WindowEvent.event
      let pos = this.xy.posToGlobal(this.parent)
      if e.pos.x.float32 in pos.x..(pos.x + this.w[]) and e.pos.y.float32 in pos.y..(pos.y + this.h[]):
        this.hovered[] = true
      else:
        this.hovered[] = false
    
    
    if signal of WindowEvent and signal.WindowEvent.event of MouseMoveEvent:
      let e = (ref MouseMoveEvent)signal.WindowEvent.event
      let d = vec2().posToGlobal(this)
      this.mouseX[] = e.window.mouse.pos.x.float32 - d.x
      this.mouseY[] = e.window.mouse.pos.y.float32 - d.y


    if signal of WindowEvent and signal.WindowEvent.event of MouseMoveEvent and signal.WindowEvent.handled == false and signal.WindowEvent.fake == false:
      if this.pressed[]:
        if not this.grabStarted:
          this.grabStarted = true
          if this.grabbed.hasHandlers:
            signal.WindowEvent.handled = true
          this.grabbed.emit(this.pressedPos)


    elif signal of WindowEvent and signal.WindowEvent.event of MouseButtonEvent and signal.WindowEvent.handled == false:
      if this.visibility != collapsed:
        let e = (ref MouseButtonEvent)signal.WindowEvent.event
        if e.button in this.acceptedButtons[]:
          if e.pressed:
            if this.hovered[]:
              this.pressedButtons.incl e.button
              this.pressed[] = true
              this.pressedPos = e.window.mouse.pos + e.window.pos.vec2
          else:
            this.pressedButtons.excl e.button
            if this.pressedButtons == {}:
              if this.pressed[]:
                this.pressed[] = false
                this.grabStarted = false
                if this.hovered[] and not e.generated:
                  this.mouseDownAndUpInside.emit()

    elif signal of WindowEvent and signal.WindowEvent.event of ScrollEvent and signal.WindowEvent.handled == false:
      if this.visibility != collapsed:
        let e = (ref ScrollEvent)signal.WindowEvent.event
        if this.hovered[]:
          this.scrolled.emit(vec2(e.deltaX, e.delta))
    

    elif signal of GetActiveCursor:
      if signal.GetActiveCursor.cursor == nil and this.hovered[]:
        signal.GetActiveCursor.cursor = this.cursor
  

  if signal of VisibilityChanged:
    if signal.VisibilityChanged.visibility == collapsed:
      this.hovered[] = false


proc newMouseArea*(): MouseArea = new result

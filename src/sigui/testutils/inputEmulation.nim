
import std/[unicode]
import pkg/[vmath, bumpy]
import pkg/siwin/platforms/any/window
import pkg/pixie/images
import ../[uiobj, uibase, window, windowCreation]


#* ------------- input emulation: events plumbing ------------- *#

proc toRefEvent[T](e: T): ref AnyWindowEvent =
  result = (ref T)()
  (ref T)(result)[] = e


proc sendWindowEvent[T](this: UiWindow, e: T) =
  ## sends a window event to the ui tree, same as a real window does
  this.recieve(WindowEvent(sender: this, event: e.toRefEvent))


#* ------------- input emulation: mouse ------------- *#

proc mouseMoveTo*(this: UiWindow, pos: Vec2, kind = MouseMoveKind.move) =
  ## moves the emulated mouse cursor to `pos` (window coordinates, pixels)
  this.siwinWindow.mouse.pos = pos
  this.sendWindowEvent(MouseMoveEvent(window: this.siwinWindow, pos: pos, kind: kind))


proc mouseMoveBy*(this: UiWindow, offset: Vec2) =
  this.mouseMoveTo(this.siwinWindow.mouse.pos + offset)


proc mousePress*(this: UiWindow, button: MouseButton = MouseButton.left) =
  ## presses an emulated mouse button at the current cursor position
  this.siwinWindow.mouse.pressed.incl button
  this.sendWindowEvent(MouseButtonEvent(window: this.siwinWindow, button: button, pressed: true))


proc mouseRelease*(this: UiWindow, button: MouseButton = MouseButton.left, click = false) =
  ## releases an emulated mouse button at the current cursor position.
  ## if `click` is true, also emits ClickEvent, as a real window does when the cursor
  ## didn't move between press and release
  this.siwinWindow.mouse.pressed.excl button
  this.sendWindowEvent(MouseButtonEvent(window: this.siwinWindow, button: button, pressed: false))
  if click:
    this.sendWindowEvent(ClickEvent(window: this.siwinWindow, button: button, pos: this.siwinWindow.mouse.pos))


proc mouseClick*(this: UiWindow, pos: Vec2, button: MouseButton = MouseButton.left) =
  ## moves the emulated mouse cursor to `pos` and clicks (press + release without movement)
  this.mouseMoveTo(pos)
  this.mousePress(button)
  this.mouseRelease(button, click = true)


proc mouseDoubleClick*(this: UiWindow, pos: Vec2, button: MouseButton = MouseButton.left) =
  ## performs two clicks at `pos`, the second one marked as double
  this.mouseClick(pos, button)
  this.siwinWindow.mouse.pressed.incl button
  this.sendWindowEvent(MouseButtonEvent(window: this.siwinWindow, button: button, pressed: true))
  this.siwinWindow.mouse.pressed.excl button
  this.sendWindowEvent(MouseButtonEvent(window: this.siwinWindow, button: button, pressed: false))
  this.sendWindowEvent(ClickEvent(window: this.siwinWindow, button: button, pos: pos, double: true))


proc mouseScroll*(this: UiWindow, delta: float, deltaX = 0'f64) =
  ## rotates the emulated mouse wheel at the current cursor position.
  ## delta > 0 - scroll down, delta < 0 - scroll up (as a real mouse wheel reports)
  this.sendWindowEvent(ScrollEvent(window: this.siwinWindow, delta: delta, deltaX: deltaX, device: ScrollDeviceKind.discrete))


proc mouseScrollAt*(this: UiWindow, delta: float, pos: Vec2, deltaX = 0'f64) =
  ## moves the emulated mouse cursor to `pos` and scrolls the wheel there
  this.mouseMoveTo(pos)
  this.mouseScroll(delta, deltaX)


proc mouseDrag*(this: UiWindow, fromPos, toPos: Vec2, button: MouseButton = MouseButton.left, steps = 4) =
  ## presses the emulated mouse button at `fromPos`, moves the cursor to `toPos`
  ## in `steps` movements, then releases the button
  this.mouseMoveTo(fromPos)
  this.mousePress(button)
  for i in 1 .. max(1, steps):
    this.mouseMoveTo(fromPos + (toPos - fromPos) * (i.float32 / steps.float32), MouseMoveKind.moveWhileDragging)
  this.mouseRelease(button)


proc mouseEnterWindow*(this: UiWindow, pos: Vec2) =
  this.siwinWindow.mouse.pos = pos
  this.sendWindowEvent(MouseMoveEvent(window: this.siwinWindow, pos: pos, kind: MouseMoveKind.enter))


proc mouseLeaveWindow*(this: UiWindow) =
  ## moves the emulated mouse cursor far outside of the window, notifying about leave
  this.mouseMoveTo(vec2(-1000, -1000), MouseMoveKind.leave)


proc mouseMoveTo*(this: UiWindow, pos: IVec2) = this.mouseMoveTo(pos.vec2)
proc mouseClick*(this: UiWindow, pos: IVec2, button: MouseButton = MouseButton.left) = this.mouseClick(pos.vec2, button)
proc mouseDrag*(this: UiWindow, fromPos, toPos: IVec2, button: MouseButton = MouseButton.left, steps = 4) = this.mouseDrag(fromPos.vec2, toPos.vec2, button, steps)
proc mouseScrollAt*(this: UiWindow, delta: float, pos: IVec2, deltaX = 0'f64) = this.mouseScrollAt(delta, pos.vec2, deltaX)


#* ------------- input emulation: keyboard ------------- *#

proc updateModifiers(this: UiWindow) =
  let pressed = this.siwinWindow.keyboard.pressed
  var modifiers: set[ModifierKey]
  if (pressed * {Key.lshift, Key.rshift}).len != 0: modifiers.incl ModifierKey.shift
  if (pressed * {Key.lcontrol, Key.rcontrol}).len != 0: modifiers.incl ModifierKey.control
  if (pressed * {Key.lalt, Key.ralt, Key.level3_shift, Key.level5_shift}).len != 0: modifiers.incl ModifierKey.alt
  if (pressed * {Key.lsystem, Key.rsystem}).len != 0: modifiers.incl ModifierKey.system
  this.siwinWindow.keyboard.modifiers = modifiers


proc keyPress*(this: UiWindow, key: Key) =
  ## presses a key (and keeps it pressed until `keyRelease`)
  this.siwinWindow.keyboard.pressed.incl key
  this.updateModifiers()
  this.sendWindowEvent(KeyEvent(window: this.siwinWindow, key: key, pressed: true, modifiers: this.siwinWindow.keyboard.modifiers))


proc keyRelease*(this: UiWindow, key: Key) =
  ## releases a key pressed by `keyPress`
  this.siwinWindow.keyboard.pressed.excl key
  this.updateModifiers()
  this.sendWindowEvent(KeyEvent(window: this.siwinWindow, key: key, pressed: false, modifiers: this.siwinWindow.keyboard.modifiers))


proc keyTap*(this: UiWindow, key: Key) =
  ## presses and releases a key
  this.keyPress(key)
  this.keyRelease(key)


proc hotkey*(this: UiWindow, keys: varargs[Key]) =
  ## presses all the given keys one by one (keeping them pressed) and releases them
  ## in reverse order, like a user does when entering a key combination
  for k in keys: this.keyPress(k)
  for i in countdown(keys.high, 0): this.keyRelease(keys[i])


proc textInput*(this: UiWindow, text: string) =
  ## sends text as if it was typed using an input method
  this.sendWindowEvent(TextInputEvent(window: this.siwinWindow, text: text))


proc typeText*(this: UiWindow, text: string) =
  ## types text character by character, as a user does
  for r in text.runes:
    this.textInput($r)


#* ------------- object-relative input ------------- *#

proc globalRect*(obj: Uiobj): Rect =
  ## rect of the component in window (root) coordinates
  rect(obj.globalXy, obj.wh)


proc centerOf*(obj: Uiobj): Vec2 =
  ## center of the component in window (root) coordinates
  obj.globalXy + obj.wh / 2


proc clickAt*(this: UiWindow, obj: Uiobj, offset: Vec2 = vec2()) =
  ## clicks in the center of the component (plus `offset`)
  this.mouseClick(obj.centerOf + offset)


proc clickAt*(this: UiWindow, obj: Uiobj, offsetX, offsetY: float32) =
  this.clickAt(obj, vec2(offsetX, offsetY))


proc clickAt*(this: UiWindow, pos: Vec2) =
  ## clicks at the given window position
  this.mouseClick(pos)


proc hoverAt*(this: UiWindow, obj: Uiobj, offset: Vec2 = vec2()) =
  ## moves the emulated mouse cursor to the center of the component (plus `offset`)
  this.mouseMoveTo(obj.centerOf + offset)


proc hoverAt*(this: UiWindow, pos: Vec2) =
  this.mouseMoveTo(pos)


proc dragFromTo*(this: UiWindow, fromObj, toObj: Uiobj, button: MouseButton = MouseButton.left, steps = 4) =
  ## drags from the center of one component to the center of another
  this.mouseDrag(fromObj.centerOf, toObj.centerOf, button, steps)


proc dragFromTo*(this: UiWindow, fromPos, toPos: Vec2, button: MouseButton = MouseButton.left, steps = 4) =
  this.mouseDrag(fromPos, toPos, button, steps)


proc scrollTo*(this: UiWindow, obj: Uiobj, delta: float, deltaX = 0'f64) =
  ## scrolls the mouse wheel over the component
  this.mouseScrollAt(delta, obj.centerOf, deltaX)


proc typeInto*(this: UiWindow, obj: Uiobj, text: string) =
  ## activates the text area (like a mouse click does) and types text into it
  this.clickAt(obj)
  this.typeText(text)

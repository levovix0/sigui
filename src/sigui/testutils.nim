## Utilities for testing sigui applications without a visible window and without user interaction.
##
## Designed to be used by automated tests and AI agents:
##
## - `newHeadlessUiWindow` creates a UiWindow that renders into an offscreen framebuffer,
##   so no window is shown on screen
## - `screenshot`/`saveScreenshot` render the window content into an image
## - mouse and keyboard input can be emulated programmatically (`mouseClick`, `mouseDrag`,
##   `typeText`, `hotkey`, etc.)
## - `uiRepr`/`uiJson` dumps a component tree in a compact machine-readable form
##
## ```nim
## import unittest, sigui, sigui/testutils
##
## let win = newHeadlessUiWindow(size = ivec2(200, 100))
## win.makeLayout:
##   this.clearColor = "#202020".color
##   - UiRect.new as rect:
##     w = 50; h = 50
##     color = "#ff0000".color
##
##     - MouseArea.new as mouse:
##       this.fill parent
##       on this.clicked: rect.color[] = "#00ff00".color
##
## win.saveScreenshot "rect.png"
## win.clickAt(vec2(25, 25))
## check rect.color[] == "#00ff00".color
## ```
##
## note: headless rendering uses an invisible X11 window to obtain an OpenGL context,
## so on Linux it requires X11 (or XWayland) to be available

import std/[json, strutils, times, unicode]
import pkg/[vmath, bumpy, chroma, opengl]
import pkg/siwin/[platforms, offscreen]
import pkg/siwin/platforms/any/window
import pkg/rice/transform
import pkg/pixie
import ./[uiobj, uibase, window, windowCreation, mouseArea, textArea]
import ./rendering/[current_backend]
export Image

when defined(macosx):
  {.error: "sigui/testutils requires an offscreen OpenGL context, which siwin does not provide for macOS yet".}


#* ------------- headless window ------------- *#

type
  HeadlessUiWindow* = ref object of UiWindow
    ## UiWindow that renders into an offscreen framebuffer instead of a visible window.
    ## Mouse/keyboard state is not driven by any real device, input can only be emulated
    ## using procedures from this module.
    m_size*: IVec2
      ## size of the drawing area in pixels

    fbo: GlUint
    fboTexture: GlUint


var headlessGlobals: SiwinGlobals


proc setupOffscreenFramebuffer(this: HeadlessUiWindow, size: IVec2) =
  let raw = this.ctx.RiceDrawContext.raw

  if this.fbo != 0:
    glDeleteFramebuffers(1, this.fbo.addr)
    glDeleteTextures(1, this.fboTexture.addr)
    this.fbo = 0
    this.fboTexture = 0

  glGenTextures(1, this.fboTexture.addr)
  glBindTexture(GlTexture2d, this.fboTexture)
  glTexImage2D(GlTexture2d, 0, GlRgba.Glint, size.x.Glsizei, size.y.Glsizei, 0, GlRgba, GlUnsignedByte, nil)
  glTexParameteri(GlTexture2d, GlTextureMinFilter, GlNearest)
  glTexParameteri(GlTexture2d, GlTextureMagFilter, GlNearest)

  glGenFramebuffers(1, this.fbo.addr)
  glBindFramebuffer(GlFramebuffer, this.fbo)
  glFramebufferTexture2D(GlFramebuffer, GlColorAttachment0, GlTexture2d, this.fboTexture, 0)

  glViewport(0, 0, size.x.Glsizei, size.y.Glsizei)
  raw.fbo = this.fbo
  raw.fboSize = size
  raw.updateDrawingAreaSize(size)
  raw.projection = combine(
    scale(vec3(2 / size.x.float32, -2 / size.y.float32, 1)),
    translate(vec3(-1, 1, 0)),
  )

  this.wh = size.vec2


proc newHeadlessUiWindow*(size = ivec2(800, 600)): HeadlessUiWindow =
  ## creates a UiWindow with an offscreen OpenGL drawing area of the given size.
  ## no window appears on the screen
  if headlessGlobals == nil:
    # siwin does not support offscreen contexts on wayland yet, use x11 (XWayland works fine)
    headlessGlobals = newSiwinGlobals(x11)

  new result

  result.siwinWindow = headlessGlobals.newOpenglContext()
  loadExtensions()
  result.setupEventsHandling()
  result.ctx = newRiceDrawContext()
  result.parentRoot = result
  result.m_size = size
  result.setupOffscreenFramebuffer(size)


proc size*(this: HeadlessUiWindow): IVec2 = this.m_size


proc `size=`*(this: HeadlessUiWindow, v: IVec2) =
  if this.m_size == v: return
  this.m_size = v
  this.setupOffscreenFramebuffer(v)


method doRedraw*(this: HeadlessUiWindow) =
  ## headless window is not rendered continuously, call `render`/`screenshot`/`frame` instead
  discard


proc render*(this: HeadlessUiWindow) =
  ## draws one frame, same as a real window does on each RenderEvent
  this.recieve(BeforeDraw(sender: this, ctx: this.ctx))
  this.draw(this.ctx)
  this.ctx.finishRendering()


proc screenshot*(this: HeadlessUiWindow): Image =
  ## draws one frame and returns it as a pixie Image
  this.render()

  result = newImage(this.m_size.x, this.m_size.y)
  glBindFramebuffer(GlFramebuffer, this.fbo)
  glPixelStorei(GlPackAlignment, 1)
  glReadPixels(0, 0, this.m_size.x.Glsizei, this.m_size.y.Glsizei, GlRgba, GlUnsignedByte, result.data[0].addr)

  # OpenGL returns rows bottom-to-top, pixie stores rows top-to-bottom
  let h = this.m_size.y
  for y in 0 ..< h div 2:
    let top = y * this.m_size.x
    let bottom = (h - 1 - y) * this.m_size.x
    for x in 0 ..< this.m_size.x:
      swap(result.data[top + x], result.data[bottom + x])


proc saveScreenshot*(this: HeadlessUiWindow, filepath: string) =
  ## draws one frame and saves it as an image file (format is detected by extension)
  this.screenshot.writeFile filepath


proc windowPixelColor*(this: HeadlessUiWindow, pos: Vec2): Color =
  ## draws one frame and returns the color of the pixel at `pos` (in window coordinates)
  let img = this.screenshot()
  let c = img[pos.x.int, pos.y.int]
  color(c.r.int / 255, c.g.int / 255, c.b.int / 255, c.a.int / 255)

proc windowPixelColor*(this: HeadlessUiWindow, x, y: SomeInteger|SomeFloat): Color =
  ## draws one frame and returns the color of the pixel at `pos` (in window coordinates)
  this.pixelColor(vec2(x.float32, y.float32))


proc pixelColor*(this: Uiobj, pos: Vec2): Color =
  ## draws one frame and returns the color of the pixel at `pos` (in component coordinates)
  this.root.HeadlessUiWindow.windowPixelColor(pos.posToGlobal(this))

proc pixelColor*(this: Uiobj, x, y: SomeInteger|SomeFloat): Color =
  ## draws one frame and returns the color of the pixel at `pos` (in component coordinates)
  this.pixelColor(vec2(x.float32, y.float32))


#* ------------- frame loop ------------- *#

proc tick*(this: HeadlessUiWindow, deltaTime = initDuration(milliseconds = 16)) =
  ## emits onTick with the given deltaTime; animations and transitions are updated by this
  this.onTick.emit(TickEvent(window: this.siwinWindow, deltaTime: deltaTime))


proc frame*(this: HeadlessUiWindow, deltaTime = initDuration(milliseconds = 16)) =
  ## performs a full frame as a real window does: tick + render
  this.tick(deltaTime)
  this.render()


proc settleAnimations*(this: HeadlessUiWindow, duration = initDuration(seconds = 10)) =
  ## same as frame, but has much longer step duration, so most of the animations will be finished
  this.tick(duration)
  this.render()


proc tickUntil*(
  this: HeadlessUiWindow,
  condition: proc(): bool,
  timeout = initDuration(seconds = 10),
  frameDelta = initDuration(milliseconds = 16),
): bool =
  ## ticks and draws frames until `condition` returns true or the virtual timeout passes.
  ## returns true if condition was met
  var waited = DurationZero
  while not condition():
    if waited >= timeout: return false
    this.frame(frameDelta)
    waited += frameDelta
  result = true


#* ------------- input emulation: events plumbing ------------- *#

proc toRefEvent[T](e: T): ref AnyWindowEvent =
  result = (ref T)()
  (ref T)(result)[] = e


proc sendWindowEvent[T](this: HeadlessUiWindow, e: T) =
  ## sends a window event to the ui tree, same as a real window does
  this.recieve(WindowEvent(sender: this, event: e.toRefEvent))


#* ------------- input emulation: mouse ------------- *#

proc mouseMoveTo*(this: HeadlessUiWindow, pos: Vec2, kind = MouseMoveKind.move) =
  ## moves the emulated mouse cursor to `pos` (window coordinates, pixels)
  this.siwinWindow.mouse.pos = pos
  this.sendWindowEvent(MouseMoveEvent(window: this.siwinWindow, pos: pos, kind: kind))


proc mouseMoveBy*(this: HeadlessUiWindow, offset: Vec2) =
  this.mouseMoveTo(this.siwinWindow.mouse.pos + offset)


proc mousePress*(this: HeadlessUiWindow, button: MouseButton = MouseButton.left) =
  ## presses an emulated mouse button at the current cursor position
  this.siwinWindow.mouse.pressed.incl button
  this.sendWindowEvent(MouseButtonEvent(window: this.siwinWindow, button: button, pressed: true))


proc mouseRelease*(this: HeadlessUiWindow, button: MouseButton = MouseButton.left, click = false) =
  ## releases an emulated mouse button at the current cursor position.
  ## if `click` is true, also emits ClickEvent, as a real window does when the cursor
  ## didn't move between press and release
  this.siwinWindow.mouse.pressed.excl button
  this.sendWindowEvent(MouseButtonEvent(window: this.siwinWindow, button: button, pressed: false))
  if click:
    this.sendWindowEvent(ClickEvent(window: this.siwinWindow, button: button, pos: this.siwinWindow.mouse.pos))


proc mouseClick*(this: HeadlessUiWindow, pos: Vec2, button: MouseButton = MouseButton.left) =
  ## moves the emulated mouse cursor to `pos` and clicks (press + release without movement)
  this.mouseMoveTo(pos)
  this.mousePress(button)
  this.mouseRelease(button, click = true)


proc mouseDoubleClick*(this: HeadlessUiWindow, pos: Vec2, button: MouseButton = MouseButton.left) =
  ## performs two clicks at `pos`, the second one marked as double
  this.mouseClick(pos, button)
  this.siwinWindow.mouse.pressed.incl button
  this.sendWindowEvent(MouseButtonEvent(window: this.siwinWindow, button: button, pressed: true))
  this.siwinWindow.mouse.pressed.excl button
  this.sendWindowEvent(MouseButtonEvent(window: this.siwinWindow, button: button, pressed: false))
  this.sendWindowEvent(ClickEvent(window: this.siwinWindow, button: button, pos: pos, double: true))


proc mouseScroll*(this: HeadlessUiWindow, delta: float, deltaX = 0'f64) =
  ## rotates the emulated mouse wheel at the current cursor position.
  ## delta > 0 - scroll down, delta < 0 - scroll up (as a real mouse wheel reports)
  this.sendWindowEvent(ScrollEvent(window: this.siwinWindow, delta: delta, deltaX: deltaX, device: ScrollDeviceKind.discrete))


proc mouseScrollAt*(this: HeadlessUiWindow, delta: float, pos: Vec2, deltaX = 0'f64) =
  ## moves the emulated mouse cursor to `pos` and scrolls the wheel there
  this.mouseMoveTo(pos)
  this.mouseScroll(delta, deltaX)


proc mouseDrag*(this: HeadlessUiWindow, fromPos, toPos: Vec2, button: MouseButton = MouseButton.left, steps = 4) =
  ## presses the emulated mouse button at `fromPos`, moves the cursor to `toPos`
  ## in `steps` movements, then releases the button
  this.mouseMoveTo(fromPos)
  this.mousePress(button)
  for i in 1 .. max(1, steps):
    this.mouseMoveTo(fromPos + (toPos - fromPos) * (i.float32 / steps.float32), MouseMoveKind.moveWhileDragging)
  this.mouseRelease(button)


proc mouseEnterWindow*(this: HeadlessUiWindow, pos: Vec2) =
  this.siwinWindow.mouse.pos = pos
  this.sendWindowEvent(MouseMoveEvent(window: this.siwinWindow, pos: pos, kind: MouseMoveKind.enter))


proc mouseLeaveWindow*(this: HeadlessUiWindow) =
  ## moves the emulated mouse cursor far outside of the window, notifying about leave
  this.mouseMoveTo(vec2(-1000, -1000), MouseMoveKind.leave)


proc mouseMoveTo*(this: HeadlessUiWindow, pos: IVec2) = this.mouseMoveTo(pos.vec2)
proc mouseClick*(this: HeadlessUiWindow, pos: IVec2, button: MouseButton = MouseButton.left) = this.mouseClick(pos.vec2, button)
proc mouseDrag*(this: HeadlessUiWindow, fromPos, toPos: IVec2, button: MouseButton = MouseButton.left, steps = 4) = this.mouseDrag(fromPos.vec2, toPos.vec2, button, steps)
proc mouseScrollAt*(this: HeadlessUiWindow, delta: float, pos: IVec2, deltaX = 0'f64) = this.mouseScrollAt(delta, pos.vec2, deltaX)


#* ------------- input emulation: keyboard ------------- *#

proc updateModifiers(this: HeadlessUiWindow) =
  let pressed = this.siwinWindow.keyboard.pressed
  var modifiers: set[ModifierKey]
  if (pressed * {Key.lshift, Key.rshift}).len != 0: modifiers.incl ModifierKey.shift
  if (pressed * {Key.lcontrol, Key.rcontrol}).len != 0: modifiers.incl ModifierKey.control
  if (pressed * {Key.lalt, Key.ralt, Key.level3_shift, Key.level5_shift}).len != 0: modifiers.incl ModifierKey.alt
  if (pressed * {Key.lsystem, Key.rsystem}).len != 0: modifiers.incl ModifierKey.system
  this.siwinWindow.keyboard.modifiers = modifiers


proc keyPress*(this: HeadlessUiWindow, key: Key) =
  ## presses a key (and keeps it pressed until `keyRelease`)
  this.siwinWindow.keyboard.pressed.incl key
  this.updateModifiers()
  this.sendWindowEvent(KeyEvent(window: this.siwinWindow, key: key, pressed: true, modifiers: this.siwinWindow.keyboard.modifiers))


proc keyRelease*(this: HeadlessUiWindow, key: Key) =
  ## releases a key pressed by `keyPress`
  this.siwinWindow.keyboard.pressed.excl key
  this.updateModifiers()
  this.sendWindowEvent(KeyEvent(window: this.siwinWindow, key: key, pressed: false, modifiers: this.siwinWindow.keyboard.modifiers))


proc keyTap*(this: HeadlessUiWindow, key: Key) =
  ## presses and releases a key
  this.keyPress(key)
  this.keyRelease(key)


proc hotkey*(this: HeadlessUiWindow, keys: varargs[Key]) =
  ## presses all the given keys one by one (keeping them pressed) and releases them
  ## in reverse order, like a user does when entering a key combination
  for k in keys: this.keyPress(k)
  for i in countdown(keys.high, 0): this.keyRelease(keys[i])


proc textInput*(this: HeadlessUiWindow, text: string) =
  ## sends text as if it was typed using an input method
  this.sendWindowEvent(TextInputEvent(window: this.siwinWindow, text: text))


proc typeText*(this: HeadlessUiWindow, text: string) =
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


proc clickAt*(this: HeadlessUiWindow, obj: Uiobj, offset: Vec2 = vec2()) =
  ## clicks in the center of the component (plus `offset`)
  this.mouseClick(obj.centerOf + offset)


proc clickAt*(this: HeadlessUiWindow, obj: Uiobj, offsetX, offsetY: float32) =
  this.clickAt(obj, vec2(offsetX, offsetY))


proc clickAt*(this: HeadlessUiWindow, pos: Vec2) =
  ## clicks at the given window position
  this.mouseClick(pos)


proc hoverAt*(this: HeadlessUiWindow, obj: Uiobj, offset: Vec2 = vec2()) =
  ## moves the emulated mouse cursor to the center of the component (plus `offset`)
  this.mouseMoveTo(obj.centerOf + offset)


proc hoverAt*(this: HeadlessUiWindow, pos: Vec2) =
  this.mouseMoveTo(pos)


proc dragFromTo*(this: HeadlessUiWindow, fromObj, toObj: Uiobj, button: MouseButton = MouseButton.left, steps = 4) =
  ## drags from the center of one component to the center of another
  this.mouseDrag(fromObj.centerOf, toObj.centerOf, button, steps)


proc dragFromTo*(this: HeadlessUiWindow, fromPos, toPos: Vec2, button: MouseButton = MouseButton.left, steps = 4) =
  this.mouseDrag(fromPos, toPos, button, steps)


proc scrollTo*(this: HeadlessUiWindow, obj: Uiobj, delta: float, deltaX = 0'f64) =
  ## scrolls the mouse wheel over the component
  this.mouseScrollAt(delta, obj.centerOf, deltaX)


proc typeInto*(this: HeadlessUiWindow, obj: TextArea, text: string) =
  ## activates the text area (like a mouse click does) and types text into it
  this.clickAt(obj)
  this.typeText(text)


#* ------------- tree dump (machine-readable) ------------- *#

proc parseDumpedValue(value: string): JsonNode =
  ## converts a value printed by `$` into a json value when it is trivially parseable,
  ## otherwise keeps it as a string
  case value
  of "true": return newJBool(true)
  of "false": return newJBool(false)
  of "nil": return newJNull()
  else: discard

  try:
    return newJInt(value.parseInt)
  except CatchableError:
    discard

  try:
    return newJFloat(value.parseFloat)
  except CatchableError:
    discard

  result = newJString(value)


proc uiJson*(obj: Uiobj): JsonNode =
  ## builds a machine-readable json representation of a component tree.
  ## properties that differ from their default values are included as fields,
  ## nested components are placed into the "childs" array
  if obj == nil: return newJNull()

  result = %*{
    "type": obj.componentTypeName,
    "globalBox": [round(obj.globalX[]).int, round(obj.globalY[]).int, round(obj.w[]).int, round(obj.h[]).int],
    "localBox": [round(obj.x[]).int, round(obj.y[]).int, round(obj.w[]).int, round(obj.h[]).int],
  }

  for field in obj.formatFields():
    let i = field.find(':')
    if i == -1: continue
    let
      name = field[0 ..< i].strip
      value = field[(i+1) ..< field.len].strip
    if name == "box": continue  # it is already included as localBox
    result[name] = parseDumpedValue(value)

  var childs = newJArray()
  for child in obj.childs:
    childs.add child.uiJson
  if childs.len > 0:
    result["childs"] = childs


proc uiJsonRepr*(obj: Uiobj): string =
  ## `uiJson` pretty-printed as a json string
  pretty obj.uiJson


proc uiRepr*(obj: Uiobj): string =
  ## builds a compact machine-readable representation of a component tree, one component per line
  ## example: "UiRect(globalBox = [10, 20, 100x50], color = #FF0000)"
  if obj == nil: return "nil"

  result = obj.componentTypeName & "("
  result.add "globalBox = [" &
    $round(obj.globalX[]).int & ", " & $round(obj.globalY[]).int & ", " &
    $round(obj.w[]).int & "x" & $round(obj.h[]).int & "]"

  for field in obj.formatFields():
    let i = field.find(':')
    if i == -1: continue
    let
      name = field[0 ..< i].strip
      value = field[(i+1) ..< field.len].strip
    if name == "box": continue
    result.add ", " & name & " = " & value

  result.add ")"

  for child in obj.childs:
    for line in child.uiRepr.split('\n'):
      result.add "\n  " & line


proc findComponents*[T: Uiobj](obj: Uiobj, typ: typedesc[T]): seq[T] =
  ## returns all components that is of or inherited from `typ`
  if obj == nil: return
  if obj of T: result.add obj.T
  for child in obj.childs:
    result.add child.findComponents(typ)

proc findComponent*[T: Uiobj](obj: Uiobj, typ: typedesc[T]): T =
  ## returns first components that is of or inherited from `typ`
  if obj == nil: return nil
  if obj of T: return obj.T
  for child in obj.childs:
    let res = child.findComponent(typ)
    if res != nil: return res


proc findComponentsByExactType*(obj: Uiobj, name: string): seq[Uiobj] =
  ## returns all components in the subtree with componentTypeName == `name`
  ## (e.g. "Button", "UiText")
  if obj == nil: return
  if obj.componentTypeName == name: result.add obj
  for child in obj.childs:
    result.add child.findComponentsByExactType(name)

proc findComponentByExactType*(obj: Uiobj, name: string): Uiobj =
  ## returns the first component in the subtree with componentTypeName == `name`, nil if none
  if obj == nil: return nil
  if obj.componentTypeName == name: return obj
  for child in obj.childs:
    let res = child.findComponentByExactType(name)
    if res != nil: return res


proc componentAt*(obj: Uiobj, pos: Vec2): Uiobj =
  ## returns the deepest component in the subtree that contains `pos`
  ## (in window coordinates), nil if there is none.
  ## hidden/collapsed components and their subtrees are skipped
  proc impl(o: Uiobj): Uiobj =
    if o == nil: return nil
    if o.visibility[] in {hidden, collapsed}: return nil

    # children first (last drawn on top), so the deepest/frontmost match wins
    for i in countdown(o.childs.high, 0):
      let res = impl(o.childs[i])
      if res != nil: return res

    if pos.x in o.globalX[] .. (o.globalX[] + o.w[]) and
       pos.y in o.globalY[] .. (o.globalY[] + o.h[]):
      result = o

  result = impl(obj)


proc id*(obj: Uiobj): tuple[name: string, address: int] =
  ## alias for casting Uiobj to int
  ## this is recommended for obj identity comparison in check
  ((if obj == nil: "<nil>" else: obj.componentTypeName), cast[int](obj))


proc `~==`*(a: Color, b: Color, eps = 0.08): bool =
  ## returs if colors are almost equal
  ## this is recomended for use in check instead of `==`
  abs(a.r - b.r) < eps and
  abs(a.g - b.g) < eps and
  abs(a.b - b.b) < eps and
  abs(a.a - b.a) < eps

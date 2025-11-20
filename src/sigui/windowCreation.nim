# should be used instead of directly importing siwin
# todo: add windy support

import pkg/siwin/[windowOpengl, platforms]
import pkg/siwin/platforms/any/window
import pkg/[vmath, opengl]
import ./[uiobj, events]
import ./render/[contexts]


when defined(sigui_debug_useLogging):
  import logging


type
  UiWindow* = ref object of UiRoot
    siwinWindow*: Window
    clearColor*: Col

registerComponent UiWindow


let siwinGlobals = newSiwinGlobals()



when defined(sigui_debug_redrawInitiatedBy):
  import std/importutils
  privateAccess Window
  proc sigui_debug_redrawInitiatedBy_formatFunction(obj: Uiobj, alreadyRedrawing, hasWindow: bool): string


method doRedraw*(obj: UiWindow) =
  let win = obj.siwinWindow
  
  when defined(sigui_debug_redrawInitiatedBy):
    let alreadyRedrawing =
      if win != nil: win.redrawRequested
      else: false

    when defined(sigui_debug_useLogging):
      info(sigui_debug_redrawInitiatedBy_formatFunction(obj, alreadyRedrawing, win != nil))
    else:
      echo sigui_debug_redrawInitiatedBy_formatFunction(obj, alreadyRedrawing, win != nil)
  
  else:
    redraw win



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
  child.recieve(AttachedToRoot(root: this))



proc newUiWindow*(
  size = ivec2(1280, 720),
  title = "",
  screen: int32 = -1,
  fullscreen = false,
  resizable = true,
  frameless = false,
  transparent = false,
  vsync = true,

  class = "", # window class (used in x11), equals to title if not specified
): UiWindow =
  siwinGlobals.newOpenglWindow(
    size,
    title,
    screen,
    fullscreen,
    resizable,
    frameless,
    transparent,
    vsync,
    class,
  ).newUiWindow


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


template withWindow*(obj: Uiobj, winVar: untyped, body: untyped) =
  proc bodyProc(winVar {.inject.}: UiWindow) =
    body
  if obj.root != nil:
    bodyProc(obj.parentUiWindow)
  obj.onSignal.connect obj.eventHandler, proc(e: Signal) =
    if e of AttachedToRoot:
      bodyProc(obj.parentUiWindow)


method mouseState*(root: UiWindow): Mouse =
  root.siwinWindow.mouse

method keyboardState*(root: UiWindow): Keyboard =
  root.siwinWindow.keyboard

method touchscreenState*(root: UiWindow): TouchScreen =
  root.siwinWindow.touchScreen


method `cursor=`(root: UiWindow, v: Cursor) =
  root.siwinWindow.cursor = v



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


proc run*(win: UiWindow) =
  run win.siwinWindow


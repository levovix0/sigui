# should be used instead of directly importing siwin
# todo: add windy support

import std/[macros, sequtils]
import pkg/siwin/[windowOpengl, platforms]
import pkg/siwin/platforms/any/[window, clipboards]
import pkg/[chroma, vmath, opengl]
import ./[uiobj, uiobjMacros, events, properties]
import ./rendering/[any, current_backend]


when defined(sigui_debug_useLogging):
  import logging


type
  UiWindow* = ref object of UiRoot
    siwinWindow*: Window
    clearColor*: Color = color(0, 0, 0)

registerComponent UiWindow


var siwinGlobals: SiwinGlobals



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
      win.recieve(BeforeDraw(sender: win, ctx: win.ctx))
      win.draw(win.ctx)
      win.ctx.finishRendering()
    ,
    onTick: proc(e: TickEvent) =
      win.onTick.emit(e)
    ,
    onResize: proc(e: ResizeEvent) =
      win.wh = e.size.vec2
      win.ctx.resize(e.size)

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
    onDrop: proc(e: DropEvent) =
      win.recieve(WindowEvent(sender: win, event: e.toRef))
    ,
  )

proc newUiWindow*(siwinWindow: Window): UiWindow =
  result = UiWindow(siwinWindow: siwinWindow)
  loadExtensions()
  result.setupEventsHandling
  result.ctx = newRiceDrawContext()
  result.wh = siwinWindow.size.vec2

template newUiRoot*(siwinWindow: Window): UiWindow =
  newUiWindow(siwinWindow)



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
  preferedPlatform =
    when defined(linux) and defined(sigui_prefer_x11): Platform.x11
    else: defaultPreferedPlatform(),
): UiWindow =
  if siwinGlobals == nil:
    siwinGlobals = newSiwinGlobals(preferedPlatform)

  result = siwinGlobals.newOpenglWindow(
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

  result.parentRoot = result


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


method mouseState*(root: UiWindow): var Mouse =
  root.siwinWindow.mouse

method keyboardState*(root: UiWindow): var Keyboard =
  root.siwinWindow.keyboard

method touchscreenState*(root: UiWindow): var TouchScreen =
  root.siwinWindow.touchScreen


method `cursor=`(root: UiWindow, v: Cursor) =
  root.siwinWindow.cursor = v


method clipboardText*(root: UiWindow): string =
  root.siwinWindow.clipboard.text

method `clipboardText=`*(root: UiWindow, v: string) =
  root.siwinWindow.clipboard.text = v



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
  markCompleted(win)
  run win.siwinWindow



#----- utils -----

macro preview*(args: varargs[untyped]) =
  let body = args[^1]
  
  let win = ident("win")
  let obj = ident("obj")
  let margin = ident("margin")
  
  let windowCreate = nnkCall.newTree(bindSym("newUiWindow") & args[0..^2])
  let windowMkLayout = nnkCall.newTree(bindSym("makeLayout"), win, body)
  
  let setWindowSize =
    if args.anyIt(it.kind == nnkExprEqExpr and it.len == 2 and it[0] == ident("size")):
      newEmptyNode()
    else:
      quote do:
        var objSize = `obj`.wh
        if objSize.x == 0: objSize.x = 100
        if objSize.y == 0: objSize.y = 100
      
        `win`.wh = objSize + vec2(`margin`.left + `margin`.right, `margin`.top + `margin`.bottom)
        `win`.siwinWindow.size = `win`.wh.ivec2  # todo: siwin on Wayland ignores this resize
  
  let setClearColor =
    if args.anyIt(it.kind == nnkExprEqExpr and it.len == 2 and it[0] == ident("transparent") and it[1] == ident("true")):
      quote do:
        `win`.clearColor = color(0, 0, 0, 0)
    else:
      newEmptyNode()
  
  result = quote do:
    let `win` = `windowCreate`
    `setClearColor`

    `windowMkLayout`

    if `win`.childs.len > 0:
      let `obj` = `win`.childs[0]

      let `margin` = `obj`.margin
      
      `setWindowSize`
      
      `win`.childs[0].fill(`win`)
      `obj`.margin = `margin`
    
    run `win`


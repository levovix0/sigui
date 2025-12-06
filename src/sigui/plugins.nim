import ./window
import ./[uiobj, events, properties]
import ./render/contexts


type
  UiPluginEvent = enum
    plugin_x_changed
    plugin_y_changed
    plugin_w_changed
    plugin_h_changed

  UiPluginInterface* = object
    onDraw*:              proc(env: pointer, e {.byref.}: DrawContext)            {.cdecl.}
    onClose*:             proc(env: pointer, e {.byref.}: CloseEvent)             {.cdecl.}
    onTick*:              proc(env: pointer, e {.byref.}: TickEvent)              {.cdecl.}
    onResize*:            proc(env: pointer, e {.byref.}: ResizeEvent)            {.cdecl.}
    onWindowMove*:        proc(env: pointer, e {.byref.}: WindowMoveEvent)        {.cdecl.}
    onStateBoolChanged*:  proc(env: pointer, e {.byref.}: StateBoolChangedEvent)  {.cdecl.}
    onMouseMove*:         proc(env: pointer, e {.byref.}: MouseMoveEvent)         {.cdecl.}
    onMouseButton*:       proc(env: pointer, e {.byref.}: MouseButtonEvent)       {.cdecl.}
    onScroll*:            proc(env: pointer, e {.byref.}: ScrollEvent)            {.cdecl.}
    onClick*:             proc(env: pointer, e {.byref.}: ClickEvent)             {.cdecl.}
    onKey*:               proc(env: pointer, e {.byref.}: KeyEvent)               {.cdecl.}
    onTextInput*:         proc(env: pointer, e {.byref.}: TextInputEvent)         {.cdecl.}
    
    connectEvents*: proc(
      env: pointer,
      hostEnv: pointer,
      binding: proc(hostEnv: pointer, event: UiPluginEvent) {.cdecl.}
    ) {.cdecl.}

    emitEvent*: proc(
      env: pointer,
      event: UiPluginEvent,
    ) {.cdecl.}


  UiPlugin* = object
    env*: pointer
    iface*: ptr UiPluginInterface
    x*, y*, w*, h*: float32
    windowEvent_handled*: bool
    windowEvent_fake*: bool

  HostUiRoot* = ref HostUiRootObj
  HostUiRootObj* = object of UiRoot
    plugin: ptr UiPlugin

  PluginUiRoot* = ref object of UiRoot
    plugin*: UiPlugin
    iface*: UiPluginInterface


registerComponent HostUiRoot
registerComponent PluginUiRoot


method init(this: HostUiRoot) =
  procCall this.super.init()
  this.withRoot r:
    r.onTick.connectTo this, e:
      this.plugin.iface.onTick(this.plugin.env, e)
  
  template makeEvent(prop) =
    this.prop.changed.connectTo this:
      if this.plugin != nil:
        this.plugin.prop = this.prop[]
        this.plugin.iface.emitEvent(this.plugin.env, `plugin prop changed`)
  
  makeEvent x
  makeEvent y
  makeEvent w
  makeEvent h


method recieve(this: HostUiRoot, signal: Signal) =
  if signal of WindowEvent:
    let e = signal.WindowEvent.event
    template event(ev, E) =
      if e of E: this.plugin.iface.ev(this.plugin.env, ((ref E)e)[])
    
    if this.plugin != nil:
      this.plugin.windowEvent_fake = signal.WindowEvent.fake
      this.plugin.windowEvent_handled = signal.WindowEvent.handled
      
      event onClose, CloseEvent
      event onResize, ResizeEvent
      event onWindowMove, WindowMoveEvent
      event onStateBoolChanged, StateBoolChangedEvent
      event onMouseMove, MouseMoveEvent
      event onMouseButton, MouseButtonEvent
      event onScroll, ScrollEvent
      event onClick, ClickEvent
      event onKey, KeyEvent
      event onTextInput, TextInputEvent
      
      signal.WindowEvent.fake = this.plugin.windowEvent_fake
      signal.WindowEvent.handled = this.plugin.windowEvent_handled


method draw(this: HostUiRoot, ctx: DrawContext) =
  this.drawBefore(ctx)
  if this.visibility != Visibility.collapsed:
    this.plugin.iface.onDraw(this.plugin.env, ctx)
  this.drawAfter(ctx)


proc setPlugin*(this: HostUiRoot, plugin: ptr UiPlugin) =
  this.plugin = plugin
  if this.plugin != nil:
    this.plugin.iface.connectEvents(
      this.plugin.env,
      cast[pointer](this),
      proc(hostEnv: pointer, event: UiPluginEvent) {.cdecl.} =
        let this = cast[HostUiRoot](hostEnv)
        
        case event
        of plugin_x_changed: this.x[] = this.plugin.x
        of plugin_y_changed: this.y[] = this.plugin.y
        of plugin_w_changed: this.w[] = this.plugin.w
        of plugin_h_changed: this.h[] = this.plugin.h
    )



proc newPluginUiRoot*(): PluginUiRoot =
  new result

  template event(ev, E) =
    result.iface.ev = proc(env: pointer, e {.byref.}: E) {.cdecl.} =
      let this = cast[PluginUiRoot](env)
      let refE = new (ref E)
      refE[] = e
      let eventSignal = WindowEvent(
        event: refE,
        fake: this.plugin.windowEvent_fake,
        handled: this.plugin.windowEvent_handled
      )
      this.recieve(eventSignal)
      this.plugin.windowEvent_fake = eventSignal.fake
      this.plugin.windowEvent_handled = eventSignal.handled

  event onClose, CloseEvent
  event onResize, ResizeEvent
  event onWindowMove, WindowMoveEvent
  event onStateBoolChanged, StateBoolChangedEvent
  event onMouseMove, MouseMoveEvent
  event onMouseButton, MouseButtonEvent
  event onScroll, ScrollEvent
  event onClick, ClickEvent
  event onKey, KeyEvent
  event onTextInput, TextInputEvent

  result.iface.onTick = proc(env: pointer, e {.byref.}: TickEvent) {.cdecl.} =
    let this = cast[PluginUiRoot](env)
    this.onTick.emit(e)

  result.iface.onDraw = proc(env: pointer, e {.byref.}: DrawContext) {.cdecl.} =
    let this = cast[PluginUiRoot](env)
    this.draw(e)

  result.iface.connectEvents = proc(
    env: pointer,
    hostEnv: pointer,
    binding: proc(hostEnv: pointer, event: UiPluginEvent) {.cdecl.}
  ) {.cdecl.} =
    let this = cast[PluginUiRoot](env)

    template makeEvent(prop) =
      this.prop.changed.connectTo this:
        this.plugin.prop = this.prop[]
        binding(hostEnv, `plugin prop changed`)

      this.plugin.prop = this.prop[]
      binding(hostEnv, `plugin prop changed`)

    makeEvent x
    makeEvent y
    makeEvent w
    makeEvent h

  result.iface.emitEvent = proc(
    env: pointer,
    event: UiPluginEvent,
  ) {.cdecl.} =
    let this = cast[PluginUiRoot](env)

    template makeEvent(prop) =
      this.prop[] = this.plugin.prop

    case event
    of plugin_x_changed: makeEvent x
    of plugin_y_changed: makeEvent y
    of plugin_w_changed: makeEvent w
    of plugin_h_changed: makeEvent h
  
  result.plugin.env = cast[pointer](result)
  result.plugin.iface = result.iface.addr


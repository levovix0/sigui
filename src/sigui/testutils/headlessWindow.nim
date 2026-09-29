import std/[times]
import pkg/[vmath, chroma, opengl]
import pkg/siwin/[platforms, offscreen]
import pkg/siwin/platforms/any/window
import pkg/pixie/[images, imageloading]
import ../[uiobj, uibase, window, windowCreation]
import ../rendering/[current_backend]

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
  raw.projection = translate(vec3(-1, 1, 0)) * scale(vec3(2 / size.x.float32, -2 / size.y.float32, 1))

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


proc pixelColor*(this: HeadlessUiWindow, pos: Vec2): Color =
  ## draws one frame and returns the color of the pixel at `pos` (in component coordinates)
  this.root.HeadlessUiWindow.windowPixelColor(pos.posToGlobal(this))

proc pixelColor*(this: Uiobj, pos: Vec2): Color =
  ## draws one frame and returns the color of the pixel at `pos` (in component coordinates)
  this.root.HeadlessUiWindow.windowPixelColor(pos.posToGlobal(this))

proc pixelColor*(this: Uiobj, x, y: SomeInteger|SomeFloat): Color =
  ## draws one frame and returns the color of the pixel at `pos` (in component coordinates)
  this.pixelColor(vec2(x.float32, y.float32))


#* ------------- frame loop ------------- *#

proc tick*(this: UiWindow, deltaTime = initDuration(milliseconds = 16)) =
  ## emits onTick with the given deltaTime; animations and transitions are updated by this
  this.onTick.emit(TickEvent(window: this.siwinWindow, deltaTime: deltaTime))


proc frame*(this: UiWindow, deltaTime = initDuration(milliseconds = 16)) =
  ## performs a full frame as a real window does: tick + render
  this.tick(deltaTime)
  this.render()


proc settleAnimations*(this: UiWindow, duration = initDuration(seconds = 10)) =
  ## same as frame, but has much longer step duration, so most of the animations will be finished
  this.tick(duration)
  this.render()


proc tickUntil*(
  this: UiWindow,
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
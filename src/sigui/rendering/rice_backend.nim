import std/[unicode]
import pkg/[chroma, bumpy]
import pkg/rice/[contexts as riceContexts, gl, primitivesAA, paths, contextutils, antialiasing, transform, rasterTexts]
import pkg/pixie/[fonts as pixieFonts, paths as pixiePaths, fontloading]
import pkg/pixie/fileformats/[svg]
import pkg/pixie/rendering/[svg, fontpoly, pathpoly]
import ./any

export riceContexts except DrawContext
export gl

type
  RiceDrawContext* = ref object of any.DrawContext
    raw*: riceContexts.DrawContext
    clipStack*: seq[ClipRectState]


  ClipRectState* = object
    ef*: FrameBuffer
    psh*: PushedFrameBuffer
    prevOffset*: Vec2
    prevProjectionMatrix*: Mat4
    pos*: Vec2
    size*: Vec2
    radius*: float32


  RiceDrawContextImage* = ref object of any.DrawContextImage
    tex*: Texture
    imageSize*: IVec2
  

  RiceTextDrawContext* = ref object of any.TextDrawContext
    raw*: rasterTexts.TextDrawContext
    pos*: Vec2


  RicePathCache* = ref object of any.PathCache
    mesh*: Mesh
    offset*: Vec2
    logicalSize*: Vec2
    aafb*: AntialiasedFramebuffer



#* ------------- window ------------- *#

proc scaleOf(ctx: RiceDrawContext): float32 {.inline.} =
  ## device pixels per logical pixel
  max(ctx.scale, 0.0001'f32)

proc snappedToDevice(v: Vec2, s: float32): Vec2 {.inline.} =
  ## snaps a logical coordinate to the device pixel grid (result is in logical pixels)
  (v * s).round / s


method resize*(ctx: RiceDrawContext, size: IVec2) =
  ## `size` is the size of the drawing area in device pixels
  let s = ctx.scaleOf
  glViewport 0, 0, size.x, size.y
  assert ctx.raw.fbo == 0
  ctx.raw.fboSize = size
  ctx.raw.updateDrawingAreaSize(size)

  # logical coordinates of the [0 .. size/s] range are mapped to [-1 .. 1]
  ctx.raw.projection = combine(
    scale(vec3(2 * s / size.x.float32, -2 * s / size.y.float32, 1)),
    translate(vec3(-1, 1, 0)),
  )

method finishRendering*(ctx: RiceDrawContext) =
  ctx.raw.deleteUnusedFrameBuffers()
  ctx.raw.markAllFreeFrameBuffersAsUnused()

method clear*(ctx: RiceDrawContext, color: Color) =
  glClearColor(color.r, color.g, color.b, color.a)
  glClear(GL_COLOR_BUFFER_BIT)


#* ------------- images ------------- *#

method loadImage*(ctx: RiceDrawContext, filepath: string): DrawContextImage =
  ## todo

method newImage*(ctx: RiceDrawContext, size: IVec2): any.DrawContextImage =
  result = RiceDrawContextImage(tex: newTexture(), imageSize: size)
  loadTexture(result.RiceDrawContextImage.tex.raw, size, nil)

method imageFromBuffer*(ctx: RiceDrawContext, size: IVec2, data: pointer): any.DrawContextImage =
  ## data is pointer to uint8 rgba pixels
  result = RiceDrawContextImage(tex: newTexture(), imageSize: size)
  loadTexture(result.RiceDrawContextImage.tex.raw, size, data)

method parseSvg*(ctx: RiceDrawContext, size: IVec2, data: string): any.DrawContextImage =
  if data == "": return nil
  let img = data.parseSvg(size.x, size.y).newImage
  RiceDrawContextImage(
    tex: newTexture(img),
    imageSize: ivec2(img.width.int32, img.height.int32),
  )

method size*(image: RiceDrawContextImage): IVec2 = image.imageSize


#* ------------- fonts and text ------------- *#

proc readTypeface_impl(filepath: string): Typeface {.exportc: "sigui_pixie_readTypeface".} =
  fontloading.readTypeface(filepath)

proc parseTtf_impl(data: string): Typeface {.exportc: "sigui_pixie_parseTtf".} =
  fontloading.parseTtf(data)


proc computeBounds_impl*(arrangement: Arrangement): Rect {.exportc: "sigui_pixie_arrangement_computeBounds".} =
  fontpoly.computeBounds(arrangement)


proc rasterFontForDrawing(ctx: RiceDrawContext, font: Font): Font {.inline.} =
  ## font for glyph rasterization: glyphs are rasterized at device resolution,
  ## so the font size must be scaled by the UI scale
  let s = ctx.scaleOf
  if s == 1'f32: font
  else: font.typeface.withSize(font.size * s)


method drawRasterText*(
  ctx: RiceDrawContext,
  pos: Vec2,
  arrangement: Arrangement,
  color: Color,
  origin: Vec2 = vec2(0, 0),
  exactBoundaries = false,
  transform = mat4(),
) =
  if arrangement == nil or arrangement.fonts.len == 0: return

  let s = ctx.scaleOf
  var raw = ctx.raw.startRasterTextDrawing(ctx.rasterFontForDrawing(arrangement.fonts[0]))
  raw.color.uniform = color.vec4

  let posNdc = ctx.raw.viewportToGlMatrix * transform * snappedToDevice(pos + ctx.raw.offset, s).vec3(0)
  let box = fontpoly.computeBounds(arrangement)  # logical pixels; todo: computeBounds is slow

  let offset =
    if exactBoundaries: (vec2(box.x, -box.y) + vec2(box.w, -box.h) * origin) * s
    else: (vec2(box.w + box.x, -(box.h + box.y)) * origin) * s

  for i, rune in arrangement.runes:
    let selectionRect = arrangement.selectionRects[i]
    let glyphOffset = (vec2(selectionRect.x, -selectionRect.y) * s).round
    ctx.raw.fastRasterDrawRune(
      rune,
      rect(posNdc.xy + glyphOffset * ctx.raw.px - offset * ctx.raw.px, selectionRect.wh * s),
      raw,
    )

  ctx.raw.endRasterTextDrawing()


method startRasterTextDrawing*(
  ctx: RiceDrawContext,
  font: Font,
  origin: Vec2,
): any.TextDrawContext =
  let res = RiceTextDrawContext(raw: ctx.raw.startRasterTextDrawing(ctx.rasterFontForDrawing(font)))
  res.pos = (ctx.raw.viewportToGlMatrix * snappedToDevice(origin + ctx.raw.offset, ctx.scaleOf).vec3(0)).xy
  res

method endRasterTextDrawing*(ctx: RiceDrawContext) =
  ctx.raw.endRasterTextDrawing()

method fastRasterDrawRune*(
  ctx: RiceDrawContext,
  rune: Rune,
  rect: Rect,
  context: any.TextDrawContext,
) =
  ## `rect` is in logical pixels; xy is the glyph offset relative to
  ## the origin that was passed to startRasterTextDrawing
  let s = ctx.scaleOf
  let glyphOffset = (vec2(rect.x, -rect.y) * s).round
  ctx.raw.fastRasterDrawRune(
    rune,
    rect(context.RiceTextDrawContext.pos + glyphOffset * ctx.raw.px, rect.wh * s),
    context.RiceTextDrawContext.raw,
  )

method `color=`(context: RiceTextDrawContext, v: Color) =
  context.raw.color.uniform = v.vec4


#* ------------- drawing ------------- *#

method fillRect*(
  ctx: RiceDrawContext,
  rect: Rect,
  color: Color,
  radius: float32 = 0,
  blend: bool = true,
) =
  let s = ctx.scaleOf
  ctx.raw.fillRect(
    ((rect.xy + ctx.raw.offset) * s).round, rect.wh * s, color, radius * s, blend
  )

method drawRect*(
  ctx: RiceDrawContext,
  rect: Rect,
  color: Color,
  thickness: float32 = 0,
  radius: float32 = 0,
  blend: bool = true,
  dashingPattern: array[2, float32] = [1'f32, 0],
) =
  let s = ctx.scaleOf
  if dashingPattern[0] > 0 and dashingPattern[1] > 0 and thickness > 0:
    # dashed border, drawn as a stroke of a rounded rect path with dashes
    # todo: antialiasing
    # the mesh is drawn through the projection matrix, so it can stay in logical pixels
    let t = thickness / 2
    var path = pixiePaths.newPath()
    path.roundedRect(
      rect(rect.xy + t, rect.wh - t * 2),
      max(0'f32, radius - t), max(0'f32, radius - t),
      max(0'f32, radius - t), max(0'f32, radius - t),
    )
    let mesh = path.toStrokeMesh(
      thickness, pixiePaths.ButtCap,
      dashes = @[dashingPattern[0], dashingPattern[1]],
    )

    ctx.raw.withPushPopIf BlendRgbx, blend:
      ctx.raw.fill2dMeshFlat(mesh, color, mat4())

  else:
    ctx.raw.drawRect(
      ((rect.xy + ctx.raw.offset) * s).round, rect.wh * s, color, thickness * s, radius * s, blend
    )

method drawImage*(
  ctx: RiceDrawContext,
  rect: Rect,
  image: any.DrawContextImage,
  color: Color,
  radius: float32 = 0,
  blend: bool = true,
  flipY = false,
  imagePos = vec2(),
  imageSize = vec2(),
) =
  let s = ctx.scaleOf
  ctx.raw.drawImage(
    ((rect.xy + ctx.raw.offset) * s).round, rect.wh * s, image.RiceDrawContextImage.tex.raw, color,
    radius * s, blend, flipY = flipY, imagePos = imagePos, imageSize = imageSize,
  )

method drawIcon*(
  ctx: RiceDrawContext,
  rect: Rect,
  mask: any.DrawContextImage,
  color: Color,
  radius: float32 = 0,
  flipY = false,
) =
  # todo: rice drawIcon does not support flipY
  let s = ctx.scaleOf
  ctx.raw.drawIcon(
    ((rect.xy + ctx.raw.offset) * s).round, rect.wh * s, mask.RiceDrawContextImage.tex.raw, color, radius * s, true, 0'f32
  )

method drawShadowRect*(
  ctx: RiceDrawContext,
  rect: Rect,
  color: Color,
  blurRadius: float32,
  radius: float32 = 0,
) =
  let s = ctx.scaleOf
  ctx.raw.drawShadowRect(
    ((rect.xy + ctx.raw.offset) * s).round, rect.wh * s, blurRadius * s, color, radius * s
  )


#* ------------- clip rects ------------- *#

method pushClipRect*(
  ctx: RiceDrawContext,
  rect: Rect,
  radius: float32 = 0,
) =
  # todo: if radius = 0, use glViewport for clipping
  let s = ctx.scaleOf
  # the framebuffer content is in device pixels for sharpness
  let sizeI = ivec2((rect.w * s).round.int32, (rect.h * s).round.int32)
  let ef = ctx.raw.requireFrameBuffer(sizeI)
  let psh = ctx.raw.push ef

  # children of the clip rect are drawn in logical coordinates (relative to the clip rect),
  # so translate them into the framebuffer
  let prevOffset = ctx.raw.offset
  let prevProjectionMatrix = ctx.raw.projectionMatrix
  ctx.raw.offset = -rect.xy
  # logical coordinates of the [0 .. rect.wh] range are mapped to the framebuffer [-1 .. 1]
  ctx.raw.projection = combine(
    scale(vec3(2 * s / sizeI.x.float32, -2 * s / sizeI.y.float32, 1)),
    translate(vec3(-1, 1, 0)),
  )

  ctx.clipStack.add ClipRectState(
    ef: ef, psh: psh,
    prevOffset: prevOffset,
    prevProjectionMatrix: prevProjectionMatrix,
    pos: rect.xy, size: rect.wh, radius: radius,
  )

  glClearColor(0, 0, 0, 0)
  glClear(GL_COLOR_BUFFER_BIT)

method popClipRect*(ctx: RiceDrawContext) =
  let state = ctx.clipStack.pop()
  let s = ctx.scaleOf
  ctx.raw.pop state.psh
  ctx.raw.free state.ef
  ctx.raw.offset = state.prevOffset
  ctx.raw.projection = state.prevProjectionMatrix

  ctx.raw.drawImage(
    ((state.pos + ctx.raw.offset) * s).round, state.size * s, state.ef.tex.raw, color(1, 1, 1, 1),
    state.radius * s, true, flipY = true, imageSize = state.ef.size.vec2,
  )


#* ------------- paths ------------- *#

proc computeBounds_impl(path: Path): Rect {.exportc: "sigui_pixie_path_computeBounds".} =
  pathpoly.computeBounds(path)

method newPathCache*(ctx: RiceDrawContext): any.PathCache =
  RicePathCache()

method update*(
  cache: RicePathCache,
  ctx: any.DrawContext,
  path: any.Path,
  transform: Mat3,
  kind: PathKind,
  strokeWidth: float32,
  lineCap: any.LineCap,
  lineJoin: any.LineJoin,
) =
  cache.mesh = Mesh()
  if path == nil: return
  let raw = ctx.RiceDrawContext.raw
  let s = ctx.RiceDrawContext.scaleOf

  let bounds = path.computeBounds(transform)
  var boundsI = (x: bounds.x.floor.int32, y: bounds.y.floor.int32, w: bounds.w.ceil.int32, h: bounds.h.ceil.int32)

  let grow =
    if kind == FillPath: 0'i32
    else: strokeWidth.ceil.int32
  boundsI.x -= grow
  boundsI.y -= grow
  boundsI.w += grow * 2
  boundsI.h += grow * 2
  # todo: do not draw outside window

  cache.offset = vec2(boundsI.x.float32, boundsI.y.float32)
  cache.logicalSize = vec2(boundsI.w.float32, boundsI.h.float32)
  # the framebuffer content is in device pixels for sharpness
  raw.resize(cache.aafb, ivec2((boundsI.w.float32 * s).round.int32, (boundsI.h.float32 * s).round.int32))

  if boundsI.w <= 0 or bounds.h <= 0:
    return

  case kind
  of StrokePath:
    cache.mesh = path.toStrokeMesh(
      strokeWidth,
      pixiePaths.LineCap(ord(lineCap)),
      pixiePaths.LineJoin(ord(lineJoin)),
    )
  of FillPath:
    cache.mesh = path.toMesh()

method draw*(
  cache: RicePathCache,
  ctx: any.DrawContext,
  pos: Vec2,
  transform: Mat3,
  color: Color,
  antialiasing = true,
) =
  let raw = ctx.RiceDrawContext.raw
  let s = ctx.RiceDrawContext.scaleOf

  # Mat3 is treated as a 2d affine transform (row-major translation)
  let meshTransform = mat4(
    transform[0,0], transform[0,1], 0, transform[0,2],
    transform[1,0], transform[1,1], 0, transform[1,2],
    0,            0,            1, 0,
    transform[2,0], transform[2,1], 0, 1,
  )

  raw.withPushPopIf BlendRgbx, color.a != 1 or antialiasing:
    var prevFbo: PushedAntialiasedFrameBuffer
    if antialiasing:
      prevFbo = raw.push(cache.aafb)
      glClearColor(0, 0, 0, 0)
      glClear(GlColorBufferBit)

    let prevM = raw.viewportToGlMatrix
    # mesh vertices are in logical pixels, the framebuffer content is in device pixels
    raw.viewportToGlMatrix =
      translate(-1, -1) *
      scale(2/cache.logicalSize.x.float32, 2/cache.logicalSize.y.float32) *
      translate(vec3((if antialiasing: -cache.offset else: vec2()), 0))
    raw.fill2dMeshFlat(cache.mesh, color, meshTransform)
    raw.viewportToGlMatrix = prevM

    if antialiasing:
      raw.pop prevFbo
      raw.draw(
        cache.aafb,
        translate(snappedToDevice(pos + cache.offset, s).vec3(0)) *
        scale(vec3(1/s, 1/s, 1)),
      )



proc newRiceDrawContext*(): RiceDrawContext =
  result = RiceDrawContext(raw: riceContexts.newDrawContext())

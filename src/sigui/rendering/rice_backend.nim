import rice/[gl, primitivesAA, paths, contextutils, antialiasing, transform, rasterTexts]
import rice/contexts as riceContexts
import pkg/pixie as pixie  # readImage, decodeImage
import pkg/pixie/[fonts as pixieFonts, paths as pixiePaths]
import pkg/pixie/fileformats/[svg]
import ./any

export riceContexts except DrawContext
export gl

type
  RiceDrawContext* = ref object of any.DrawContext
    raw*: riceContexts.DrawContext
    clipStack: seq[ClipRectState]

  ClipRectState = object
    ef: FrameBuffer
    psh: PushedFrameBuffer
    prevViewportMatrix: Mat4
    prevProjectionMatrix: Mat4
    pos: Vec2
    size: Vec2
    radius: float32

  RiceDrawContextImage* = ref object of any.DrawContextImage
    tex*: Texture
    imageSize*: IVec2

  PixieFontFamily* = ref object of any.FontFamily
    raw*: pixieFonts.Typeface

  PixieFontFace* = ref object of any.FontFace
    raw*: pixieFonts.Font
    rawFamily*: PixieFontFamily

  RicePath* = ref object of any.Path
    raw*: pixiePaths.Path

  RicePathCache* = ref object of any.PathCache
    mesh: Mesh
    offset: Vec2
    aafb: AntialiasedFramebuffer



#* ------------- window ------------- *#

method resize*(ctx: RiceDrawContext, size: IVec2) =
  glViewport 0, 0, size.x, size.y
  assert ctx.raw.fbo == 0
  ctx.raw.fboSize = size
  ctx.raw.updateDrawingAreaSize(size)

  ctx.raw.projection = combine(
    scale(vec3(2 / size.x, -2 / size.y, 1)),
    translate(vec3(-1, 1, 0)),
  )

method finishRendering*(ctx: RiceDrawContext) =
  ctx.raw.deleteUnusedFrameBuffers()
  ctx.raw.markAllFreeFrameBuffersAsUnused()

method clear*(ctx: RiceDrawContext, color: Color) =
  glClearColor(color.r, color.g, color.b, color.a)
  glClear(GL_COLOR_BUFFER_BIT)


#* ------------- images ------------- *#

method loadImage*(ctx: RiceDrawContext, filepath: string): any.DrawContextImage =
  let img = pixie.readImage(filepath)
  RiceDrawContextImage(
    tex: newTexture(img),
    imageSize: ivec2(img.width.int32, img.height.int32),
  )

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

method loadFont*(ctx: RiceDrawContext, filepath: string): any.FontFamily =
  PixieFontFamily(raw: pixieFonts.readTypeface(filepath))

method parseTtf*(ctx: RiceDrawContext, data: string): any.FontFamily =
  PixieFontFamily(raw: pixieFonts.parseTtf(data))

method family*(font: PixieFontFace): FontFamily = font.rawFamily
method size*(font: PixieFontFace): float32 = font.raw.size
method lineHeight*(font: PixieFontFace): float32 = font.raw.lineHeight
method underline*(font: PixieFontFace): bool = font.raw.underline
method strikethrough*(font: PixieFontFace): bool = font.raw.strikethrough
method noKerningAdjustments*(font: PixieFontFace): bool = font.raw.noKerningAdjustments

method `family=`*(font: PixieFontFace, v: FontFamily) =
  font.raw.typeface = v.PixieFontFamily.raw
  font.rawFamily = v.PixieFontFamily

method `size=`*(font: PixieFontFace, v: float32) = font.raw.size = v
method `lineHeight=`*(font: PixieFontFace, v: float32) = font.raw.lineHeight = v
method `underline=`*(font: PixieFontFace, v: bool) = font.raw.underline = v
method `strikethrough=`*(font: PixieFontFace, v: bool) = font.raw.strikethrough = v
method `noKerningAdjustments=`*(font: PixieFontFace, v: bool) = font.raw.noKerningAdjustments = v

method withSize*(family: PixieFontFamily, size: float32): FontFace =
  let res = PixieFontFace(raw: newFont(family.raw), rawFamily: family)
  res.raw.size = size
  res

method textArrangement*(
  ctx: RiceDrawContext,
  font: FontFace,
  text: sink string,
  bounds = vec2(0, 0),
  hAlign = any.LeftAlign,
  vAlign = any.TopAlign,
  wrap = true,
): TextArrangement =
  if font == nil or font.family == nil: return nil

  let raw = pixieFonts.typeset(
    [pixieFonts.newSpan(text, font.PixieFontFace.raw)], bounds,
    pixieFonts.HorizontalAlignment(ord(hAlign)),
    pixieFonts.VerticalAlignment(ord(vAlign)),
    wrap,
  )

  result = TextArrangement(
    lines: move raw.lines,
    spans: move raw.lines,
    runes: move raw.runes,
    positions: move raw.positions,
    selectionRects: move raw.selectionRects,
  )
  for f in raw.fonts:
    result.fonts.add PixieFontFace(raw: f)

method drawRasterText*(
  ctx: RiceDrawContext,
  pos: Vec2,
  arrangement: TextArrangement,
  color: Color,
  origin: Vec2 = vec2(0, 0),
  exactBoundaries = false,
  transform = mat4(),
) =
  if arrangement == nil: return
  
  let pixarr = Arrangement(
    lines: move arrangement.lines,
    spans: move arrangement.lines,
    runes: move arrangement.runes,
    positions: move arrangement.positions,
    selectionRects: move arrangement.selectionRects,
  )
  for f in arrangement.fonts:
    pixarr.fonts.add f.PixieFontFace.raw

  ctx.raw.drawRasterText(
    pos.vec3(0), pixarr, color.vec4,
    origin, exactBoundaries, transform,
  )

  arrangement.lines = move pixarr.lines
  arrangement.spans = move pixarr.spans
  arrangement.runes = move pixarr.runes
  arrangement.positions = move pixarr.positions
  arrangement.selectionRects = move pixarr.selectionRects


#* ------------- drawing ------------- *#

method fillRect*(
  ctx: RiceDrawContext,
  pos: Vec2,
  size: Vec2,
  color: Color,
  radius: float32 = 0,
  blend: bool = true,
) =
  ctx.raw.fillRect(pos, size, color, radius, blend)

method drawRect*(
  ctx: RiceDrawContext,
  pos: Vec2,
  size: Vec2,
  color: Color,
  thickness: float32 = 0,
  radius: float32 = 0,
  blend: bool = true,
  dashingPattern: array[2, float32] = [1'f32, 0],
) =
  if dashingPattern[0] > 0 and dashingPattern[1] > 0 and thickness > 0:
    # dashed border, drawn as a stroke of a rounded rect path with dashes
    # todo: antialiasing
    let t = thickness / 2
    var path = pixiePaths.newPath()
    path.roundedRect(
      rect(pos + t, size - t * 2),
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
    ctx.raw.drawRect(pos, size, color, thickness, radius, blend)

method drawImage*(
  ctx: RiceDrawContext,
  pos: Vec2,
  size: Vec2,
  image: any.DrawContextImage,
  color: Color,
  radius: float32 = 0,
  blend: bool = true,
  flipY = false,
  imagePos = vec2(),
  imageSize = vec2(),
) =
  ctx.raw.drawImage(
    pos, size, image.RiceDrawContextImage.tex.raw, color,
    radius, blend, flipY = flipY, imagePos = imagePos, imageSize = imageSize,
  )

method drawIcon*(
  ctx: RiceDrawContext,
  pos: Vec2,
  size: Vec2,
  mask: any.DrawContextImage,
  color: Color,
  radius: float32 = 0,
  flipY = false,
) =
  # todo: rice drawIcon does not support flipY
  ctx.raw.drawIcon(pos, size, mask.RiceDrawContextImage.tex.raw, color, radius, true, 0'f32)

method drawShadowRect*(
  ctx: RiceDrawContext,
  pos: Vec2,
  size: Vec2,
  color: Color,
  blurRadius: float32,
  radius: float32 = 0,
) =
  ctx.raw.drawShadowRect(pos, size, color, blurRadius, radius)


#* ------------- clip rects ------------- *#

method pushClipRect*(
  ctx: RiceDrawContext,
  pos: Vec2,
  size: Vec2,
  radius: float32 = 0,
) =
  # todo: if radius = 0, use glViewport for clipping
  let sizeI = ivec2(size.x.round.int32, size.y.round.int32)
  let ef = ctx.raw.requireFrameBuffer(sizeI)
  let psh = ctx.raw.push ef

  # children of the clip rect are drawn in global coordinates,
  # so translate them into the framebuffer
  let prevViewportMatrix = ctx.raw.viewportMatrix
  let prevProjectionMatrix = ctx.raw.projectionMatrix
  ctx.raw.viewport = translate(vec3(-pos.x, -pos.y, 0))
  ctx.raw.projection = combine(
    scale(vec3(2 / size.x, -2 / size.y, 1)),
    translate(vec3(-1, 1, 0)),
  )
  ctx.raw.wh = vec2(pos.x + size.x / 2, -(pos.y + size.y / 2))
  # note: ctx.raw.px is already set by push, because it is the same for any offset

  ctx.clipStack.add ClipRectState(
    ef: ef, psh: psh,
    prevViewportMatrix: prevViewportMatrix,
    prevProjectionMatrix: prevProjectionMatrix,
    pos: pos, size: size, radius: radius,
  )

  glClearColor(0, 0, 0, 0)
  glClear(GL_COLOR_BUFFER_BIT)

method popClipRect*(ctx: RiceDrawContext) =
  let state = ctx.clipStack.pop()
  ctx.raw.pop state.psh
  ctx.raw.free state.ef
  ctx.raw.viewport = state.prevViewportMatrix
  ctx.raw.projection = state.prevProjectionMatrix

  ctx.raw.drawImage(
    state.pos, state.size, state.ef.tex.raw, color(1, 1, 1, 1),
    state.radius, true, flipY = true, imageSize = state.ef.size.vec2,
  )


#* ------------- paths ------------- *#

method newPath*(ctx: RiceDrawContext): any.Path =
  RicePath(raw: pixiePaths.newPath())

method parsePath*(ctx: RiceDrawContext, s: string): any.Path =
  RicePath(raw: pixiePaths.parsePath(s))

method newPathCache*(ctx: RiceDrawContext): any.PathCache =
  RicePathCache()


method moveTo*(path: RicePath, v: Vec2) = path.raw.moveTo(v)
method lineTo*(path: RicePath, v: Vec2) = path.raw.lineTo(v)
method bezierCurveTo*(path: RicePath, ctrl1, ctrl2, to: Vec2) = path.raw.bezierCurveTo(ctrl1, ctrl2, to)
method quadraticCurveTo*(path: RicePath, ctrl, to: Vec2) = path.raw.quadraticCurveTo(ctrl, to)
method ellipticalArcTo*(
  path: RicePath,
  rx, ry: float32,
  xAxisRotation: float32,
  largeArcFlag, sweepFlag: bool,
  to: Vec2,
) = path.raw.ellipticalArcTo(rx, ry, xAxisRotation, largeArcFlag, sweepFlag, to.x, to.y)
method arc*(path: RicePath, pos: Vec2, r: float32, a: Vec2, ccw = false) = path.raw.arc(pos, r, a, ccw)
method arcTo*(path: RicePath, a, b: Vec2, r: float32) = path.raw.arcTo(a, b, r)
method closePath*(path: RicePath) = path.raw.closePath()

method rect*(path: RicePath, rect: Rect, clockwise = true) = path.raw.rect(rect, clockwise)
method roundedRect*(path: RicePath, rect: Rect, nw, ne, se, sw: float32, clockwise = true) =
  path.raw.roundedRect(rect, nw, ne, se, sw, clockwise)
method ellipse*(path: RicePath, center: Vec2, rx, ry: float32) = path.raw.ellipse(center, rx, ry)
method circle*(path: RicePath, center: Vec2, r: float32) = path.raw.ellipse(center, r, r)
method polygon*(path: RicePath, pos: Vec2, r: float32, n: int) = path.raw.polygon(pos, r, n)

method addPath*(path: RicePath, other: any.Path) = path.raw.addPath(other.RicePath.raw)
method transform*(path: RicePath, mat: Mat3) = path.raw.transform(mat)
method copy*(path: RicePath): any.Path = RicePath(raw: path.raw.copy())

method computeBounds*(path: RicePath, transform = mat3()): Rect =
  path.raw.computeBounds(transform)


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

  let bounds = path.RicePath.raw.computeBounds(transform)
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
  raw.resize(cache.aafb, ivec2(boundsI.w, boundsI.h))

  if boundsI.w <= 0 or bounds.h <= 0:
    return

  case kind
  of StrokePath:
    cache.mesh = path.RicePath.raw.toStrokeMesh(
      strokeWidth,
      pixiePaths.LineCap(ord(lineCap)),
      pixiePaths.LineJoin(ord(lineJoin)),
    )
  of FillPath:
    cache.mesh = path.RicePath.raw.toMesh()

method draw*(
  cache: RicePathCache,
  ctx: any.DrawContext,
  pos: Vec2,
  transform: Mat3,
  color: Color,
  antialiasing = true,
) =
  let raw = ctx.RiceDrawContext.raw

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
    raw.viewportToGlMatrix =
      translate(-1, -1) *
      scale(2/cache.aafb.size.x.float32, 2/cache.aafb.size.y.float32) *
      translate(vec3((if antialiasing: -cache.offset else: vec2()), 0))
    raw.fill2dMeshFlat(cache.mesh, color, meshTransform)
    raw.viewportToGlMatrix = prevM

    if antialiasing:
      raw.pop prevFbo
      raw.draw(cache.aafb, translate((pos + cache.offset).round.vec3(0)))



proc newRiceDrawContext*(): RiceDrawContext =
  result = RiceDrawContext(raw: riceContexts.newDrawContext())

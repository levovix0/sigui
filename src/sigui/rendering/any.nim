## A backend-agnostic interface of drawing primitives onto a "window"
##
## It is recomended to import this module for creating custom components instead of importing whole graphics stack.
## Because then the compilation will be faster, and also a drawing backend can be switched.
##
## But if you need to draw something non-generic, import the sigui/drawing/current_backend backend instead

import std/[unicode]
import pkg/[vmath, bumpy, chroma]
import pkg/pixie/[paths, fonts]
export paths, fonts


type
  DrawContext* = ref object of RootObj

  DrawContextImage* = ref object of RootObj
    ## (Texture from rice). An image, uploaded onto DrawContext (on GPU)

  TextDrawContext* = ref object of RootObj

  PathKind* = enum
    StrokePath
    FillPath

  PathCache* = ref object of RootObj
    ## (Mesh + AntialiasedFramebuffer from rice).
    ## A path, triangulated into a mesh, ready to be drawn quickly.
    ## update() it when the path (or its stroke parameters) changes, draw() it on every frame


method loadImage*(ctx: DrawContext, filepath: string): DrawContextImage {.base.} = discard
method newImage*(ctx: DrawContext, size: IVec2): DrawContextImage {.base.} = discard
method imageFromBuffer*(ctx: DrawContext, size: IVec2, data: pointer): DrawContextImage {.base.} = discard
  ## data is pointer to uint8 rgba pixels
method parseSvg*(ctx: DrawContext, size: IVec2, data: string): DrawContextImage {.base.} = discard

method size*(image: DrawContextImage): IVec2 {.base.} = discard


method resize*(ctx: DrawContext, size: IVec2) {.base.} = discard

method finishRendering*(ctx: DrawContext) {.base.} = discard


#* ------------- text ------------- *#

proc readTypeface*(filepath: string): Typeface {.importc: "sigui_pixie_readTypeface".}
proc parseTtf*(data: string): Typeface {.importc: "sigui_pixie_parseTtf".}

proc computeBounds*(arrangement: Arrangement): Rect {.importc: "sigui_pixie_arrangement_computeBounds".}


proc withSize*(family: Typeface, size: float32): Font =
  let res = newFont(family)
  res.size = size
  res


method startRasterTextDrawing*(
  ctx: DrawContext,
  font: Font,
  origin: Vec2,
): TextDrawContext {.base.} = discard

method endRasterTextDrawing*(ctx: DrawContext) {.base.} = discard

method fastRasterDrawRune*(
  ctx: DrawContext,
  rune: Rune,
  rect: Rect,
  context: TextDrawContext,
) {.base.} = discard

method `color=`*(context: TextDrawContext, v: Color) {.base.} = discard

method drawRasterText*(
  ctx: DrawContext,
  pos: Vec2,
  arrangement: Arrangement,
  color: Color,
  origin: Vec2 = vec2(0, 0),
  exactBoundaries = false,
  transform = mat4(),
) {.base.} = discard


#* ------------- drawing ------------- *#

method clear*(
  ctx: DrawContext,
  color: Color,
) {.base.} = discard


method fillRect*(
  ctx: DrawContext,
  rect: Rect,
  color: Color,
  radius: float32 = 0,
  blend: bool = true,
) {.base.} = discard


method drawRect*(
  ctx: DrawContext,
  rect: Rect,
  color: Color,
  thickness: float32 = 0,
  radius: float32 = 0,
  blend: bool = true,
  dashingPattern: array[2, float32] = [1, 0],
) {.base.} = discard


method drawImage*(
  ctx: DrawContext,
  rect: Rect,
  image: DrawContextImage,
  color: Color,
  radius: float32 = 0,
  blend: bool = true,
  flipY = false,
  imagePos = vec2(),
  imageSize = vec2(),
) {.base.} = discard

method drawIcon*(
  ctx: DrawContext,
  rect: Rect,
  mask: DrawContextImage,
  color: Color,
  radius: float32 = 0,
  flipY = false,
) {.base.} = discard


method drawShadowRect*(
  ctx: DrawContext,
  rect: Rect,
  color: Color,
  blurRadius: float32,
  radius: float32 = 0,
) {.base.} = discard


method pushClipRect*(
  ctx: DrawContext,
  rect: Rect,
  radius: float32 = 0,
) {.base.} = discard

method popClipRect*(ctx: DrawContext) {.base.} = discard


#* ------------- paths ------------- *#

proc computeBounds*(path: Path): Rect {.importc: "sigui_pixie_path_computeBounds".}

method newPathCache*(ctx: DrawContext): PathCache {.base.} = discard

method update*(
  cache: PathCache,
  ctx: DrawContext,
  path: Path,
  transform: Mat3,
  kind: PathKind,
  strokeWidth: float32,
  lineCap: LineCap,
  lineJoin: LineJoin,
) {.base.} = discard
  ## (Re)triangulates the path into the cache.
  ## Expensive, so call it only when the path or its parameters change

method draw*(
  cache: PathCache,
  ctx: DrawContext,
  pos: Vec2,
  transform: Mat3,
  color: Color,
  antialiasing = true,
) {.base.} = discard


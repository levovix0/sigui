## A backend-agnostic interface of drawing primitives onto a "window"
##
## It is recomended to import this module for creating custom components instead of importing whole graphics stack.
## Because then the compilation will be faster, and also a drawing backend can be switched.
##
## But if you need to draw something non-generic, import the sigui/drawing/current_backend backend instead
##
## todo: working with fonts and paths through methods may be slow, should be benchmarked to see if it is crutial

import std/[unicode]
import pkg/[vmath, bumpy, chroma]


type
  DrawContext* = ref object of RootObj

  DrawContextImage* = ref object of RootObj
    ## (Texture from rice). An image, uploaded onto DrawContext (on GPU)

  FontFamily* = ref object of RootObj
    ## (Typeface from pixie)

  FontFace* = ref object of RootObj
    ## (Font from pixie)
  
  HorizontalAlignment* = enum
    LeftAlign
    CenterAlign
    RightAlign

  VerticalAlignment* = enum
    TopAlign
    MiddleAlign
    BottomAlign

  TextArrangement* = ref object
    lines*: seq[(int, int)]    ## The (start, stop) of the lines of text.
    spans*: seq[(int, int)]    ## The (start, stop) of the spans in the text.
    fonts*: seq[FontFace]      ## The font for each span.
    runes*: seq[Rune]          ## The runes of the text.
    positions*: seq[Vec2]      ## The positions of the glyphs for each rune.
    selectionRects*: seq[Rect] ## The selection rects for each glyph.


  LineCap* = enum
    ButtCap, RoundCap, SquareCap

  LineJoin* = enum
    MiterJoin, RoundJoin, BevelJoin

  Path* = ref object of RootObj
    ## (Path from pixie)

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


method loadFont*(ctx: DrawContext, filepath: string): FontFamily {.base.} = discard
method parseTtf*(ctx: DrawContext, data: string): FontFamily {.base.} = discard

method family*(a: FontFace): FontFamily {.base.} = discard
method size*(a: FontFace): float32 {.base.} = discard
method lineHeight*(a: FontFace): float32 {.base.} = discard
method underline*(a: FontFace): bool {.base.} = discard
method strikethrough*(a: FontFace): bool {.base.} = discard
method noKerningAdjustments*(a: FontFace): bool {.base.} = discard

method `family=`*(a: FontFace, v: FontFamily) {.base.} = discard
method `size=`*(a: FontFace, v: float32) {.base.} = discard
method `lineHeight=`*(a: FontFace, v: float32) {.base.} = discard
method `underline=`*(a: FontFace, v: bool) {.base.} = discard
method `strikethrough=`*(a: FontFace, v: bool) {.base.} = discard
method `noKerningAdjustments=`*(a: FontFace, v: bool) {.base.} = discard

method withSize*(family: FontFamily, size: float32): FontFace {.base.} = discard


method textArrangement*(
  ctx: DrawContext,
  font: FontFace,
  text: sink string,
  bounds = vec2(0, 0),
  hAlign = LeftAlign,
  vAlign = TopAlign,
  wrap = true,
): TextArrangement {.base.} = discard

proc size*(arrangement: TextArrangement): Vec2 =
  if arrangement.runes.len > 0:
    for i in 0 ..< arrangement.runes.len:
      if arrangement.runes[i] != Rune(10):
        let rect = arrangement.selectionRects[i]
        result.x = max(result.x, rect.x + rect.w)
    let finalRect = arrangement.selectionRects[^1]
    result.y = finalRect.y + finalRect.h
    if arrangement.runes[^1] == Rune(10):
      result.y += finalRect.h


#* ------------- paths ------------- *#


method newPath*(ctx: DrawContext): Path {.base.} = discard
method parsePath*(ctx: DrawContext, s: string): Path {.base.} = discard

method newPathCache*(ctx: DrawContext): PathCache {.base.} = discard


method moveTo*(path: Path, v: Vec2) {.base.} = discard
method lineTo*(path: Path, v: Vec2) {.base.} = discard
method bezierCurveTo*(path: Path, ctrl1, ctrl2, to: Vec2) {.base.} = discard
method quadraticCurveTo*(path: Path, ctrl, to: Vec2) {.base.} = discard
method ellipticalArcTo*(
  path: Path,
  rx, ry: float32,
  xAxisRotation: float32,
  largeArcFlag, sweepFlag: bool,
  to: Vec2,
) {.base.} = discard
method arc*(
  path: Path, pos: Vec2, r: float32, a: Vec2, ccw = false
) {.base.} = discard
method arcTo*(path: Path, a, b: Vec2, r: float32) {.base.} = discard
method closePath*(path: Path) {.base.} = discard

method rect*(path: Path, rect: Rect, clockwise = true) {.base.} = discard
method roundedRect*(
  path: Path, rect: Rect, nw, ne, se, sw: float32, clockwise = true
) {.base.} = discard
method ellipse*(path: Path, center: Vec2, rx, ry: float32) {.base.} = discard
method circle*(path: Path, center: Vec2, r: float32) {.base.} = discard
method polygon*(path: Path, pos: Vec2, r: float32, n: int) {.base.} = discard

method addPath*(path: Path, other: Path) {.base.} = discard
method transform*(path: Path, mat: Mat3) {.base.} = discard
method copy*(path: Path): Path {.base.} = discard

method computeBounds*(path: Path, transform = mat3()): Rect {.base.} = discard


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


method clear*(
  ctx: DrawContext,
  color: Color,
) {.base.} = discard


method fillRect*(
  ctx: DrawContext,
  pos: Vec2,
  size: Vec2,
  color: Color,
  radius: float32 = 0,
  blend: bool = true,
) {.base.} = discard


method drawRect*(
  ctx: DrawContext,
  pos: Vec2,
  size: Vec2,
  color: Color,
  thickness: float32 = 0,
  radius: float32 = 0,
  blend: bool = true,
  dashingPattern: array[2, float32] = [1, 0],
) {.base.} = discard


method drawImage*(
  ctx: DrawContext,
  pos: Vec2,
  size: Vec2,
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
  pos: Vec2,
  size: Vec2,
  mask: DrawContextImage,
  color: Color,
  radius: float32 = 0,
  flipY = false,
) {.base.} = discard


method drawRasterText*(
  ctx: DrawContext,
  pos: Vec2,
  arrangement: TextArrangement,
  color: Color,
  origin: Vec2 = vec2(0, 0),
  exactBoundaries = false,
  transform = mat4(),
) {.base.} = discard


method drawShadowRect*(
  ctx: DrawContext,
  pos: Vec2,
  size: Vec2,
  color: Color,
  blurRadius: float32,
  radius: float32 = 0,
) {.base.} = discard


method pushClipRect*(
  ctx: DrawContext,
  pos: Vec2,
  size: Vec2,
  radius: float32 = 0,
) {.base.} = discard

method popClipRect*(ctx: DrawContext) {.base.} = discard


method resize*(ctx: DrawContext, size: IVec2) {.base.} = discard

method finishRendering*(ctx: DrawContext) {.base.} = discard


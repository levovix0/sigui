import std/[tables, macros, sequtils, sets]
import pkg/[shady, pixie]
import pkg/fusion/[matching, astdsl]
import ./[gl, text as renderText]

when hasImageman:
  import pkg/imageman


type
  Texture* = ref TextureObj
  TextureObj = object
    glid: GlUint


  DrawContext* = ref object
    rect*: Shape

    shaders*: Table[int, RootRef]
    
    px*: Vec2  ## size of a pixel
    wh*: Vec2  ## size of the drawing area in pixels

    frameBufferHierarchy*: seq[tuple[fbo: GlUint, size: IVec2]]
    offset*: Vec2

    glyphBuffer*: GlyphBuffer


var freeTextures*: HashSet[GlUint]


#* ------------- textures ------------- *#

const sigui_render_texturesToAllocateIfNoFree {.intdefine.} = 8

proc `=destroy`(texture: TextureObj) =
  freeTextures.incl texture.glid
  try:
    texture.glid.loadTexture(pixie.newImage(1, 1))  # load empty image to force opengl use less memory
  except GlError, PixieError:
    discard


proc raw*(texture: Texture): GlUint =
  texture.glid


proc newTexture*(): Texture =
  if freeTextures.len == 0:
    var newTextureGlUids: array[sigui_render_texturesToAllocateIfNoFree, GlUint]
    glGenTextures(sigui_render_texturesToAllocateIfNoFree, newTextureGlUids[0].addr)
    for i in 0..<sigui_render_texturesToAllocateIfNoFree:
      freeTextures.incl newTextureGlUids[i]
  
  new result
  result.glid = freeTextures.pop


proc load*(texture: Texture, image: pixie.Image) =
  texture.raw.loadTexture(image)

proc newTexture*(image: pixie.Image): Texture =
  result = newTexture()
  result.load(image)


when hasImageman:
  proc load*(texture: Texture, image: imageman.Image[imageman.ColorRgbau]) =
    texture.raw.loadTexture(image)

  proc newTexture*(image: imageman.Image[imageman.ColorRgbau]): Texture =
    result = newTexture()
    result.load(image)



#* ------------- makeShader macros ------------- *#

var newShaderId {.compileTime.}: int = 1


macro makeShader*(ctx: DrawContext, body: untyped): auto =
  ##
  ## .. code-block:: nim
  ##   let solid = ctx.makeShader:
  ##     {.version: "330 core".}
  ##     proc vert(
  ##       gl_Position: var Vec4,
  ##       pos: var Vec2,
  ##       ipos: Vec2,
  ##       transform: Uniform[Mat4],
  ##       size: Uniform[Vec2],
  ##       px: Uniform[Vec2],
  ##     ) =
  ##       transformation(gl_Position, pos, size, px, ipos, transform)
  ##
  ##     proc frag(
  ##       glCol: var Vec4,
  ##       pos: Vec2,
  ##       radius: Uniform[float],
  ##       size: Uniform[Vec2],
  ##       color: Uniform[Vec4],
  ##     ) =
  ##       glCol = vec4(color.rgb * color.a, color.a) * roundRect(pos, size, radius)
  ##
  ## convers to (roughly):
  ##
  ## .. code-block:: nim
  ##   proc vert(
  ##     gl_Position: var Vec4,
  ##     pos: var Vec2,
  ##     ipos: Vec2,
  ##     transform: Uniform[Mat4],
  ##     size: Uniform[Vec2],
  ##     px: Uniform[Vec2],
  ##   ) =
  ##     transformation(gl_Position, pos, size, px, ipos, transform)
  ##
  ##   proc frag(
  ##     glCol: var Vec4,
  ##     pos: Vec2,
  ##     radius: Uniform[float],
  ##     size: Uniform[Vec2],
  ##     color: Uniform[Vec4],
  ##   ) =
  ##     glCol = vec4(color.rgb * color.a, color.a) * roundRect(pos, size, radius)
  ##
  ##   type MyShader = ref object of RootObj
  ##     shader: Shader
  ##     transform: OpenglUniform[Mat4]
  ##     size: OpenglUniform[Vec2]
  ##     px: OpenglUniform[Vec2]
  ##     radius: OpenglUniform[float]
  ##     color: OpenglUniform[Vec4]
  ##
  ##   if not ctx.shaders.hasKey(1):
  ##     let x = MyShader()
  ##     x.shader = newShader {GlVertexShader: vert.toGLSL("330 core"), GlFragmentShader: frag.toGLSL("330 core")}
  ##     x.transform =  OpenglUniform[Mat4](result.solid.shader["transform"])
  ##     x.size = OpenglUniform[Vec2](result.solid.shader["size"])
  ##     x.px = OpenglUniform[Vec2](result.solid.shader["px"])
  ##     x.radius = OpenglUniform[float](result.solid.shader["radius"])
  ##     x.color = OpenglUniform[Vec4](result.solid.shader["color"])
  ##     ctx.shaders[1] = RootRef(x)
  ##
  ##   MyShader(ctx.shaders[1])
  let id = newShaderId
  inc newShaderId
  var
    vert: NimNode
    frag: NimNode
    uniforms: Table[string, NimNode]
  
  var version: NimNode = newLit "300 es"
  var origBody = body
  var body = body
  if body.kind != nnkStmtList:
    body = newStmtList(body)

  proc findUniforms(uniforms: var Table[string, NimNode], params: seq[NimNode]) =
    for x in params:
      x.expectKind nnkIdentDefs
      var names = x[0..^3].mapIt($it)
      case x[^2]
      of BracketExpr[Ident(strVal: "Uniform"), @t]:
        for name in names:
          uniforms[name] = t

  result = buildAst(stmtList):
    for x in body:
      case x
      of Pragma[ExprColonExpr[Ident(strVal: "version"), @ver]]:
        version = ver
      of ProcDef[@name is Ident(strVal: "vert"), _, _, FormalParams[Empty(), all @params], .._]:
        x
        vert = name
        (uniforms.findUniforms(params))
      of ProcDef[@name is Ident(strVal: "frag"), _, _, FormalParams[Empty(), all @params], .._]:
        x
        frag = name
        (uniforms.findUniforms(params))
      else: x

    if vert == nil:
      (error("vert shader proc not defined", origBody))
    if frag == nil:
      (error("frag shader proc not defined", origBody))
    
    let shaderT = genSym(nskType)

    typeSection:
      typeDef:
        shaderT
        empty()
        refTy:
          objectTy:
            empty()
            ofInherit:
              bindSym"RootObj"
            recList:
              identDefs(ident "shader"):
                bindSym"Shader"
                empty()

              for n, t in uniforms:
                identDefs(ident n):
                  bracketExpr bindSym"OpenglUniform": t
                  empty()
    
    ifExpr:
      elifBranch:
        call bindSym"not":
          call bindSym"hasKey":
            dotExpr(ctx, ident "shaders")
            newLit id
        stmtList:
          let shaderX = genSym(nskLet)
          letSection:
            identDefs(shaderX, empty(), call(bindSym"new", shaderT))
          
          asgn dotExpr(shaderX, ident"shader"):
            call bindSym"newShader":
              tableConstr:
                exprColonExpr:
                  ident "GlVertexShader"
                  call bindSym"toGLSL":
                    vert
                    version
                exprColonExpr:
                  ident "GlFragmentShader"
                  call bindSym"toGLSL":
                    frag
                    version
          
          for n, t in uniforms:
            asgn dotExpr(shaderX, ident n):
              call bracketExpr(bindSym"OpenglUniform", t):
                bracketExpr:
                  dotExpr(shaderX, ident "shader")
                  newLit n
          
          call bindSym"[]=":
            dotExpr(ctx, ident "shaders")
            newLit id
            call bindSym"RootRef": shaderX
    
    call shaderT: call(bindSym"[]", dotExpr(ctx, ident "shaders"), newLit id)
  
  result = nnkBlockStmt.newTree(newEmptyNode(), result)


#* ------------- utils ------------- *#

proc mat4*(x: Mat2): Mat4 =
  ## note: this function exists in Glsl, but do not in vmath
  mat4(
    x[0, 0], x[0, 1], 0, 0,
    x[1, 0], x[1, 1], 0, 0,
    0,       0,       1, 0,
    0,       0,       0, 1,
  )


proc passTransform*(ctx: DrawContext, shader: tuple|object|ref object, pos = vec2(), size = vec2(10, 10), angle: float32 = 0, flipY = false) =
  shader.transform.uniform =
    translate(vec3(ctx.px*(vec2(pos.x, -pos.y) - ctx.wh - (if flipY: vec2(0, size.y) else: vec2())), 0)) *
    scale(if flipY: vec3(1, -1, 1) else: vec3(1, 1, 1)) *
    rotate(angle, vec3(0, 0, 1))
  shader.size.uniform = size
  shader.px.uniform = ctx.px


var gltex*: Uniform[Sampler2d]  # workaround shady#9

proc transformation*(glpos: var Vec4, pos: var Vec2, size, px, ipos: Vec2, transform: Mat4) =
  let scale = vec2(px.x * size.x, px.y * -size.y)
  glpos = transform * mat2(scale.x, 0, 0, scale.y).mat4 * vec4(ipos, vec2(0, 1))
  pos = vec2(ipos.x * size.x, ipos.y * size.y)


proc newDrawContext*: DrawContext =
  new result

  result.rect = newShape(
    [
      vec2(0, 1),   # top left
      vec2(0, 0),   # bottom left
      vec2(1, 0),   # bottom right
      vec2(1, 1),   # top right
    ], [
      0'u32, 1, 2,
      2, 3, 0,
    ]
  )


proc updateDrawingAreaSize*(ctx: DrawContext, size: IVec2) =
  # update size
  ctx.px = vec2(2'f32 / size.x.float32, 2'f32 / size.y.float32)
  ctx.wh = ivec2(size.x, -size.y).vec2 / 2


proc drawText*(ctx: DrawContext, pos: Vec2, arrangement: Arrangement, color: Vec4) =
  if arrangement == nil or arrangement.fonts.len == 0:
    return

  let shader = ctx.makeShader:
    proc vert(
      gl_Position: var Vec4,
      pos: var Vec2,
      uv: var Vec2,
      ipos: Vec2,
      transform: Uniform[Mat4],
      size: Uniform[Vec2],
      px: Uniform[Vec2],
      placement: Uniform[Vec2],
      placementWh: Uniform[Vec2],
    ) =
      transformation(gl_Position, pos, size, px, ipos, transform)
      uv = placement + ipos * placementWh

    proc frag(
      glCol: var Vec4,
      pos: Vec2,
      uv: Vec2,
      size: Uniform[Vec2],
      color: Uniform[Vec4],
    ) =
      let col = gltex.texture(uv)
      glCol = vec4(color.rgb * color.a, color.a) * col.r

  use shader.shader
  glEnable(GlBlend)
  glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

  let family = ctx.glyphBuffer.families.mgetOrPut(arrangement.fonts[0].glyphFamily, GlyphFamilyBuffer()).addr

  for i, rune in arrangement.runes:
    var rect = arrangement.selectionRects[i]
    # todo: force pixie to adjust text to pixel grid while generating arrangement, for better alligning
    ctx.passTransform(shader, pos = pos + rect.xy, size = rect.wh, angle=0)

    let placement = family[].renderIfNeeded(rune, arrangement.fonts[0], rect.wh)
    shader.placement.uniform =
      vec2(placement.x.float, placement.y.float) /
      vec2(sigui_glyphBuffer_textureSize, sigui_glyphBuffer_textureSize)
    
    shader.placementWh.uniform =
      rect.wh /
      vec2(sigui_glyphBuffer_textureSize, sigui_glyphBuffer_textureSize)

    shader.color.uniform = color
    
    glBindTexture(GlTexture2d, placement.texture)

    draw ctx.rect
  
  glBindTexture(GlTexture2d, 0)
  glDisable(GlBlend)

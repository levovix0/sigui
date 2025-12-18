import std/[tables, macros, sequtils, sets]
import pkg/[shady, pixie]
import pkg/fusion/[astdsl]
import ./[gl, text as renderText]

when hasImageman:
  import pkg/imageman/[images as imagemanImages, colors as imagemanColors]


type
  Texture* = ref TextureObj
  TextureObj = object
    glid: GlUint

  
  EffectBuffer* = ref object
    fbo*: FrameBuffers
    tex*: Texture
    size*: IVec2
    # todo: split free area of EffectBuffer like an atlas, so many small ClipArea widgets can be draw onto same EffectBuffer without clearing it


  DrawContextRef* = ref DrawContextObj
  DrawContext* = ptr DrawContextObj
  DrawContextObj* = object
    rect*: Shape

    shaders*: Table[int, RootRef]
    
    px*: Vec2  ## size of a pixel
    wh*: Vec2  ## size of the drawing area in pixels
    windowWh*: IVec2

    frameBufferHierarchy*: seq[tuple[fbo: GlUint, size: IVec2]]
    offset*: Vec2

    glyphBuffer*: GlyphBuffer

    freeEffectBuffers: seq[EffectBuffer]
    unusedEffectBuffers: HashSet[GlUint]


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
  proc load*(texture: Texture, image: imagemanImages.Image[imagemanColors.ColorRgbau]) =
    texture.raw.loadTexture(image)

  proc newTexture*(image: imagemanImages.Image[imagemanColors.ColorRgbau]): Texture =
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
      
      # Uniform[t]
      if x[^2].kind == nnkBracketExpr and x[^2][0] == ident("Uniform"):
        for name in names:
          uniforms[name] = x[^2][1]

  result = buildAst(stmtList):
    for x in body:
      # {.version: ver.}
      if x.kind == nnkPragma and x.len == 1 and x[0].kind == nnkExprColonExpr and x[0][0] == ident("version"):
        version = x[0][1]
      
      # proc vert(params...) = body
      elif x.kind == nnkProcDef and x[0] == ident("vert"):
        x
        vert = x[0]
        (uniforms.findUniforms(x.params[1..^1]))

      # proc frag(params...) = body
      elif x.kind == nnkProcDef and x[0] == ident("frag"):
        x
        frag = x[0]
        (uniforms.findUniforms(x.params[1..^1]))

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


proc newDrawContext*: DrawContextRef =
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




#* ------------- EffectBuffer ------------- *#

proc requireEffectBuffer*(ctx: DrawContext, minSize: IVec2): EffectBuffer =
  let minSize = ivec2(max(minSize.x, 1), max(minSize.y, 1))
  
  var i = 0
  while i < ctx.freeEffectBuffers.len:
    template ef: untyped = ctx.freeEffectBuffers[i]

    if ef.size.x >= minSize.x and ef.size.y >= minSize.y:
      ctx.unusedEffectBuffers.excl ef.fbo[0]
      result = ef
      ctx.freeEffectBuffers.del i
      return
    
    inc i
  
  # no available free buffer with size that is at least `minSize`

  if ctx.freeEffectBuffers.len != 0:
    # resize existing framebuffer
    template ef: untyped = ctx.freeEffectBuffers[0]
    result = ef

    ef.size = ivec2(max(minSize.x, ef.size.x), max(minSize.y, ef.size.y))

    let prevFbo =
      if ctx.frameBufferHierarchy.len != 0: ctx.frameBufferHierarchy[^1].fbo
      else: 0
    
    glBindFramebuffer(GlFramebuffer, ef.fbo[0])
    glBindTexture(GlTexture2d, ef.tex.raw)
    glTexImage2D(GlTexture2d, 0, GlRgba.Glint, ef.size.x, ef.size.y, 0, GlRgba, GlUnsignedByte, nil)
    glTexParameteri(GlTexture2d, GlTextureMinFilter, GlNearest)
    glTexParameteri(GlTexture2d, GlTextureMagFilter, GlNearest)
    glFramebufferTexture2D(GlFramebuffer, GlColorAttachment0, GlTexture2d, ef.tex.raw, 0)
        
    glBindFramebuffer(GlFramebuffer, prevFbo)
    
    ctx.freeEffectBuffers.del 0
  
  else:
    # create new framebuffer
    new result

    template ef: untyped = result
    ef.size = minSize

    ef.fbo = newFrameBuffers(1)
    ef.tex = newTexture()

    let prevFbo =
      if ctx.frameBufferHierarchy.len != 0: ctx.frameBufferHierarchy[^1].fbo
      else: 0
    
    glBindFramebuffer(GlFramebuffer, ef.fbo[0])
    glBindTexture(GlTexture2d, ef.tex.raw)
    glTexImage2D(GlTexture2d, 0, GlRgba.Glint, ef.size.x, ef.size.y, 0, GlRgba, GlUnsignedByte, nil)
    glTexParameteri(GlTexture2d, GlTextureMinFilter, GlNearest)
    glTexParameteri(GlTexture2d, GlTextureMagFilter, GlNearest)
    glFramebufferTexture2D(GlFramebuffer, GlColorAttachment0, GlTexture2d, ef.tex.raw, 0)
        
    glBindFramebuffer(GlFramebuffer, prevFbo)


proc free*(ctx: DrawContext, ef: EffectBuffer) =
  assert ctx.freeEffectBuffers.allIt(it.fbo[0] != ef.fbo[0])
  ctx.freeEffectBuffers.add ef


proc deleteUnusedEffectBuffers*(ctx: DrawContext) =
  var c = 0
  for efFbo in ctx.unusedEffectBuffers:
    var i = 0
    while i < ctx.freeEffectBuffers.len:
      template ef: untyped = ctx.freeEffectBuffers[i]
      if ef.fbo[0] == efFbo:
        ctx.freeEffectBuffers.del i
        inc c
      else:
        inc i


proc markAllFreeEffectBuffersAsUnused*(ctx: DrawContext) =
  for ef in ctx.freeEffectBuffers:
    ctx.unusedEffectBuffers.incl ef.fbo[0]


proc push*(ctx: DrawContext, ef: EffectBuffer, clear = true) =
  ctx.frameBufferHierarchy.add (ef.fbo[0], ef.size)
  glBindFramebuffer(GlFramebuffer, ef.fbo[0])

  glViewport 0, 0, ef.size.x.GLsizei, ef.size.y.GLsizei
  ctx.updateDrawingAreaSize(ef.size)
  
  if clear:
    glClearColor(0, 0, 0, 0)
    glClear(GlColorBufferBit)


proc pop*(ctx: DrawContext, ef: EffectBuffer) =
  assert ctx.frameBufferHierarchy.len != 0 and ctx.frameBufferHierarchy[^1].fbo == ef.fbo[0]
  ctx.frameBufferHierarchy.del ctx.frameBufferHierarchy.high
  
  let prevFbo =
    if ctx.frameBufferHierarchy.len != 0: ctx.frameBufferHierarchy[^1].fbo
    else: 0
  glBindFramebuffer(GlFramebuffer, prevFbo)

  let size =
    if ctx.frameBufferHierarchy.len != 0: ctx.frameBufferHierarchy[^1].size
    else: ctx.windowWh
  glViewport 0, 0, size.x.GLsizei, size.y.GLsizei
  ctx.updateDrawingAreaSize(size)




#* ------------- drawing ------------- *#

proc drawText*(ctx: DrawContext, pos: Vec2, arrangement: Arrangement, color: Vec4) =
  if arrangement == nil or arrangement.fonts.len == 0:
    return

  let shader = ctx.makeShader:
    proc vert(
      gl_Position: var Vec4,
      uv: var Vec2,
      ipos: Vec2,
      transform: Uniform[Vec4],
      placement: Uniform[Vec4],
    ) =
      gl_Position = vec4(transform.Vec4.xy + ipos * transform.Vec4.zw, vec2(0, 1))
      uv = placement.Vec4.xy + ipos * placement.Vec4.zw

    proc frag(
      glCol: var Vec4,
      uv: Vec2,
      color: Uniform[Vec4],
    ) =
      let col = gltex.texture(uv)
      glCol = vec4(color.Vec4.rgb * color.Vec4.a, color.Vec4.a) * col.r

  use shader.shader
  glEnable(GlBlend)
  glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

  let family = ctx.glyphBuffer.families.mgetOrPut(arrangement.fonts[0].glyphFamily, GlyphFamilyBuffer()).addr

  var prevTexture = -1.Gluint

  for i, rune in arrangement.runes:
    var rect = arrangement.selectionRects[i]
    rect.wh = rect.wh + vec2(2, 2)
    
    # todo: force pixie to adjust text to pixel grid while generating arrangement, for better alligning
    
    shader.transform.uniform = vec4(vec2(-1, 1) + vec2(pos.x + rect.x, -(pos.y + rect.y)) * ctx.px, vec2(rect.w, -rect.h) * ctx.px)

    let placement = family[].renderIfNeeded(rune, arrangement.fonts[0], rect.wh)
    shader.placement.uniform =
      vec4(
        vec2(placement.x.float, placement.y.float) /
        vec2(sigui_glyphBuffer_textureSize, sigui_glyphBuffer_textureSize),

        rect.wh /
        vec2(sigui_glyphBuffer_textureSize, sigui_glyphBuffer_textureSize)
      )

    shader.color.uniform = color
    
    if prevTexture != placement.texture:
      glBindTexture(GlTexture2d, placement.texture)
      glTexParameteri(GlTexture2d, GlTextureMinFilter, GlNearest)
      prevTexture = placement.texture

    draw ctx.rect
  
  glBindTexture(GlTexture2d, 0)
  glDisable(GlBlend)

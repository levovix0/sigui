import tables
import pkg/[vmath, bumpy, siwin, shady, chroma]
import pkg/pixie/fileformats/[svg], pkg/pixie/[fonts, images]
import ./[events, properties, cvmath, uiobj]
import ./render/[gl, contexts]

when hasImageman:
  import imageman except Rect, color, Color

export vmath, cvmath, bumpy, gl, chroma, fonts, images, events, properties, tables, contexts, uiobj

when defined(sigui_debug_useLogging):
  import logging


type
  UiRect* = ref object of Uiobj
    color*: Property[Col] = color(0, 0, 0).property
    radius*: Property[float32]
    angle*: Property[float32]
  

  UiImage* = ref object of Uiobj
    radius*: Property[float32]
    blend*: Property[bool] = true.property
    tex: Texture
    imageWh*: Property[IVec2]
    angle*: Property[float32]
    color*: Property[Col] = color(1, 1, 1).property
    colorOverlay*: Property[bool]
      ## if true, image will have flat color, with image alpha working like a mask (useful for icons)

  UiSvgImage* = ref object of Uiobj
    ## pixel-perfect svg image
    ## expensive resize
    radius*: Property[float32]
    blend*: Property[bool] = true.property
    image*: Property[string]
    imageWh*: Property[IVec2]
    angle*: Property[float32]
    color*: Property[Col] = color(0, 0, 0).property
    tex: Texture

  UiRectBorder* = ref object of UiRect
    borderWidth*: Property[float32] = 1'f32.property
    tiled*: Property[bool]
    tileSize*: Property[Vec2] = vec2(4, 4).property
    tileSecondSize*: Property[Vec2] = vec2(2, 2).property
    secondColor*: Property[Col]

  UiRectStroke* {.deprecated: "renamed to UiRectBorder".} = UiRectBorder

  RectShadow* = ref object of UiRect
    blurRadius*: Property[float32]
  

  ClipRect* = ref object of Uiobj
    radius*: Property[float32]
    angle*: Property[float32]
    color*: Property[Col] = color(1, 1, 1).property
    fbo: FrameBuffers
    tex: Texture
    prevSize: IVec2
  

  UiText* = ref object of Uiobj
    text*: Property[string]
    font*: Property[Font]
    bounds*: Property[Vec2]
    hAlign*: Property[HorizontalAlignment]
    vAlign*: Property[VerticalAlignment]
    wrap*: Property[bool] = true.property
    color*: Property[Col] = color(0, 0, 0).property

    arrangement*: Property[Arrangement]
    roundPositionOnDraw*: Property[bool] = true.property


#----- DrawContext -----


proc roundRect(pos, size: Vec2, radius: float32): float32 =
  if radius == 0: return 1
  
  if pos.x < radius and pos.y < radius:
    let d = length(pos - vec2(radius, radius))
    return (radius - d + 0.5).max(0).min(1)
  
  elif pos.x > size.x - radius and pos.y < radius:
    let d = length(pos - vec2(size.x - radius, radius))
    return (radius - d + 0.5).max(0).min(1)
  
  elif pos.x < radius and pos.y > size.y - radius:
    let d = length(pos - vec2(radius, size.y - radius))
    return (radius - d + 0.5).max(0).min(1)
  
  elif pos.x > size.x - radius and pos.y > size.y - radius:
    let d = length(pos - vec2(size.x - radius, size.y - radius))
    return (radius - d + 0.5).max(0).min(1)

  return 1


proc drawRect*(ctx: DrawContext, pos: Vec2, size: Vec2, col: Vec4, radius: float32, blend: bool, angle: float32) =
  let shader = ctx.makeShader:
    proc vert(
      gl_Position: var Vec4,
      pos: var Vec2,
      ipos: Vec2,
      transform: Uniform[Mat4],
      size: Uniform[Vec2],
      px: Uniform[Vec2],
    ) =
      transformation(gl_Position, pos, size.Vec2, px.Vec2, ipos, transform.Mat4)

    proc frag(
      glCol: var Vec4,
      pos: Vec2,
      radius: Uniform[float],
      size: Uniform[Vec2],
      color: Uniform[Vec4],
    ) =
      glCol = vec4(color.Vec4.rgb * color.Vec4.a, color.Vec4.a) * roundRect(pos, size.Vec2, radius.float)
  
  if blend:
    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

  use shader.shader
  ctx.passTransform(shader, pos=pos, size=size, angle=angle)
  shader.radius.uniform = radius
  shader.color.uniform = col
  draw ctx.rect
  if blend: glDisable(GlBlend)


proc drawRectStroke*(ctx: DrawContext, pos: Vec2, size: Vec2, col: Vec4, radius: float32, blend: bool, angle: float32, borderWidth: float32, tiled: bool, tileSize: Vec2, tileSecondSize: Vec2, secondColor: Vec4) =
  let shader = ctx.makeShader:
    proc roundRectStroke(pos, size: Vec2, radius: float32, borderWidth: float32): float32 =
      if pos.x < radius + borderWidth and pos.y < radius + borderWidth:
        let d = length(pos - vec2(radius, radius) - vec2(borderWidth, borderWidth))
        return (radius + borderWidth - d + 0.5).max(0).min(1) * (1 - (radius - d + 0.5).max(0).min(1))
      
      elif pos.x > size.x - radius - borderWidth and pos.y < radius + borderWidth:
        let d = length(pos - vec2(size.x - radius, radius) - vec2(-borderWidth, borderWidth))
        return (radius + borderWidth - d + 0.5).max(0).min(1) * (1 - (radius - d + 0.5).max(0).min(1))
      
      elif pos.x < radius + borderWidth and pos.y > size.y - radius - borderWidth:
        let d = length(pos - vec2(radius, size.y - radius) - vec2(borderWidth, -borderWidth))
        return (radius + borderWidth - d + 0.5).max(0).min(1) * (1 - (radius - d + 0.5).max(0).min(1))
      
      elif pos.x > size.x - radius - borderWidth and pos.y > size.y - radius - borderWidth:
        let d = length(pos - vec2(size.x - radius, size.y - radius) - vec2(-borderWidth, -borderWidth))
        return (radius + borderWidth - d + 0.5).max(0).min(1) * (1 - (radius - d + 0.5).max(0).min(1))

      elif pos.x < borderWidth: return 1
      elif pos.y < borderWidth: return 1
      elif pos.x > size.x - borderWidth: return 1
      elif pos.y > size.y - borderWidth: return 1
      return 0

    proc strokeTiling(pos, size, tileSize, tileSecondSize: Vec2, radius, borderWidth: float32): float32 =
      if tileSize == size: return 0

      if (
        (pos.x < radius + borderWidth and pos.y < radius + borderWidth) or
        (pos.x > size.x - radius - borderWidth and pos.y < radius + borderWidth) or
        (pos.x < radius + borderWidth and pos.y > size.y - radius - borderWidth) or
        (pos.x > size.x - radius - borderWidth and pos.y > size.y - radius - borderWidth)
      ):
        return 0
      else:
        if pos.x <= borderWidth or pos.x >= size.x - borderWidth:
          var y = pos.y
          while y > 0:
            if y < tileSize.y: return 0
            y -= tileSize.y
            if y < tileSecondSize.y: return 1
            y -= tileSecondSize.y
        else:
          var x = pos.x
          while x > 0:
            if x < tileSize.x: return 0
            x -= tileSize.x
            if x < tileSecondSize.x: return 1
            x -= tileSecondSize.x
        return 1


    proc vert(
      gl_Position: var Vec4,
      pos: var Vec2,
      ipos: Vec2,
      transform: Uniform[Mat4],
      size: Uniform[Vec2],
      px: Uniform[Vec2],
    ) =
      transformation(gl_Position, pos, size.Vec2, px.Vec2, ipos, transform.Mat4)

    proc frag(
      glCol: var Vec4,
      pos: Vec2,
      radius: Uniform[float],
      size: Uniform[Vec2],
      color: Uniform[Vec4],
      borderWidth: Uniform[float],
      tileSize: Uniform[Vec2],
      tileSecondSize: Uniform[Vec2],
      secondColor: Uniform[Vec4],
    ) =
      if strokeTiling(pos, size.Vec2, tileSize.Vec2, tileSecondSize.Vec2, radius, borderWidth) > 0:
        glCol =
          vec4(secondColor.Vec4.rgb * secondColor.Vec4.a, secondColor.Vec4.a) *
          roundRectStroke(pos, size.Vec2, radius.float, borderWidth.float)
      else:
        glCol =
          vec4(color.Vec4.rgb * color.Vec4.a, color.Vec4.a) *
          roundRectStroke(pos, size.Vec2, radius.float, borderWidth.float)
  
  if blend:
    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

  use shader.shader
  ctx.passTransform(shader, pos=pos, size=size, angle=angle)
  shader.radius.uniform = radius
  shader.color.uniform = col
  shader.borderWidth.uniform = borderWidth
  if tiled:
    shader.tileSize.uniform = tileSize
    shader.tileSecondSize.uniform = tileSecondSize
  else:
    shader.tileSize.uniform = size
    shader.tileSecondSize.uniform = vec2(0, 0)
  shader.secondColor.uniform = secondColor
  draw ctx.rect
  if blend: glDisable(GlBlend)


proc drawImage*(ctx: DrawContext, pos: Vec2, size: Vec2, tex: GlUint, color: Vec4, radius: float32, blend: bool, angle: float32, flipY = false) =
  let shader = ctx.makeShader:
    proc vert(
      gl_Position: var Vec4,
      pos: var Vec2,
      uv: var Vec2,
      ipos: Vec2,
      transform: Uniform[Mat4],
      size: Uniform[Vec2],
      px: Uniform[Vec2],
    ) =
      transformation(gl_Position, pos, size.Vec2, px.Vec2, ipos, transform.Mat4)
      uv = ipos

    proc frag(
      glCol: var Vec4,
      pos: Vec2,
      uv: Vec2,
      radius: Uniform[float],
      size: Uniform[Vec2],
      color: Uniform[Vec4],
    ) =
      let c = gltex.texture(uv)
      glCol = vec4(c.rgb, c.a) * roundRect(pos, size.Vec2, radius.float) * vec4(color.Vec4.rgb * color.Vec4.a, color.Vec4.a)

  if blend:
    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)
  
  use shader.shader
  ctx.passTransform(shader, pos=pos, size=size, angle=angle, flipY=flipY)
  shader.radius.uniform = radius
  shader.color.uniform = color
  glBindTexture(GlTexture2d, tex)
  draw ctx.rect
  glBindTexture(GlTexture2d, 0)
  if blend: glDisable(GlBlend)


proc drawIcon*(ctx: DrawContext, pos: Vec2, size: Vec2, tex: GlUint, col: Vec4, radius: float32, blend: bool, angle: float32) =
  # draw image (with solid color)
  let shader = ctx.makeShader:
    proc vert(
      gl_Position: var Vec4,
      pos: var Vec2,
      uv: var Vec2,
      ipos: Vec2,
      transform: Uniform[Mat4],
      size: Uniform[Vec2],
      px: Uniform[Vec2],
    ) =
      transformation(gl_Position, pos, size.Vec2, px.Vec2, ipos, transform.Mat4)
      uv = ipos

    proc frag(
      glCol: var Vec4,
      pos: Vec2,
      uv: Vec2,
      radius: Uniform[float],
      size: Uniform[Vec2],
      color: Uniform[Vec4],
    ) =
      let col = gltex.texture(uv)
      glCol = vec4(color.Vec4.rgb * color.Vec4.a, color.Vec4.a) * col.a * roundRect(pos, size.Vec2, radius.float)

  if blend:
    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

  use shader.shader
  ctx.passTransform(shader, pos=pos, size=size, angle=angle)
  shader.radius.uniform = radius
  shader.color.uniform = col
  glBindTexture(GlTexture2d, tex)
  draw ctx.rect
  glBindTexture(GlTexture2d, 0)
  if blend: glDisable(GlBlend)


proc drawShadowRect*(ctx: DrawContext, pos: Vec2, size: Vec2, col: Vec4, radius: float32, blend: bool, blurRadius: float32, angle: float32) =
  let shader = ctx.makeShader:
    proc distanceRoundRect(pos, size: Vec2, radius: float32, blurRadius: float32): float32 =
      if pos.x < radius + blurRadius and pos.y < radius + blurRadius:
        let d = length(pos - vec2(radius + blurRadius, radius + blurRadius))
        result = ((radius + blurRadius - d) / blurRadius).max(0).min(1)
      
      elif pos.x > size.x - radius - blurRadius and pos.y < radius + blurRadius:
        let d = length(pos - vec2(size.x - radius - blurRadius, radius + blurRadius))
        result = ((radius + blurRadius - d) / blurRadius).max(0).min(1)
      
      elif pos.x < radius + blurRadius and pos.y > size.y - radius - blurRadius:
        let d = length(pos - vec2(radius + blurRadius, size.y - radius - blurRadius))
        result = ((radius + blurRadius - d) / blurRadius).max(0).min(1)
      
      elif pos.x > size.x - radius - blurRadius and pos.y > size.y - radius - blurRadius:
        let d = length(pos - vec2(size.x - radius - blurRadius, size.y - radius - blurRadius))
        result = ((radius + blurRadius - d) / blurRadius).max(0).min(1)
      
      elif pos.x < blurRadius:
        result = (pos.x / blurRadius).max(0).min(1)

      elif pos.y < blurRadius:
        result = (pos.y / blurRadius).max(0).min(1)
      
      elif pos.x > size.x - blurRadius:
        result = ((size.x - pos.x) / blurRadius).max(0).min(1)

      elif pos.y > size.y - blurRadius:
        result = ((size.y - pos.y) / blurRadius).max(0).min(1)
      
      else:
        result = 1
      
      result *= result

    proc vert(
      gl_Position: var Vec4,
      pos: var Vec2,
      ipos: Vec2,
      transform: Uniform[Mat4],
      size: Uniform[Vec2],
      px: Uniform[Vec2],
    ) =
      transformation(gl_Position, pos, size.Vec2, px.Vec2, ipos, transform.Mat4)

    proc frag(
      glCol: var Vec4,
      pos: Vec2,
      radius: Uniform[float],
      blurRadius: Uniform[float],
      size: Uniform[Vec2],
      color: Uniform[Vec4],
    ) =
      glCol = vec4(color.Vec4.rgb * color.Vec4.a, color.Vec4.a) * distanceRoundRect(pos, size.Vec2, radius.float, blurRadius.float)

  if blend:
    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)
  
  use shader.shader
  ctx.passTransform(shader, pos=pos, size=size, angle=angle)
  shader.radius.uniform = radius
  shader.color.uniform = col
  shader.blurRadius.uniform = blurRadius
  draw ctx.rect
  if blend: glDisable(GlBlend)



#----- Basic Components -----


proc `image=`*(obj: UiImage, img: images.Image) =
  if img != nil:
    if obj.tex == nil: obj.tex = newTexture()
    obj.tex.load(img)
    if obj.wh == vec2():
      obj.wh = vec2(img.width.float32, img.height.float32)
    obj.imageWh[] = ivec2(img.width.int32, img.height.int32)

when hasImageman:
  proc `image=`*(obj: UiImage, img: imageman.Image[ColorRGBAU]) =
    if obj.tex == nil: obj.tex = newTexture()
    obj.tex.load(img)
    if obj.wh == vec2():
      obj.wh = vec2(img.width.float32, img.height.float32)
    obj.imageWh[] = ivec2(img.width.int32, img.height.int32)


method draw*(rect: UiRect, ctx: DrawContext) =
  rect.drawBefore(ctx)
  if rect.visibility[] == visible:
    ctx.drawRect(
      (rect.xy.posToGlobal(rect.parent) + ctx.offset).round, rect.wh,
      rect.color.vec4, rect.radius, rect.color[].a != 1 or rect.radius != 0, rect.angle
    )
  rect.drawAfter(ctx)


method draw*(this: UiImage, ctx: DrawContext) =
  this.drawBefore(ctx)
  if this.visibility[] == visible and this.tex != nil:
    if this.colorOverlay[]:
      ctx.drawIcon(
        (this.xy.posToGlobal(this.parent) + ctx.offset).round, this.wh, this.tex.raw,
        this.color.vec4, this.radius, this.blend or this.radius != 0, this.angle
      )
    else:
      ctx.drawImage(
        (this.xy.posToGlobal(this.parent) + ctx.offset).round, this.wh, this.tex.raw,
        this.color.vec4, this.radius, this.blend or this.radius != 0, this.angle
      )
  this.drawAfter(ctx)


method init*(this: UiSvgImage) =
  procCall this.super.init

  var prevSize = ivec2(0, 0)
  proc updateTexture(size = ivec2()) =
    let sz =
      if size.x > 0 and size.y > 0: size
      elif this.w[].int32 > 0 and this.h[].int32 > 0: this.wh.ivec2
      else: ivec2(0, 0)
    
    prevSize = size
    
    if this.image[] != "":
      
      var img = this.image[].parseSvg(sz.x, sz.y).newImage
      
      if this.tex == nil: this.tex = newTexture()
      this.tex.load(img)
      if this.wh == vec2():
        this.wh = vec2(img.width.float32, img.height.float32)
      if size == ivec2():
        this.imageWh[] = ivec2(img.width.int32, img.height.int32)
    else:
      this.imageWh[] = ivec2()

  this.image.changed.connectTo this: updateTexture()
  this.w.changed.connectTo this: updateTexture(this.wh.ceil.ivec2)
  this.h.changed.connectTo this: updateTexture(this.wh.ceil.ivec2)


method draw*(ico: UiSvgImage, ctx: DrawContext) =
  ico.drawBefore(ctx)
  if ico.visibility[] == visible and ico.tex != nil:
    ctx.drawIcon((ico.xy.posToGlobal(ico.parent) + ctx.offset).round, ico.wh.ceil, ico.tex.raw, ico.color.vec4, ico.radius, ico.blend or ico.radius != 0, ico.angle)
  ico.drawAfter(ctx)


proc `fontSize=`*(this: UiText, size: float32) =
  this.font[].size = size
  this.font.changed.emit()

method init*(this: UiText) =
  procCall this.super.init

  this.arrangement.changed.connectTo this:
    if this.arrangement[] != nil:
      let bounds = this.arrangement[].layoutBounds
      this.wh = bounds
    else:
      this.wh = vec2()

  proc newArrangement(this: UiText): Arrangement =
    if this.text[] != "" and this.font != nil:
      typeset(this.font[], this.text[], this.bounds[], this.hAlign[], this.vAlign[], this.wrap[])
    else: nil

  this.text.changed.connectTo this: this.arrangement[] = newArrangement(this)
  this.font.changed.connectTo this: this.arrangement[] = newArrangement(this)
  this.bounds.changed.connectTo this: this.arrangement[] = newArrangement(this)
  this.hAlign.changed.connectTo this: this.arrangement[] = newArrangement(this)
  this.vAlign.changed.connectTo this: this.arrangement[] = newArrangement(this)
  this.wrap.changed.connectTo this: this.arrangement[] = newArrangement(this)


method draw*(text: UiText, ctx: DrawContext) =
  text.drawBefore(ctx)
  let pos =
    if text.roundPositionOnDraw[]:
      (text.xy.posToGlobal(text.parent) + ctx.offset).round
    else:
      text.xy.posToGlobal(text.parent) + ctx.offset

  if text.visibility[] == visible:
    ctx.drawText(pos, text.arrangement[], text.color.vec4)
  text.drawAfter(ctx)


method draw*(rect: UiRectBorder, ctx: DrawContext) =
  rect.drawBefore(ctx)
  if rect.visibility[] == visible:
    ctx.drawRectStroke((rect.xy.posToGlobal(rect.parent) + ctx.offset).round, rect.wh, rect.color.vec4, rect.radius, true, rect.angle, rect.borderWidth[], rect.tiled[], rect.tileSize[], rect.tileSecondSize[], rect.secondColor[].vec4)
  rect.drawAfter(ctx)


method draw*(rect: RectShadow, ctx: DrawContext) =
  rect.drawBefore(ctx)
  if rect.visibility[] == visible:
    ctx.drawShadowRect((rect.xy.posToGlobal(rect.parent) + ctx.offset).round, rect.wh, rect.color.vec4, rect.radius, true, rect.blurRadius, rect.angle)
  rect.drawAfter(ctx)


method draw*(this: ClipRect, ctx: DrawContext) =
  this.drawBefore(ctx)
  if this.visibility == visible:
    if this.w[] <= 0 or this.h[] <= 0: return
    if this.fbo == nil: this.fbo = newFrameBuffers(1)

    let size = ivec2(this.w[].round.int32, this.h[].round.int32)

    ctx.frameBufferHierarchy.add (this.fbo[0], size)
    glBindFramebuffer(GlFramebuffer, this.fbo[0])
    
    if this.prevSize != size or this.tex == nil:
      this.prevSize = size
      this.tex = newTexture()
      glBindTexture(GlTexture2d, this.tex.raw)
      glTexImage2D(GlTexture2d, 0, GlRgba.Glint, size.x, size.y, 0, GlRgba, GlUnsignedByte, nil)
      glTexParameteri(GlTexture2d, GlTextureMinFilter, GlNearest)
      glTexParameteri(GlTexture2d, GlTextureMagFilter, GlNearest)
      glFramebufferTexture2D(GlFramebuffer, GlColorAttachment0, GlTexture2d, this.tex.raw, 0)
    else:
      glBindTexture(GlTexture2d, this.tex.raw)
    
    glClearColor(0, 0, 0, 0)
    glClear(GlColorBufferBit)
    
    glViewport 0, 0, size.x.GLsizei, size.y.GLsizei
    ctx.updateDrawingAreaSize(size)

    let offset = block:
      var xy = this.xy
      var obj = this.parent
      while obj != nil and not(obj of ClipRect):
        xy.x += obj.x[]
        xy.y += obj.y[]
        obj = obj.parent
      xy
    ctx.offset -= offset
    try:
      this.drawBeforeChilds(ctx)
      this.drawChilds(ctx)
    
    finally:
      ctx.frameBufferHierarchy.del ctx.frameBufferHierarchy.high
      ctx.offset += offset

      glBindFramebuffer(GlFramebuffer, if ctx.frameBufferHierarchy.len == 0: 0.GlUint else: ctx.frameBufferHierarchy[^1].fbo)

      let size =
        if ctx.frameBufferHierarchy.len == 0:
          let win = this.parentWindow
          if win == nil: this.lastParent.wh.ivec2 else: win.size
        else: ctx.frameBufferHierarchy[^1].size
      glViewport 0, 0, size.x.GLsizei, size.y.GLsizei
      ctx.updateDrawingAreaSize(size)
      
      ctx.drawImage(
        (this.xy.posToGlobal(this.parent) + ctx.offset).round, this.wh,
        this.tex.raw, this.color.vec4, this.radius, true, this.angle, flipY=true
      )
  else:
    this.drawBeforeChilds(ctx)
    this.drawChilds(ctx)
  this.drawAfterLayer(ctx)


proc newUiImage*(): UiImage = new result
proc newUiSvgImage*(): UiSvgImage = new result
proc newUiText*(): UiText = new result
proc newUiRect*(): UiRect = new result
proc newUiRectBorder*(): UiRectBorder = new result
proc newClipRect*(): ClipRect = new result
proc newRectShadow*(): RectShadow = new result


proc withSize*(typeface: Typeface, size: float): Font =
  result = newFont(typeface)
  result.size = size


registerComponent UiRect
registerComponent UiImage
registerComponent UiSvgImage
registerComponent UiRectBorder
registerComponent RectShadow
registerComponent ClipRect
registerComponent UiText

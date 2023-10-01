import unittest
import sigui, shady

type ChessTiles = ref object of Uiobj
  tileSize: float


method draw*(this: ChessTiles, ctx: DrawContext) =
  this.drawBefore(ctx)
  if this.visibility == visible:
    let shader = ctx.makeShader:
      {.version: "330 core".}
      
      proc vert(
        gl_Position: var Vec4,
        pos: var Vec2,
        ipos: Vec2,
        transform: Uniform[Mat4],
        size: Uniform[Vec2],
        px: Uniform[Vec2],
      ) =
        # default sigui specific transformation to correct locate component on screen
        # and convert opengl's coordinate system (-1..1) to sigui's coordinate system (0..windowSize_inPixels)
        # out `pos` is component-local (0..componentSize_inPixels)
        transformation(gl_Position, pos, size, px, ipos, transform)
        # don't use it if you don't need it (and don't call `ctx.passTransform` if so)

      proc frag(
        glCol: var Vec4,
        pos: Vec2,
        tileSize: Uniform[float],
      ) =
        if (
          (pos.x - ((pos.x / (tileSize * 2)).floor * (tileSize * 2)) >= tileSize) ==
          (pos.y - ((pos.y / (tileSize * 2)).floor * (tileSize * 2)) >= tileSize)
        ):
          glCol = vec4(1, 1, 1, 1)
        else:
          glCol = vec4(0, 0, 0, 1)
      
    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

    use shader.shader
    ctx.passTransform(shader, pos=(this.xy[].posToGlobal(this.parent) + ctx.offset).round, size=this.wh[].round, angle=0)
    shader.tileSize.uniform = this.tileSize
    
    draw ctx.rect
    
    glDisable(GlBlend)
  this.drawAfter(ctx)


test "Custom shaders":
  preview(clearColor = color(0.5, 0.5, 0.5), margin = 20,
    withWindow = proc: Uiobj =
      let this = ChessTiles()
      init this
      this.bindingValue this.tileSize: min(this.w[] / 10, this.h[] / 10)
      this
  )

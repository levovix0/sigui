import unittest
import sigui, shady

type Cat = ref object of Uiobj

registerComponent Cat


proc overlapsTri*(tri_0, tri_1, tri_2: Vec2, p: Vec2): bool =
  let areaOrig = abs(
    (tri_1.x - tri_0.x) * (tri_2.y - tri_0.y) -
    (tri_2.x - tri_0.x) * (tri_1.y-tri_0.y)
  )

  let area1 = abs((tri_0.x - p.x) * (tri_1.y - p.y) - (tri_1.x - p.x) * (tri_0.y - p.y))
  let area2 = abs((tri_1.x - p.x) * (tri_2.y - p.y) - (tri_2.x - p.x) * (tri_1.y - p.y))
  let area3 = abs((tri_2.x - p.x) * (tri_0.y - p.y) - (tri_0.x - p.x) * (tri_2.y - p.y))

  return (area1 + area2 + area3 - areaOrig).abs < 0.0001


method draw*(this: Cat, ctx: DrawContext) =
  this.drawBefore(ctx)
  if this.visibility == visible:
    let shader = ctx.makeShader:
      {.version: "300 es".}
      
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
        transformation(gl_Position, pos, size.Vec2, px.Vec2, ipos, transform.Mat4)
        # don't use it if you don't need it (and don't call `ctx.passTransform` if so)

      proc frag(
        glCol: var Vec4,
        pos: Vec2,
        size: Uniform[Vec2],
      ) =
        let poz = vec2((pos.x / size.Vec2.x), ((pos.y / size.Vec2.y)))
        let w = sin((poz.x - 0.35) / 0.3 * PI * 2).abs

        if (
          poz.x > 0.35 and poz.x < 0.65 and
          poz.y > 0.55 + w * 0.1 and poz.y < 0.55 + 0.02 + w * 0.1
        ):
          glCol = vec4(0, 0, 0, 1)
        elif (
          (vec2((pos.x / size.Vec2.x - 0.42) * 3, (pos.y / size.Vec2.y - 0.4))).length < 0.05 or
          (vec2((pos.x / size.Vec2.x - 0.58) * 3, (pos.y / size.Vec2.y - 0.4))).length < 0.05
        ):
          glCol = vec4(0, 0, 0, 1)
        elif overlapsTri(
          vec2(0.150, 0.500),
          vec2(0.2, 0.130),
          vec2(0.402, 0.271),
          vec2(poz),
        ) or overlapsTri(
          vec2(0.598, 0.271),
          vec2(0.8, 0.130),
          vec2(0.850, 0.500),
          vec2(poz),
        ):
          glCol = vec4(1, 1, 1, 1)
        elif (vec2((pos.x / size.Vec2.x - 0.5), ((pos.y / size.Vec2.y - 0.5) * 1.25))).length < 0.35:
          glCol = vec4(1, 1, 1, 1)
        else:
          glCol = vec4(0, 0, 0, 0)
      
    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

    use shader.shader
    ctx.passTransform(shader, pos=(this.xy.posToGlobal(this.parent) + ctx.offset).round, size=this.wh.round, angle=0)
    
    draw ctx.rect
    
    glDisable(GlBlend)
  this.drawAfter(ctx)


test "Cat shader":
  preview(transparent = true, title = "The Cat", size = ivec2(600, 600)):
    - Cat.new:
      this.margin = 20

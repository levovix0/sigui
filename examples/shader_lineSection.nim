import unittest
import sigui/[uibase, mouseArea], shady
import ./commonGeometry

type Sandbox = ref object of Uiobj
  p1, p2: Property[Vec2]
  r: Property[float32]

registerComponent Sandbox


proc distanceToSection*(pt: Vec2, p1, p2: Vec2): float32 =
  let dp1 = pt - p1
  let dp2 = pt - p2

  let axis = (p2 - p1).normal
  let l = dp1.lenOnAxis(axis)

  if l >= 0 and l <= (p2 - p1).length:
    return length(dp1 - dp1.projectToAxis(axis))
  elif l < 0:
    return length(dp1)
  else:
    return length(dp2)



method init*(this: Sandbox) =
  procCall this.super.init

  this.p1[] = vec2(100, 100)
  this.p2[] = vec2(500, 500)
  this.r[] = 16

  this.makeLayout:
    - MouseArea.new:
      this.fill(parent)
      acceptedButtons = {MouseButton.left, MouseButton.right}

      proc update =
        if this.pressed[]:
          if this.pressedButtons == {MouseButton.left}:
            root.p1[] = vec2(this.mouseX[], this.mouseY[])
          elif this.pressedButtons == {MouseButton.right}:
            root.p2[] = vec2(this.mouseX[], this.mouseY[])
      
      on this.mouseX.changed: update()
      on this.mouseY.changed: update()
      on this.pressed[] == true: update()



method draw*(this: Sandbox, ctx: DrawContext) =
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
        transformation(gl_Position, pos, size.Vec2, px.Vec2, ipos, transform.Mat4)


      proc frag(
        glCol: var Vec4,
        pos: Vec2,
        size: Uniform[Vec2],
        p1: Uniform[Vec2],
        p2: Uniform[Vec2],
        r: Uniform[float32]
      ) =
        glCol = vec4(0, 0, 0, 0)
        
        let c = vec4(1, 1, 1, 1)

        let samples = 16.0
        var v = 0.0

        for y in 0..3:
          for x in 0..3:
            if (pos + vec2(x.float32 / 3.0 - 0.5, y.float32 / 3.0 - 0.5)).distanceToSection(p1, p2) <= r:
              v += 1

        glCol = c * (v / samples)
      

    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

    use shader.shader
    ctx.passTransform(shader, pos=(this.xy.posToGlobal(this.parent) + ctx.offset).round, size=this.wh.round, angle=0)
    shader.p1.uniform = this.p1[]
    shader.p2.uniform = this.p2[]
    shader.r.uniform = this.r[]
    
    draw ctx.rect
    
    glDisable(GlBlend)
  this.drawAfter(ctx)


test "Antialiased line section":
  preview(transparent = true, title = "Antialiased line section", size = ivec2(600, 600)):
    - Sandbox.new:
      this.margin = 20

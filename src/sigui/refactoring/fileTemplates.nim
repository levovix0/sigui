import std/strutils


const minimalMainFileTemplate = """
import sigui/[uibase]

type
  MyComponent* = ref object of Uiobj

registerComponent MyComponent

method init*(this: Switch) =
  procCall this.super.init()
"""


const componentFileTemplate = """
import sigui/[uibase]

type
  <|name|>* = ref object of Uiobj

registerComponent <|name|>


method init*(this: <|name|>) =
  procCall this.super.init()

  this.makeLayout:
    ##


when isMainModule:
  preview:
    this.clearColor = color(1, 1, 1)
    - <|name|>.new:
      this.margin = 20
"""


const shaderComponentFileTemplate = """
import sigui/[uibase], shady

type
  <|name|>* = ref object of Uiobj

registerComponent <|name|>


method init*(this: <|name|>) =
  procCall this.super.init()


method draw*(this: <|name|>, ctx: DrawContext) =
  this.drawBefore(ctx)
  if this.visibility == visible:
    let shader = ctx.makeShader:
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
        size: Uniform[Vec2],
        myColor: Uniform[Vec4],
      ) =
        glCol = myColor * (pos / size).vec4(vec2(1, 1))
      
    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

    use shader.shader
    ctx.passTransform(shader, pos=(this.xy.posToGlobal(this.parent) + ctx.offset).round, size=this.wh.round, angle=0)
    shader.myColor.uniform = color(1, 0.5, 0).vec4
    
    draw ctx.rect
    
    glDisable(GlBlend)
  this.drawAfter(ctx)


when isMainModule:
  preview:
    this.clearColor = color(1, 1, 1)
    - <|name|>.new:
      this.margin = 20
  )
"""


macro doRefactor_siguiMinimalMain*(
  instInfo: static tuple[filename: string, line: int, column: int],
) =
  writeFile instInfo.filename, minimalMainFileTemplate
  quit 0


macro doRefactor_siguiComponentFile*(
  name: untyped,
  instInfo: static tuple[filename: string, line: int, column: int],
) =
  writeFile instInfo.filename, componentFileTemplate.replace("<|name|>", name.repr)
  quit 0


macro doRefactor_siguiShaderComponentFile*(
  name: untyped,
  instInfo: static tuple[filename: string, line: int, column: int],
) =
  writeFile instInfo.filename, shaderComponentFileTemplate.replace("<|name|>", name.repr)
  quit 0


import ./[uiobj, properties, uibase]
import ./render/[gl, contexts]
import pkg/pixie/[images, paths, paints]


type
  UiPathKind* = enum
    StrokePath
    FillPath
  
  UiPath* = ref object of Uiobj
    path*: Property[Path]
    kind*: Property[UiPathKind]
    
    transform*: Property[Mat3] = mat3().property
    color*: Property[Col] = color(0, 0, 0, 1).property
    strokeWidth*: Property[float32] = 1'f32.property
    
    lineCap*: Property[LineCap]
    lineJoin*: Property[LineJoin]
    
    changed: bool
    tex: Texture
    offset: Vec2
    texWh: IVec2

proc firstHandHandler_hook(obj: UiPath, name: static string, origType: typedesc)

registerComponent UiPath



proc updateTexture(this: UiPath) =
  this.tex = nil

  if this.path[] == nil:
    return
  
  let bounds = this.path[].computeBounds(this.transform[])
  var boundsI = (x: bounds.x.floor.int32, y: bounds.y.floor.int32, w: bounds.w.ceil.int32, h: bounds.h.ceil.int32)

  let grow =
    if this.kind[] == FillPath: 0'i32
    else: this.strokeWidth[].ceil.int32
  boundsI.x -= grow
  boundsI.y -= grow
  boundsI.w += grow * 2
  boundsI.h += grow * 2

  this.offset = vec2(boundsI.x.float32, boundsI.y.float32)
  this.texWh = ivec2(boundsI.w, boundsI.h)

  if boundsI.w <= 0 or bounds.h <= 0:
    return
  
  this.tex = newTexture()

  let img = newImage(boundsI.w, boundsI.h)
  let paint = newPaint(SolidPaint)
  paint.color = this.color[]
  
  case this.kind[]
  of StrokePath:
    img.strokePath(
      this.path[],
      paint,
      translate(-this.offset) * this.transform[],
      this.strokeWidth[],
      this.lineCap[],
      this.lineJoin[]
    )

  of FillPath:
    img.fillPath(
      this.path[],
      paint,
      translate(-this.offset) * this.transform[]
    )

  this.tex.load(img)



proc firstHandHandler_hook(obj: UiPath, name: static string, origType: typedesc) =
  obj.super.firstHandHandler_hook(name, origType)

  when name == "path" or name == "transform" or name == "strokeWidth":
    obj.changed = true


method draw*(this: UiPath, ctx: DrawContext) =
  this.drawBefore(ctx)
  
  if this.visibility[] == visible:
    if this.changed:
      this.updateTexture()
      this.changed = false

    if this.tex != nil:
      ctx.drawImage(
        (this.globalXy + ctx.offset + this.offset).round, this.texWh.vec2, this.tex.raw,
        this.color.vec4, 0, true, 0
      )
  
  this.drawAfter(ctx)


when isMainModule:
  import pkg/siwin, ./mouseArea

  let win = newSiwinGlobals().newOpenglWindow(size = ivec2(600, 600)).newUiWindow

  var angle = 0'f32.property
  
  win.makeLayout:
    clearColor = "202020".color

    - UiPath.new as path:
      this.centerIn(parent)

      strokeWidth = 5
      color = "ffffff".color

      lineCap = RoundCap
      lineJoin = RoundJoin

      # kind = FillPath

      transform = binding:
        scale(vec2(1, -1)) * rotate(angle[])

      path = block:
        var p = newPath()

        p.arc(vec2(), 100, vec2(PI/2 - PI/6, PI/2*3 + PI/6), ccw = false)
        p.arc(vec2(100, 0), 50, vec2(PI/2*3 + PI/6, PI/2 - PI/6), ccw = false)
        p.closePath()

        p

    - MouseArea.new:
      this.fill(parent)

      var startAngle: float32

      on this.grabbed[] == true:
        startAngle = angle[]

      proc skew(a, b: Vec2): float32 =
        ## returns pseudo scalar product, equal to a.length * b.length * sin(a.signedAngleTo(b))
        a.x * b.y - a.y * b.x

      proc signedAngleTo(a, b: Vec2): float32 =
        ## returns the signed angle between two vectors in radians
        ## positive if b is counterclockwise from a, negative otherwise
        let cosAngle = a.dot(b) / (a.length * b.length)
        if cosAngle > 1: return 0
        if cosAngle < -1: return PI

        if cosAngle.isNaN:
          return 0

        if a.skew(b) < 0:
          -arccos(cosAngle)
        else:
          arccos(cosAngle)

      proc move =
        if not this.grabbed[]: return
        angle[] = startAngle + (this.pressWindowPos - path.xy).signedAngleTo(this.parentWindow.mouse.pos - path.xy)

      on this.mouseX.changed: move()
      on this.mouseY.changed: move()


  run win.siwinWindow

import ./[uibase]
import rice/[paths, contextutils, antialiasing, transform]
import pkg/pixie/[paths, paints]


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
    antialiasing*: Property[bool] = true.property
    
    changed: bool
    meshes: seq[Mesh]
    offset: Vec2
    aafb: AntialiasedFramebuffer


addFirstHandHandler UiPath, "path": this.changed = true; redraw(this)
addFirstHandHandler UiPath, "transform": this.changed = true; redraw(this)
addFirstHandHandler UiPath, "strokeWidth": this.changed = this.changed or (this.kind[] == StrokePath); redraw(this)


registerComponent UiPath



proc updateMesh(this: UiPath, ctx: DrawContext) =
  this.meshes = @[]
  if this.path[] == nil: return

  let bounds = this.path[].computeBounds(this.transform[])
  var boundsI = (x: bounds.x.floor.int32, y: bounds.y.floor.int32, w: bounds.w.ceil.int32, h: bounds.h.ceil.int32)

  let grow =
    if this.kind[] == FillPath: 0'i32
    else: this.strokeWidth[].ceil.int32
  boundsI.x -= grow
  boundsI.y -= grow
  boundsI.w += grow * 2
  boundsI.h += grow * 2
  # todo: do not draw outside window

  this.offset = vec2(boundsI.x.float32, boundsI.y.float32)
  ctx.resize(this.aafb, ivec2(boundsI.w, boundsI.h))

  if boundsI.w <= 0 or bounds.h <= 0:
    return
  
  case this.kind[]
  of StrokePath:
    this.meshes = this.path[].toStrokeMeshes(this.strokeWidth[], this.lineCap[], this.lineJoin[])
  of FillPath:
    this.meshes = this.path[].toMeshes()


method recieve*(this: UiPath, signal: Signal) =
  procCall this.super.recieve(signal)

  if signal of BeforeDraw:
    if this.changed and this.visibility[] == visible:
      this.updateMesh(signal.BeforeDraw.ctx)
      this.changed = false


method draw*(this: UiPath, ctx: DrawContext) =
  this.drawBefore(ctx)
  
  if this.visibility[] == visible:
    let m = this.transform[]
    let transform = mat4(
      m[0,0], m[0,1], 0, m[0,2],
      m[1,0], m[1,1], 0, m[1,2],
      0,      0,      1, 0,
      m[2,0], m[2,1], 0, 1,
    )
    ctx.withPushPopIf BlendRgbx, this.color[].a != 1 or this.antialiasing[]:
      var prevFbo: PushedAntialiasedFrameBuffer
      if this.antialiasing[]:
        prevFbo = ctx.push this.aafb
        glClearColor(0, 0, 0, 0)
        glClear(GL_COLOR_BUFFER_BIT)
      
      let prevM = ctx.viewportToGlMatrix
      ctx.viewportToGlMatrix =
        translate(-1, -1) *
        scale(2/this.aafb.size.x.float32, 2/this.aafb.size.y.float32) *
        translate(vec3((if this.antialiasing[]: -this.offset else: vec2()), 0))
      ctx.drawWithSolidColor(this.meshes, this.color, transform)
      ctx.viewportToGlMatrix = prevM
      
      if this.antialiasing[]:
        ctx.pop prevFbo
        ctx.draw(this.aafb, translate((this.xy + this.offset).round.vec3(0)))
  
  this.drawAfter(ctx)


when isMainModule:
  import ./mouseArea

  let win = newUiWindow(size = ivec2(600, 600))

  var angle = 0'f32.property
  
  win.makeLayout:
    this.clearColor = "202020".color

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


  run win

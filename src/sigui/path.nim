import ./[uibase]


type
  UiPathKind* = PathKind

  UiPath* = ref object of Uiobj
    path*: Property[Path]
    kind*: Property[PathKind]

    transform*: Property[Mat3] = mat3().property
    color*: Property[Col] = color(0, 0, 0, 1).property
    strokeWidth*: Property[float32] = 1'f32.property

    lineCap*: Property[LineCap]
    lineJoin*: Property[LineJoin]
    antialiasing*: Property[bool] = true.property

    changed: bool
    cache: PathCache


addFirstHandHandler UiPath, "path": this.changed = true; redraw(this)
addFirstHandHandler UiPath, "transform": this.changed = true; redraw(this)
addFirstHandHandler UiPath, "strokeWidth": this.changed = this.changed or (this.kind[] == StrokePath); redraw(this)
addFirstHandHandler UiPath, "kind": this.changed = true; redraw(this)
addFirstHandHandler UiPath, "lineCap": this.changed = this.changed or (this.kind[] == StrokePath); redraw(this)
addFirstHandHandler UiPath, "lineJoin": this.changed = this.changed or (this.kind[] == StrokePath); redraw(this)


registerComponent UiPath



method recieve*(this: UiPath, signal: Signal) =
  procCall this.super.recieve(signal)

  if signal of BeforeDraw:
    if this.changed and this.visibility[] == visible:
      if this.cache == nil: this.cache = signal.BeforeDraw.ctx.newPathCache()
      this.cache.update(
        signal.BeforeDraw.ctx, this.path[], this.transform[], this.kind[],
        this.strokeWidth[], this.lineCap[], this.lineJoin[],
      )
      this.changed = false


method drawInner*(this: UiPath, ctx: DrawContext) =
  if this.cache == nil: return
  this.cache.draw(
    ctx, this.xy.posToGlobal(this.parent),
    this.transform[], this.color[], this.antialiasing[],
  )


when isMainModule:
  import ./[mouseArea, windowCreation]

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
        var p = this.root.ctx.newPath()

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
        ## positive if b is counterclockwise from a, negative if clockwise
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

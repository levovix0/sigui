import unittest
import sigui/[uibase, mouseArea], siwin, shady
import ./commonGeometry

type
  Triangle = object
    points: array[3, Vec3]
    color: chroma.Color
  
  Camera = object
    center: Vec3
    direction: Vec3  # axisZ
    axisX: Vec3
    axisY: Vec3
    w: float32  # in 3d units, not in pixels
    h: float32

  Sandbox = ref object of Uiobj
    triangles: Property[seq[Triangle]]
    camera: Property[Camera]

    fbo: FrameBuffers


registerComponent Sandbox



method init*(this: Sandbox) =
  procCall this.super.init

  when false:  # todo: depth buffer becomes black when adding third triangle
    this.triangles{}.add Triangle(
      points: [
        vec3(-1, 1, 0),
        vec3(-1, -1, 0),
        vec3(1, 0, 0),
      ],
      color: "40ff40".color,
    )
  when true:
    this.triangles{}.add Triangle(
      points: [
        vec3(-1.19949, 0.318523, 0.230578 + 1),
        vec3(-0.390119, -1.3346, -0.5518 + 1),
        vec3(0.535828, -0.226397, -1.93546 + 1),
      ],
      color: "ff4040".color,
    )
  when true:
    this.triangles{}.add Triangle(
      points: [
        vec3(-1.0549, -0.802677, -1.34532 + 1),
        vec3(0.906725, -1.06574, -1.05754 + 1),
        vec3(-0.906725, 1.06574, -0.647423 + 1),
      ],
      color: "4040ff".color,
    )
  this.triangles.changed.emit()

  this.camera[] = Camera(
    # center: vec3(0, 0, 3),
    direction: vec3(0, 0, -1),
    axisX: vec3(1, 0, 0),
    axisY: vec3(0, 1, 0),
    w: 4,
    h: 3,
  )

  this.makeLayout:
    - MouseArea.new:
      this.fill(parent)
      acceptedButtons = {MouseButton.left, MouseButton.right, MouseButton.middle}

      var prevPos = vec2(this.mouseX[], this.mouseY[])
      proc update =
        let newPos = vec2(this.mouseX[], this.mouseY[])
        if this.pressed[]:
          let speed = 1 / 80
          let rotSpeed = 1 / 80
          let dx = (newPos.x - prevPos.x)
          let dy = (newPos.y - prevPos.y)
          let cam = root.camera{}.addr

          if this.pressedButtons == {MouseButton.left}:
            cam.center = cam.center + cam.axisX * (-dx * speed) + cam.axisY * (dy * speed)
            root.camera.changed.emit()

          elif this.pressedButtons == {MouseButton.right}:
            cam.center = cam.center + cam.direction * (dx * speed)
            root.camera.changed.emit()
          
          elif this.pressedButtons == {MouseButton.middle}:
            let center_l = cam.center.lenOnAxis3(cam.direction)

            cam.direction = cam.direction.rotate(vec3(0, 1, 0), dx * rotSpeed).normalize
            cam.axisX = cam.axisX.rotate(vec3(0, 1, 0), dx * rotSpeed).normalize
            cam.axisY = cam.axisY.rotate(vec3(0, 1, 0), dx * rotSpeed).normalize

            cam.direction = cam.direction.rotate(cam.axisX, dy * rotSpeed).normalize
            cam.axisX = cam.axisX.rotate(cam.axisX, dy * rotSpeed).normalize
            cam.axisY = cam.axisY.rotate(cam.axisX, dy * rotSpeed).normalize
            
            cam.center = center_l * cam.direction
            
            root.camera.changed.emit()

        prevPos = newPos
      
      on this.mouseX.changed: update()
      on this.mouseY.changed: update()
      on this.pressed[] == true:
        prevPos = vec2(this.mouseX[], this.mouseY[])
        update()



method draw*(this: Sandbox, ctx: DrawContext) =
  this.drawBefore(ctx)
  if this.visibility == visible and this.w[] > 1 and this.h[] > 1:
    let shader = ctx.makeShader:
      {.version: "300 es".}
      
      proc vert(
        gl_Position: var Vec4,
        pos: var Vec2,
        ipos: Vec2,
        uv: var Vec2,
        transform: Uniform[Mat4],
        size: Uniform[Vec2],
        px: Uniform[Vec2],
      ) =
        transformation(gl_Position, pos, size.Vec2, px.Vec2, ipos, transform.Mat4)
        uv = ipos
        uv.y = -uv.y  # for some unknown (yet) to me reason, texture flips when we render to it. workaround


      proc frag(
        glCol: var Vec4,
        pos: Vec2,
        uv: Vec2,
        size: Uniform[Vec2],
        camOrigin: Uniform[Vec3],
        camDir: Uniform[Vec3],
        camW: Uniform[Vec3],
        camH: Uniform[Vec3],
        p1: Uniform[Vec3],
        p2: Uniform[Vec3],
        p3: Uniform[Vec3],
        color: Uniform[Vec4],
        pass: Uniform[float32], # 0 - color buffer, 1 - depth buffer
      ) =
        let texDepth = gltex.texture(uv)

        if pass < 0.5:  # color
          glCol = vec4(0, 0, 0, 0)
        else:  # depth
          glCol = texDepth

        let rayStart = camOrigin + (pos.x / size.x) * camW + (pos.y / size.y) * camH
        
        let hit = raycast_hit(rayStart, camDir, p1, p2, p3)
        if hit:
          let depth = raycast_depth(rayStart, camDir, p1, p2, p3)
          if depth <= texDepth.r:
            if pass < 0.5:  # color
              glCol = color
            else:
              glCol = vec4(depth, color.g, color.b, 1)
        
    
    # must use second buffer because opengl gets a little buggy
    # when rendering to reading from the same texture
    var depthBuffer = newTexture()
    var depthBuffer2 = newTexture()
    
    for _ in 0..1:  # initialize buffers
      glBindTexture(GlTexture2d, depthBuffer.raw)
      glTexImage2D(GlTexture2d, 0, GL_RGBA32F.Glint, this.w[].round.GLSizei, this.h[].round.GLSizei, 0, GlRgba, GlUnsignedByte, nil)
      # must be 32bit float, rgba is used for ablity to embed more information into the buffer and display it
      glTexParameteri(GlTexture2d, GlTextureMinFilter, GlNearest)
      glTexParameteri(GlTexture2d, GlTextureMagFilter, GlNearest)

      if this.fbo == nil: this.fbo = newFrameBuffers(1)
      glBindFramebuffer(GlFramebuffer, this.fbo[0])
      glFramebufferTexture2D(GlFramebuffer, GlColorAttachment0, GlTexture2d, depthBuffer.raw, 0)
      glClearColor(float32.high, 0, 0, 1)
      glClear(GL_COLOR_BUFFER_BIT)
      glBindFramebuffer(GlFramebuffer, if ctx.frameBufferHierarchy.len == 0: 0.GlUint else: ctx.frameBufferHierarchy[^1].fbo)
      swap depthBuffer, depthBuffer2


    glEnable(GlBlend)
    glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

    use shader.shader
    ctx.passTransform(shader, pos=(this.xy.posToGlobal(this.parent) + ctx.offset).round, size=this.wh.round, angle=0)

    let cam = this.camera{}.addr

    shader.camOrigin.uniform = cam.center - (cam.w / 2) * cam.axisX + (cam.h / 2) * cam.axisY
    shader.camDir.uniform = cam.direction
    shader.camW.uniform = cam.axisX * cam.w
    shader.camH.uniform = (-cam.axisY) * cam.h

    for tri in this.triangles{}:
      shader.p1.uniform = tri.points[0]
      shader.p2.uniform = tri.points[1]
      shader.p3.uniform = tri.points[2]
      shader.color.uniform = tri.color.vec4

      glBindTexture(GlTexture2d, depthBuffer.raw)
      swap depthBuffer, depthBuffer2
    
      when true:  # can be set to false to display the depth buffer on the screen
        shader.pass.uniform = 0
      else:
        shader.pass.uniform = 1
      draw ctx.rect

      shader.pass.uniform = 1
      glBindFramebuffer(GlFramebuffer, this.fbo[0])
      glFramebufferTexture2D(GlFramebuffer, GlColorAttachment0, GlTexture2d, depthBuffer.raw, 0)
      draw ctx.rect
      glBindFramebuffer(GlFramebuffer, if ctx.frameBufferHierarchy.len == 0: 0.GlUint else: ctx.frameBufferHierarchy[^1].fbo)
      
    
    glBindTexture(GlTexture2d, 0)
    glDisable(GlBlend)
  this.drawAfter(ctx)


test "\"Fake\" 3D":
  preview(clearColor = color(0, 0, 0, 0), size = ivec2(800, 600), transparent = true, margin = 0,
    withWindow = proc: Uiobj =
      let this = Sandbox()
      init this
      this.withWindow win:
        win.siwinWindow.title = "\"Fake\" 3D"
      this
  )

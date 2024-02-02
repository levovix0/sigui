import sigui/[uibase, mouseArea, animations, dolars]

type
  Switch* = ref object of Uiobj
    enabled*: Property[bool] = true.property
    isOn*: Property[bool]
    color*: Property[Col] = color(0, 0, 0).property

registerComponent Switch


method init*(this: Switch) =
  if this.initialized: return
  procCall this.super.init()
  
  this.isOn.changed.connectTo this, val:
    echo this

  this.makeLayout:
    this.w[] = 40
    this.h[] = 20

    - MouseArea() as mouse:
      this.fill(parent)
      this.mouseDownAndUpInside.connectTo root:
        if root.enabled[]:
          root.isOn[] = not root.isOn[]

      - UiRectBorder():
        this.fill(parent)
        this.binding radius: min(this.w[], this.h[]) / 2 - 2
        this.borderWidth[] = 2
        this.color[] = color(0.7, 0.7, 0.7)

        - UiRect():
          this.centerY = parent.center
          this.binding w: min(parent.w[], parent.h[]) - 8
          this.binding h: this.w[]
          this.binding radius: this.w[] / 2
          this.binding x:
            if root.isOn[]:
              parent.w[] - this.w[] - 4
            else:
              4'f32
          this.binding color: root.color[]

          - this.x.transition(0.4's):
            this.interpolation[] = outCubicInterpolation

    this.newChildsObject = mouse


when isMainModule:
  preview(clearColor = color(1, 1, 1), margin = 20, withWindow = proc: Uiobj =
    var r = Switch()
    init r
    r
  )
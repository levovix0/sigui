import sigui/[uibase, mouseArea, animations, dolars]

type
  Switch* = ref object of Uiobj
    enabled*: Property[bool] = true.property
    isOn*: Property[bool]
    color*: Property[Col] = color(0, 0, 0).property

registerComponent Switch


method init*(this: Switch) =
  procCall this.super.init()
  
  when isMainModule:
    this.isOn.changed.connectTo this, val:
      echo this

  this.makeLayout:
    w = 40
    h = 20

    - MouseArea() as mouse:
      this.fill(parent)
      this.mouseDownAndUpInside.connectTo root:
        if root.enabled[]:
          root.isOn[] = not root.isOn[]

      - UiRectBorder():
        this.fill(parent)
        this.binding radius: min(this.w[], this.h[]) / 2 - 2
        borderWidth = 2
        color = "aaa"

        - UiRect():
          centerY = parent.center
          w := min(parent.w[], parent.h[]) - 8
          h := this.w[]
          radius := this.w[] / 2
          x = binding:
            if root.isOn[]:
              parent.w[] - this.w[] - 4
            else:
              4'f32
          color := root.color[]

          - this.x.transition(0.4's):
            easing = outCubicEasing

    this.newChildsObject = mouse


when isMainModule:
  preview(clearColor = color(1, 1, 1), margin = 20, withWindow = proc: Uiobj =
    var r = Switch()
    init r
    r
  )
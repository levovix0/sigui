import std/[unittest]
import sigui/[uibase, mouseArea]

type MyComponent = ref object of UiRect
  invisibleProp: Property[int]
  visibleProp: Property[int] = 1.property
  field: int

registerComponent MyComponent

test "properties":
  let x = MyComponent.new
  UiRoot.new.makeLayout:
    - x:
      this.color[] = color(1, 0, 0)
      this.w[] = 20
      this.h[] = 30
      this.field = 2

      - RectShadow.new as shadow:
        this.fill(parent, -5)
        this.drawLayer = before parent
        this.radius[] = 5
      
      - MouseArea.new:
        this.mouseDownAndUpInside.connectTo parent:
          discard

  echo x

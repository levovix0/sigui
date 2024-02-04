import sigui, siwin

let win = newOpenglWindow(size=ivec2(1280, 720), title="Hello sigui").newUiWindow

win.makeLayout:
  - UiRect():
    this.centerIn(parent)
    this.w[] = 100
    this.binding h: this.w[]

    var state = 0.property

    this.binding color:
      (
        case state[]
        of 0: color(1, 0, 0)
        of 1: color(0, 1, 0)
        else: color(0, 0, 1)
      ).lighten(if mouse.hovered[]: 0.3 else: 0)

    - this.color.transition(0.4's)

    - MouseArea() as mouse:
      this.fill(parent)
      this.mouseDownAndUpInside.connectTo root:
        state[] = (state[] + 1) mod 3
      this.cursor = (ref Cursor)(kind: builtin, builtin: BuiltinCursor.pointingHand)

run win.siwinWindow

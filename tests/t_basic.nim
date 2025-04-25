import sigui, siwin

let win = newSiwinGlobals().newOpenglWindow(size=ivec2(1280, 720), title="Hello sigui").newUiWindow

win.makeLayout:
  - UiRect.new:
    this.centerIn(parent)
    w = 100
    h := this.w[]  # same as this.bindingValue this.h[]: this.w[]

    var state = 0.property

    color = binding:  # same as this.bindingValue this.color[]:
      (
        case state[]
        of 0: color(1, 0, 0)
        of 1: color(0, 1, 0)
        else: color(0, 0, 1)
      ).lighten(if mouse.hovered[]: 0.3 else: 0)

    - this.color.transition(0.4's)

    - MouseArea.new as mouse:
      this.fill(parent)
      
      on this.mouseDownAndUpInside:
        state[] = (state[] + 1) mod 3
      
      cursor = (ref Cursor)(kind: builtin, builtin: BuiltinCursor.pointingHand)

run win.siwinWindow

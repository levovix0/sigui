import pkg/[siwin]
import ./[uiobj, properties, events]

type
  GlobalKeybinding* = ref object of Uiobj
    sequence*: Property[set[Key]]
    exact*: Property[bool]
    activated*: Event[void]

registerComponent GlobalKeybinding


proc globalKeybinding*(sequence: set[Key], exact: bool = true): GlobalKeybinding =
  result = GlobalKeybinding(sequence: sequence.property, exact: exact.property)


method recieve*(this: GlobalKeybinding, signal: Signal) =
  if signal of WindowEvent and signal.WindowEvent.event of KeyEvent and signal.WindowEvent.handled == false:
    let e = (ref KeyEvent)signal.WindowEvent.event
    
    if this.exact[]:
      if e.pressed and e.window.keyboard.pressed == this.sequence[]:
        this.activated.emit()
    
    else:
      if e.pressed and (this.sequence[] * e.window.keyboard.pressed) == this.sequence[] and e.key in this.sequence[]:
        this.activated.emit()

  procCall this.super.recieve(signal)

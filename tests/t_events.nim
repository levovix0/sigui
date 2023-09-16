import unittest
import sigui

test "events":
  var e: Event[int]
  var eh: EventHandler
  var capture = 0

  e.emit 1
  check capture == 0

  e.connect eh, proc(v: int) =
    capture = v

  e.emit 2
  check capture == 2
  e.emit 3
  check capture == 3

  e.disconnect eh

  e.emit 4
  check capture == 3

  (proc =
    var eh2: EventHandler
    e.connect eh2, proc(v: int) =
      capture = v
    e.emit 5
    check capture == 5
  )()
  
  e.emit 6
  when defined(orc) or defined(arc):
    check capture == 5
  else:
    ## don't check, garbadge collection is unpredictable


test "properties":
  var e = 0.property
  var eh = EventHandler()
  var capture = 0

  check e[] == 0
  e[] = 1
  check e[] == 1
  check capture == 0

  e.changed.connectTo eh:
    capture = e
  
  check capture == 0

  e[] = 2
  check e[] == 2
  check capture == 2

  e{} = 3
  check e[] == 3
  check capture == 2


test "custom properties":
  var capture1 = 0
  var e = CustomProperty[int](
    get: proc(): int = capture1 + 1,
    set: proc(v: int) = capture1 = v - 1
  )
  var eh = EventHandler()
  var capture2 = 0

  e.changed.connectTo eh:
    capture2 = e

  check e[] == 1
  e[] = 2
  check e[] == 2
  check capture1 == 1
  check capture2 == 2

  e{} = 5
  check e[] == 5
  check capture1 == 4
  check capture2 == 2

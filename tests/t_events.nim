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
  var p = 0.property
  var eh = EventHandler()
  var capture = 0

  check p[] == 0
  p[] = 1
  check p[] == 1
  check capture == 0

  p.changed.connectTo eh:
    capture = p[]
  
  check capture == 0

  p[] = 2
  check p[] == 2
  check capture == 2

  p{} = 3
  check p[] == 3
  check capture == 2


test "custom properties":
  var capture1 = 0
  var prop = CustomProperty[int](
    get: proc(): int = capture1 + 1,
    set: proc(v: int) = capture1 = v - 1
  )
  var eh = EventHandler()
  var capture2 = 0

  prop.changed.connectTo eh:
    capture2 = prop[]

  check prop[] == 1
  prop[] = 2
  check prop[] == 2
  check capture1 == 1
  check capture2 == 2

  prop{} = 5
  check prop[] == 5
  check capture1 == 4
  check capture2 == 2

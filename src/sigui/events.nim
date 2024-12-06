
type
  EventHandler* = object  # pointer is wrapped to an object to attach custom destructor
    p: ptr EventHandlerObj
  EventHandlerObj = object
    connected: seq[ptr EventBase]

  EventConnectionFlag = enum
    transition

  EventConnection[T] = tuple
    eh: ptr EventHandlerObj
    f: proc(v: T) {.closure.}
    flags: set[EventConnectionFlag]

  EventBase = object
    connected: seq[EventConnection[int]]  # type of function argument does not matter for this

  FlaggedPointer* = distinct pointer
    ## pointer, but first bit is used for a flag (pointers are aligned anyway)

  Event*[T] = object  # pointer is wrapped to an object to attach custom destructor
    p: ptr EventObj[T]
    uiobj*: FlaggedPointer  # most of events is .changed properties, after most of which redraw should happen. If not nil, emit will call redrawUiobj

  EventObj*[T] = object
    ## only EventHandler can be connected to event
    ## one event can be connected to multiple components
    ## one EventHandler can connect to multiple events
    ## one event can be connected to one EventHandler multiple times
    ## connection can be removed, but if EventHandler connected to event multiple times, they all will be removed
    connected: seq[EventConnection[T]]


var redrawUiobj*: proc(uiobj: FlaggedPointer) {.cdecl.}


proc `==`*(a, b: FlaggedPointer): bool {.borrow.}


#* ------------- Event ------------- *#

proc destroyEvent(s: ptr EventBase) {.raises: [].}
proc destroyEventHandler(handler: ptr EventHandlerObj) {.raises: [].}


proc `=trace`[T](event: var Event[T], env: pointer) =
  if event.p != nil:
    for conn in event.p[].connected.mitems:
      `=trace`(conn, env)

proc `=trace`(eh: var EventHandler, env: pointer) =
  if eh.p != nil:
    for event in eh.p[].connected:
      `=trace`(event[], env)


proc `=destroy`[T](s: Event[T]) =
  if s.p != nil:
    destroyEvent(cast[ptr EventBase](s.p))

proc `=destroy`(s: EventHandler) =
  if s.p != nil:
    destroyEventHandler(s.p)


proc initIfNeeded[T](s: var Event[T]) =
  if s.p == nil:
    s.p = cast[ptr EventObj[T]](alloc0(sizeof(EventObj[T])))

proc initIfNeeded(c: var EventHandler) =
  if c.p == nil:
    c.p = cast[ptr EventHandlerObj](alloc0(sizeof(EventHandlerObj)))


proc destroyEvent(s: ptr EventBase) =
  for (handler, _, _) in s[].connected:
    var i = 0
    while i < handler[].connected.len:
      if handler[].connected[i] == s:
        handler[].connected.delete i
      else:
        inc i
  `=destroy`(s[])
  dealloc s


proc disconnectEventHandler(handler: ptr EventHandlerObj) =
  for s in handler[].connected:
    var i = 0
    while i < s[].connected.len:
      if s[].connected[i][0] == handler:
        s[].connected.delete i
      else:
        inc i
  handler[].connected = @[]


proc destroyEventHandler(handler: ptr EventHandlerObj) =
  for s in handler[].connected:
    var i = 0
    while i < s[].connected.len:
      if s[].connected[i][0] == handler:
        s[].connected.delete i
      else:
        inc i
  `=destroy`(handler[])
  dealloc handler


proc disconnect*[T](x: var Event[T]) =
  if x.p == nil: return
  destroyEvent cast[ptr EventBase](x.p)
  x.p = nil

proc disconnect*(x: var EventHandler) =
  if x.p == nil: return
  destroyEventHandler x.p
  x.p = nil


proc disconnect*[T](s: var Event[T], c: var EventHandler) =
  if s.p == nil or c.p == nil: return
  var i = 0
  while i < c.p[].connected.len:
    if c.p[].connected[i] == cast[ptr EventBase](s.p):
      c.p[].connected.delete i
    else:
      inc i
  
  i = 0
  while i < s.p[].connected.len:
    if s.p[].connected[i].eh == c.p:
      s.p[].connected.delete i
    else:
      inc i


proc disconnect*[T](s: var Event[T], flags: set[EventConnectionFlag], fullDeteach: bool = false) =
  if s.p == nil: return
  var i = 0
  while i < s.p[].connected.len:
    if (flags * s.p[].connected[i].flags).len != 0:
      let eh = s.p[].connected[i].eh

      if fullDeteach:
        disconnectEventHandler eh
      else:
        s.p[].connected.delete i
        
        var hasThisEventHandlerConnectedSomewhere = false
        for c in s.p[].connected:
          if c.eh == eh:
            hasThisEventHandlerConnectedSomewhere = true
            break
        
        if not hasThisEventHandlerConnectedSomewhere:
          var i = 0
          while i < eh[].connected.len:
            if eh[].connected[i] == cast[ptr EventBase](s.p):
              eh[].connected.delete i
            else:
              inc i

    else:
      inc i


proc emit*[T](s: Event[T], v: T, disableFlags: set[EventConnectionFlag] = {}) =
  if s.p != nil:
    var i = 0
    while i < s.p[].connected.len:
      if (disableFlags * s.p[].connected[i].flags).len == 0:
        s.p[].connected[i].f(v)
      inc i
  if s.uiobj.pointer != nil:
    redrawUiobj s.uiobj

proc emit*(s: Event[void], disableFlags: set[EventConnectionFlag] = {}) =
  if s.p != nil:
    var i = 0
    while i < s.p[].connected.len:
      if (disableFlags * s.p[].connected[i].flags).len == 0:
        s.p[].connected[i].f()
      inc i
  if s.uiobj.pointer != nil:
    redrawUiobj s.uiobj


proc connect*[T](s: var Event[T], c: var EventHandler, f: proc(v: T), flags: set[EventConnectionFlag] = {}) =
  initIfNeeded s
  initIfNeeded c
  s.p[].connected.add (c.p, f, flags)
  c.p[].connected.add cast[ptr EventBase](s.p)

proc connect*(s: var Event[void], c: var EventHandler, f: proc(), flags: set[EventConnectionFlag] = {}) =
  initIfNeeded s
  initIfNeeded c
  s.p[].connected.add (c.p, f, flags)
  c.p[].connected.add cast[ptr EventBase](s.p)


template connectTo*[T](s: var Event[T], obj: var EventHandler, body: untyped) =
  connect s, obj, proc(e {.inject.}: T) =
    body

template connectTo*(s: var Event[void], obj: var EventHandler, body: untyped) =
  connect s, obj, proc() =
    body

template connectTo*[T](s: var Event[T], obj: var EventHandler, argname: untyped, body: untyped) =
  connect s, obj, proc(argname {.inject.}: T) =
    body

template connectTo*(s: var Event[void], obj: var EventHandler, argname: untyped, body: untyped) =
  connect s, obj, proc() =
    body


proc hasHandlers*(e: Event): bool =
  if e.p == nil: return false
  e.p.connected.len > 0


template changed*[T](e: Event[T]): Event[T] =
  e

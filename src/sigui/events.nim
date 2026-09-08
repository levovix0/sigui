
type
  EventHandler* = object  # pointer is wrapped to an object to attach custom destructor
    p: ptr EventHandlerObj
  EventHandlerObj = object
    connected: seq[ptr EventBase]

  EventConnection[T] = tuple
    eh: ptr EventHandlerObj
    f: proc(v: T) {.closure.}

  EventBase = object
    connected: seq[EventConnection[int]]  # type of function argument does not matter for this

  Event*[T] = object  # pointer is wrapped to an object to attach custom destructor
    p: ptr EventObj[T]
    firstHandHandler: proc(env: pointer) {.nimcall.}
    firstHandHandlerEnv: pointer

  EventObj[T] = object
    ## only EventHandler can be connected to event
    ## one event can be connected to multiple components
    ## one EventHandler can connect to multiple events
    ## one event can be connected to one EventHandler multiple times
    ## connection can be removed, but if EventHandler connected to event multiple times, they all will be removed
    connected: seq[EventConnection[T]]


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
  for (handler, _) in s[].connected:
    var i = 0
    while i < handler[].connected.len:
      if handler[].connected[i] == s:
        handler[].connected.delete i
      else:
        inc i
  `=destroy`(s[])
  dealloc s


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


proc emit*[T](s: Event[T], v: T) =
  if s.firstHandHandler != nil: s.firstHandHandler(s.firstHandHandlerEnv)
  if s.p != nil:
    var i = 0
    while i < s.p[].connected.len:
      s.p[].connected[i].f(v)
      inc i

proc emit*(s: Event[void]) =
  if s.firstHandHandler != nil: s.firstHandHandler(s.firstHandHandlerEnv)
  if s.p != nil:
    var i = 0
    while i < s.p[].connected.len:
      s.p[].connected[i].f()
      inc i


# todo: -d:sigui_benchmark_event_emits, to see how much and which exactly events are chain-emited


proc connect*[T](s: var Event[T], c: var EventHandler, f: proc(v: T)) =
  initIfNeeded s
  initIfNeeded c
  s.p[].connected.add (c.p, f)
  c.p[].connected.add cast[ptr EventBase](s.p)

proc connect*(s: var Event[void], c: var EventHandler, f: proc()) =
  initIfNeeded s
  initIfNeeded c
  s.p[].connected.add (c.p, f)
  c.p[].connected.add cast[ptr EventBase](s.p)

proc connect*(s: var Event[void], c: var EventHandler, f: proc(env: pointer) {.nimcall.}, env: pointer) =
  initIfNeeded s
  initIfNeeded c
  let fe = (f, env)
  s.p[].connected.add (c.p, cast[ptr proc(v: void) {.closure.}](fe.addr)[])
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


proc hasHandlers*(e: EventHandler): bool =
  if e.p == nil: return false
  e.p.connected.len > 0


template changed*[T](e: Event[T]): Event[T] =
  e

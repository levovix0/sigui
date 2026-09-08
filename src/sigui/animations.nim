import std/[times, math]
import ./[uiobj, properties, events, timeutils]
export times, timeutils


type
  Easing = proc(x: float): float {.nimcall.}

  Animation*[T] = ref object
    eventHandler: EventHandler
    enabled*: Property[bool] = true.property
    running*: Property[bool]
    duration*: Property[Duration]
    action*: proc(x: T)
    easing*: Property[Easing]
    a*, b*: Property[T]
    loop*: Property[bool]
    ended*: Event[void]

    currentTime*: Property[Duration]
    
    firstTick: bool
  
  InsertablePropertyTransition*[T] = object
    transition*: PropertyTransition[T]
    prop*: ptr Property[T]


func interpolate*[T: enum | bool](a, b: T, x: float): T =
  # note: x can be any number, not just 0..1
  if x >= 1: b
  else: a

func interpolate*[T: SomeInteger](a, b: T, x: float): T =
  a + ((b - a).float * x).round.T

func interpolate*[T: SomeFloat](a, b: T, x: float): T =
  a + ((b - a).float * x).T

func interpolate*[T: array](a, b: T, x: float): T =
  for i, v in result.mpairs:
    v = interpolate(a[i], b[i], x)

func interpolate*[T: object | tuple](a, b: T, x: float): T =
  for i, y in result.fieldPairs:
    for j, af, bf in fieldPairs(a, b):
      when i == j:
        y = interpolate(af, bf, x)


proc linearEasing*(x: float): float {.nimcall.} = x

proc inSquareEasing*(x: float): float {.nimcall.} = x * x
proc inCubicEasing*(x: float): float {.nimcall.} = x * x * x

proc outSquareEasing*(x: float): float {.nimcall.} = 1 - (x - 1) * (x - 1)
proc outCubicEasing*(x: float): float {.nimcall.} = 1 + (x - 1) * (x - 1) * (x - 1)

proc inBounceEasing*(x: float): float {.nimcall.} = (-0.25 + (x * 1.45 - 0.45).pow(2) * 1.24).round(4)
proc outBounceEasing*(x: float): float {.nimcall.} = (1.25 - (x * 1.447215 - 1).pow(2) * 1.25).round(4)


proc currentValue*[T](a: Animation[T]): T =
  if a.duration != DurationZero:
    let f =
      if a.easing[] == nil: linearEasing
      else: a.easing[]
    interpolate(a.a[], a.b[], f(a.currentTime[].inMicroseconds.float / a.duration.inMicroseconds.float))
  else:
    a.a[]


# --- be compatible with makeLayout API ---
proc init*(a: Animation) = discard
proc initIfNeeded*(a: Animation) = discard
proc markCompleted*(obj: Animation) = discard


proc addChild*[T](obj: Uiobj, a: Animation[T]) =
  proc act =
    if a.enabled[] and a.action != nil and a.duration != DurationZero:
      a.action(a.currentValue)

  proc tick(deltaTime: Duration) =
    if a.enabled[] and a.running[]:
      if a.firstTick:
        a.firstTick = false
        act()
        return

      let time = a.currentTime[] + deltaTime
      a.currentTime[] =
        if time < DurationZero: DurationZero
        elif time > a.duration[]:
          if not a.loop[]:
            a.running[] = false
            a.duration[]
          else:
            initDuration(
              seconds = if a.duration.inSeconds != 0: time.inSeconds mod a.duration.inSeconds else: 0,
              nanoseconds = if a.duration.inNanoseconds != 0: time.inNanoseconds mod a.duration.inNanoseconds mod 1_000_000_000 else: 0,
            )
        else: time
      if time > a.duration[]:
        a.ended.emit()
  
  a.currentTime.changed.connectTo a: act()
  a.enabled.changed.connectTo a: act()
  a.a.changed.connectTo a: act()
  a.b.changed.connectTo a: act()
  a.easing.changed.connectTo a: act()
  a.duration.changed.connectTo a: act()

  obj.parentUiRoot.onTick.connectTo a, e:
    tick(e.deltaTime)


proc start*(a: Animation) =
  a.currentTime[] = DurationZero
  a.running[] = true
  a.firstTick = true

template animation*[T](val: T): Animation[T] =
  Animation[T](action: proc(x: T) = val = x)


template init*[T](t: InsertablePropertyTransition[T]) = discard
template initIfNeeded*[T](t: InsertablePropertyTransition[T]) = discard
template markCompleted*[T](t: InsertablePropertyTransition[T]) = discard

proc easing*[T](t: InsertablePropertyTransition[T]): var proc(x: float): float {.nimcall.} = t.transition.easing
proc duration*[T](t: InsertablePropertyTransition[T]): var Duration = t.transition.duration

proc `[]=`*(x: var proc(x: float): float {.nimcall.}, v: proc(x: float): float {.nimcall.}) {.inline.} =
  x = v

proc `[]=`*(x: var Duration, v: Duration) {.inline.} =
  x = v


proc addChild*[T](obj: Uiobj, a: InsertablePropertyTransition[T]) =
  a.prop[].clearTransition()
  a.prop[].transition = a.transition
  a.transition.a = a.prop[].unsafeVal
  a.transition.b = a.prop[].unsafeVal
  a.transition.currentTime = a.transition.duration
  
  proc tick(deltaTime: Duration) =
    if a.transition.currentTime >= a.transition.duration: return

    a.transition.currentTime = a.transition.currentTime + deltaTime
    if a.transition.currentTime > a.transition.duration:
      a.transition.currentTime = a.transition.duration
    
    let v = interpolate(
      a.transition.a, a.transition.b,
      a.transition.easing(a.transition.currentTime.inMicroseconds.float / a.transition.duration.inMicroseconds.float)
    )
    if v != a.prop[].unsafeVal:
      a.prop[].unsafeVal = v
      emit(a.prop[].changed)

  obj.parentUiRoot.onTick.connectTo a.transition.eventHandler, e:
    tick(e.deltaTime)


proc transition*[T](prop: var Property[T], dur: Duration, easing = outSquareEasing): InsertablePropertyTransition[T] =
  InsertablePropertyTransition[T](
    transition: PropertyTransition[T](duration: dur, easing: easing),
    prop: prop.addr,
  )


proc deletionAnimation*(this: Uiobj, duration: Duration, easing = outSquareEasing): UiobjDeletionAnimation =
  ## attaches a UiobjDeletionAnimation to `this` and returns it
  ## use in combination with `on (...).tick`
  if this.deletionAnimation != nil:
    result = this.deletionAnimation
  else:
    result = UiobjDeletionAnimation(duration: duration, easing: easing)
    this.deletionAnimation = result

template animateOnDelete*(obj: Uiobj, val: untyped, toVal: untyped, duration: Duration = 0.2's, easing = outSquareEasing) =
  ## attaches (or extends) a UiobjDeletionAnimation to `this` that interpolates val to toVal
  ## val and toVal is queried just before deletion animation starts
  (proc(this: Uiobj) =
    let anim = deletionAnimation(this, duration, easing)
    var a: typeof(val)
    var b: typeof(val)
    this.deleted.connectTo this:
      a = val
      b = toVal
    anim.tick.connect this.eventHandler, proc(t: float) =
      val = interpolate(a, b, t)
  )(obj)


when isMainModule:
  import ./[uibase, globalKeybinding, windowCreation]

  let animator = newUiWindow(size = ivec2(300, 40))
  animator.makeLayout:
    - UiRect.new as rect:
      w = 40
      h = 40
      x = 10
      color = color(1, 1, 1)

      - this.x.transition(0.4's):
        easing = outCubicEasing

      - this.color.transition(0.4's):
        easing = outCubicEasing

      - globalKeybinding({Key.a}, exact=false):
        this.activated.connectTo root:
          rect.x[] = 10
          rect.color[] = color(1, 1, 1)

      - globalKeybinding({Key.d}, exact=false):
        this.activated.connectTo root:
          rect.x[] = root.w[] - 10 - rect.w[]
          rect.color[] = color(1, 0, 0)
    
      # - animation(this.box.x):
      #   this.duration[] = initDuration(seconds = 1)
      #   this.a[] = 100
      #   this.b[] = 1000
      #   this.loop[] = true
      #   this.interpolation[] = outSquareInterpolation
      #   this.ended.connectTo this:
      #     let a = this.a[]
      #     this.a[] = this.b[]
      #     this.b[] = a
      #   start this
  
  run animator

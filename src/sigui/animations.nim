import std/[times, strutils, math]
import ./[uiobjOnly, properties, events {.all.}]
export times


type
  Animation*[T] = ref object
    eventHandler: EventHandler
    enabled*: Property[bool] = true.property
    running*: Property[bool]
    duration*: Property[Duration]
    action*: proc(x: T)
    easing*: Property[proc(x: float): float]
    a*, b*: Property[T]
    loop*: Property[bool]
    ended*: Event[void]

    currentTime*: Property[Duration]
    
    firstTick: bool
  
  UiAnimator* {.deprecated: "use Animator instead".} = Animator
  Animator* = ref object of Uiobj
    onTick*: Event[Duration]

registerComponent Animator


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


proc linearEasing*(x: float): float = x

proc inSquareEasing*(x: float): float = x * x
proc inCubicEasing*(x: float): float = x * x * x

proc outSquareEasing*(x: float): float = 1 - (x - 1) * (x - 1)
proc outCubicEasing*(x: float): float = 1 + (x - 1) * (x - 1) * (x - 1)

proc inBounceEasing*(x: float): float = (-0.25 + (x * 1.45 - 0.45).pow(2) * 1.24).round(4)
proc outBounceEasing*(x: float): float = (1.25 - (x * 1.447215 - 1).pow(2) * 1.25).round(4)


proc parentAnimator*(obj: Uiobj): Animator =
  var obj {.cursor.} = obj
  while true:
    if obj == nil: return nil
    if obj of Animator: return obj.Animator
    obj = obj.parent


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

  let animator = obj.parentAnimator
  if animator != nil:
    animator.onTick.connectTo a, deltaTime: tick(deltaTime)
  else:
    let animator = obj.parentUiRoot
    animator.onTick.connectTo a, e: tick(e.deltaTime)


proc start*(a: Animation) =
  a.currentTime[] = DurationZero
  a.running[] = true
  a.firstTick = true

template animation*[T](val: T): Animation[T] =
  Animation[T](action: proc(x: T) = val = x)


proc `'s`*(lit: cstring): Duration =
  let lit = ($lit).parseFloat
  initDuration(seconds = lit.int64, nanoseconds = ((lit - lit.int64.float) * 1_000_000_000).int64)
proc `'ms`*(lit: cstring): Duration =
  let lit = ($lit).parseFloat
  initDuration(milliseconds = lit.int64, nanoseconds = ((lit - lit.int64.float) * 1_000_000).int64)


proc clearTransition*(prop: var AnyProperty) =
  prop.changed.disconnect({EventConnectionFlag.transition}, fullDeteach = true)


template transition*[T](prop: var AnyProperty[T], dur: Duration): Animation[T] =
  prop.clearTransition()
  let a = Animation[T](
    action: (proc(x: T) =
      prop{} = x
      prop.changed.emit({EventConnectionFlag.transition})
    ),
    duration: dur.property
  )
  a.a{} = prop[]
  a.b{} = prop[]

  var prevPropVal = prop[]

  prop.changed.connect(a.eventHandler, proc() =
    a.a{} = prevPropVal
    a.b{} = prop[]
    start a
  , flags = {EventConnectionFlag.transition})

  prop.changed.connect(a.eventHandler, proc() = prevPropVal = prop[])

  a


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

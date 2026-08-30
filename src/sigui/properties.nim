import std/[times]
import ./[events]

type
  PropertyTransition*[T] = ref object
    easing*: proc(x: float): float {.nimcall.}
    duration*: Duration
    
    a*, b*: T
    currentTime*: Duration
    eh*: EventHandler

  Property*[T] = object
    unsafeVal*: T
    changed*: Event[void]
    transition*: PropertyTransition[T]
    # todo: replacable bindings

  CustomProperty*[T] = object
    get*: proc(): T
    set*: proc(v: T)
    changed*: Event[void]
    # todo: replacable bindings

  AnyProperty*[T] = concept a, var v
    a[] is T
    v[] = T
    a.changed is Event[void]
    a{} is T
    v{} = T


#* ------------- Property ------------- *#

proc property*[T](v: T): Property[T] =
  Property[T](unsafeVal: v)


proc `{}`*[T](p: var Property[T]): var T {.inline.} = p.unsafeVal


proc val*[T](p: Property[T]): T {.inline.} = p.unsafeVal
proc `[]`*[T](p: Property[T]): T {.inline.} = p.unsafeVal


proc `[]=`*[T](p: var Property[T], v: T) =
  ## note: p.changed will not be emitted if new value is same as previous value
  if p.transition != nil:
    if v == p.transition.b: return
    p.transition.a = p.unsafeVal
    p.transition.b = v
    p.transition.currentTime = DurationZero
  else:
    if v == p.unsafeVal: return
    p.unsafeVal = v
    emit(p.changed)

proc `val=`*[T](p: var Property[T], v: T) {.inline.} = p[] = v
  ## same as `[]=`, but does not emit p.changed


proc `{}=`*[T](p: var Property[T], v: T) {.inline.} =
  if p.transition != nil:
    p.transition.a = p.unsafeVal
    p.transition.b = v
    p.transition.currentTime = DurationZero
  else:
    p.unsafeVal = v


converter toValue*[T](p: Property[T]): T = p[]
  ##? should this converter be removed?

proc `=copy`*[T](p: var Property[T], v: Property[T]) {.error.}


proc clearTransition*[T](p: var Property[T]) =
  if p.transition != nil:
    if p.unsafeVal != p.transition.b:
      p.unsafeVal = p.transition.b
      emit(p.changed)
    disconnect p.transition.eh
    p.transition = nil


#* ------------- CustomProperty ------------- *#

proc unsafeVal*[T](p: CustomProperty[T]): T {.inline.} = p.get()
  ## note: can't get var T due to nature of CustomProperty
proc `{}`*[T](p: CustomProperty[T]): T {.inline.} = p.get()


proc val*[T](p: CustomProperty[T]): T {.inline.} = p.get()
proc `[]`*[T](p: CustomProperty[T]): T {.inline.} = p.get()


proc `val=`*[T](p: CustomProperty[T], v: T) =
  ## note: p.changed will not be emitted if new value is same as previous value
  let oldV = p.get()
  p.set(v)
  if oldV == p.get(): return
  emit(p.changed)

proc `[]=`*[T](p: CustomProperty[T], v: T) {.inline.} = p.val = v


proc `unsafeVal=`*[T](p: CustomProperty[T], v: T) {.inline.} =
  ## same as val=, but always call setter and does not emit p.changed
  p.set(v)

proc `{}=`*[T](p: var CustomProperty[T], v: T) {.inline.} = p.unsafeVal = v


converter toValue*[T](p: CustomProperty[T]): T = p[]
  ##? should this converter be removed?

proc `=copy`*[T](p: var CustomProperty[T], v: CustomProperty[T]) {.error.}

import events

type
  Property*[T] = object
    unsafeVal*: T
    changed*: Event[void]
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


proc `val=`*[T](p: var Property[T], v: T) =
  ## note: p.changed will not be emitted if new value is same as previous value
  if v == p.unsafeVal: return
  p.unsafeVal = v
  emit(p.changed)

proc `[]=`*[T](p: var Property[T], v: T) {.inline.} = p.val = v

proc val*[T](p: Property[T]): T {.inline.} = p.unsafeVal
proc `[]`*[T](p: Property[T]): T {.inline.} = p.unsafeVal

proc `{}`*[T](p: var Property[T]): var T {.inline.} = p.unsafeVal
proc `{}=`*[T](p: var Property[T], v: T) {.inline.} = p.unsafeVal = v
  ## same as `[]=`, but does not emit p.changed

converter toValue*[T](p: Property[T]): T = p[]
  ##? should this converter be removed?

proc `=copy`*[T](p: var Property[T], v: Property[T]) {.error.}


#* ------------- CustomProperty ------------- *#

proc `val=`*[T](p: CustomProperty[T], v: T) =
  ## note: p.changed will not be emitted if new value is same as previous value
  let oldV = p.get()
  p.set(v)
  if oldV == p.get(): return
  emit(p.changed)

proc `[]=`*[T](p: CustomProperty[T], v: T) {.inline.} = p.val = v

proc val*[T](p: CustomProperty[T]): T {.inline.} = p.get()
proc `[]`*[T](p: CustomProperty[T]): T {.inline.} = p.get()

proc unsafeVal*[T](p: CustomProperty[T]): T {.inline.} = p.get()
  ## note: can't get var T due to nature of CustomProperty
proc `{}`*[T](p: CustomProperty[T]): T {.inline.} = p.get()

proc `unsafeVal=`*[T](p: CustomProperty[T], v: T) {.inline.} =
  ## same as val=, but always call setter and does not emit p.changed
  p.set(v)

proc `{}=`*[T](p: CustomProperty[T], v: T) {.inline.} = p.unsafeVal = v

converter toValue*[T](p: CustomProperty[T]): T = p[]
  ##? should this converter be removed?

proc `=copy`*[T](p: var CustomProperty[T], v: CustomProperty[T]) {.error.}

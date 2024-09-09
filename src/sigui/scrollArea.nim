import std/[sequtils]
import pkg/fusion/[matching]
import ./[uibase, animations, mouseArea]

type
  ScrollArea = ref object of Uiobj
    scrollY*: Property[float]
      ## has default transition, use clearTransition() to get rid if it
      ## use targetY for programmable scroll, instead of this property
    scrollX*: Property[float]
      ## has default transition, use clearTransition() to get rid if it
      ## use targetX for programmable scroll, instead of this property

    targetX*: Property[float]
    targetY*: Property[float]

    scrollH*: Property[float]
    scrollW*: Property[float]

    verticalScrollSpeed*: Property[float] = 100.0.property
    horizontalScrollSpeed*: Property[float] = 100.0.property

    verticalScrollFitContent*: Property[bool] = true.property
    verticalScrollOverFit*: Property[float]
  
    horizontalScrollFitContent*: Property[bool] = true.property
    horizontalScrollOverFit*: Property[float]


registerComponent ScrollArea


proc updateScrollH(this: ScrollArea) =
  if this.verticalScrollFitContent[]:
    let h = this.newChildsObject.childs.mapIt(it.y[] + it.h[]).max
    this.scrollH[] = h + this.verticalScrollOverFit[]

proc updateScrollW(this: ScrollArea) =
  if this.horizontalScrollFitContent[]:
    let w = this.newChildsObject.childs.mapIt(it.x[] + it.w[]).max
    this.scrollW[] = w + this.horizontalScrollOverFit[]


method recieve*(this: ScrollArea, signal: Signal) =
  procCall this.super.recieve(signal)

  case signal
  of of ChildAdded():
    let child = signal.ChildAdded.child
    if child.parent == this.newChildsObject:
      this.updateScrollH()
      this.updateScrollW()

      child.x.changed.connectTo this: this.updateScrollW()
      child.w.changed.connectTo this: this.updateScrollW()

      child.y.changed.connectTo this: this.updateScrollH()
      child.h.changed.connectTo this: this.updateScrollH()


method init*(this: ScrollArea) =
  procCall this.super.init
  
  this.verticalScrollFitContent.changed.connectTo this: this.updateScrollH()
  this.verticalScrollOverFit.changed.connectTo this: this.updateScrollH()

  this.horizontalScrollFitContent.changed.connectTo this: this.updateScrollW()
  this.horizontalScrollOverFit.changed.connectTo this: this.updateScrollW()


  this.makeLayout:
    scrollX := this.targetX[]
    scrollY := this.targetY[]

    - this.scrollY.transition(0.2's):
      easing = outSquareEasing

    - this.scrollX.transition(0.2's):
      easing = outSquareEasing

    - ClipRect():
      this.fill parent

      - MouseArea():
        this.fill parent

        this.scrolled.connectTo root, xy:
          root.targetX[] = (root.targetX[] + xy.x * root.horizontalScrollSpeed).max(0).min((root.scrollW[] - root.w[]).max(0))
          root.targetY[] = (root.targetY[] + xy.y * root.verticalScrollSpeed).max(0).min((root.scrollH[] - root.h[]).max(0))

        - UiObj() as container:
          x := -root.scrollX[]
          y := -root.scrollY[]
    

    this.newChildsObject = container


when isMainModule:
  import ./[layouts]

  preview(clearColor = color(1, 1, 1), margin = 20,
    withWindow = proc: Uiobj =
      let this = ScrollArea()
      this.makeLayout:
        w = 200
        h = 200

        - Layout():
          orientation = vertical

          - UiRect():
            w = 200
            h = 100
            color = color(1, 0, 0)

          - UiRect():
            w = 200
            h = 100
            color = color(0, 1, 0)
            radius = 20

          - UiRect():
            w = 200
            h = 100
            color = color(0, 0, 1)

          - UiRect():
            w = 200
            h = 100
            color = color(1, 0.3, 0.3)

          - UiRect():
            w = 200
            h = 100
            color = color(0.3, 1, 0.3)
            radius = 20

          - UiRect():
            w = 200
            h = 100
            color = color(0.3, 0.3, 1)

      this
  )

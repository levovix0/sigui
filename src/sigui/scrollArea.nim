import std/[sequtils]
import pkg/fusion/[matching]
import ./[uibase, animations, mouseArea]

type
  ScrollAreaSetting* = enum
    enableHorizontalScroll
    
    hasScrollBar
    showScrollBar
    
    shrinkScrollBarWhenNotHovered
    hideScrollBarWhenNotHoveredOrScrolled

    # disableAnimationsWhenScrollingUsingBar
    # immediateScrollWhenClickedOnScrollBarArea


  ScrollArea* = ref object of Uiobj
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

    settings*: Property[set[ScrollAreaSetting]] = (
      {ScrollAreaSetting.low..ScrollAreaSetting.high}
    ).property

    verticalScrollbarObj*: CustomProperty[UiObj]
      ## if changed, properties below can be attached by you to new object
    verticalScrollbarOpacity*: Property[float]
      ## has default animation
    verticalScrollBarArea*: MouseArea
    verticalScrollBarMinHeight*: Property[float] = 20.0.property
    verticalScrollBarShrinkedWidth*: Property[float] = 3.0.property
    verticalScrollBarLastShown*: Property[Time]
    verticalScrollBarHideDelay*: Property[Duration] = initDuration(milliseconds = 1000).property

    horizontalScrollbarObj*: CustomProperty[UiObj]
      ## if changed, properties below can be attached by you to new object
    horizontalScrollbarOpacity*: Property[float]
      ## has default animation
    horizontalScrollBarArea*: MouseArea
    horizontalScrollBarMinWidth*: Property[float] = 20.0.property
    horizontalScrollBarShrinkedHeight*: Property[float] = 3.0.property
    horizontalScrollBarLastShown*: Property[Time]
    horizontalScrollBarHideDelay*: Property[Duration] = initDuration(milliseconds = 1000).property

    verticalScrollBarShouldBeVisible: Property[bool]
    horizontalScrollBarShouldBeVisible: Property[bool]
    onTick: tuple[p: Property[bool]]


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


  let scrollArea = this


  template makeScrollBar(
    sbArea, defaultSb, sbOpacity, right, w, h
  ) =
    scrollArea.sbArea = MouseArea()

    let defaultSb {.inject.} = UiRect()
    defaultSb.makeLayout:
      right = scrollArea.sbArea.right
      
      this.binding radius: this.w[] / 2

      proc withAlpha(c: Color, a: float): Color = color(c.r, c.g, c.b, a)
      this.binding color: this.color[].withAlpha(scrollArea.sbOpacity[])

      this.binding visibility:
        if this.h[] == scrollArea.sbArea.h[]: hiddenTree
        elif scrollArea.sbOpacity[] == 0.0: hiddenTree
        else: visible


  makeScrollBar verticalScrollBarArea, defaultVerticalScrollBar, verticalScrollbarOpacity, right, w, h
  makeScrollBar horizontalScrollBarArea, defaultHorizontalScrollBar, horizontalScrollbarOpacity, bottom, h, w
 

  scrollArea.withWindow win:
    win.onTick.connectTo this: scrollArea.onTick.p.changed.emit()

  scrollArea.withAnimator anim:
    anim.onTick.connectTo this: scrollArea.onTick.p.changed.emit()
  

  scrollArea.onTick.p.changed.connectTo scrollArea:
    if hideScrollBarWhenNotHoveredOrScrolled in scrollArea.settings[]:
      if (
        getTime() - scrollArea.verticalScrollBarLastShown[] > scrollArea.verticalScrollBarHideDelay[] and
        not(scrollArea.verticalScrollBarArea.hovered[] or scrollArea.verticalScrollBarArea.pressed[])
      ):
        scrollArea.verticalScrollBarShouldBeVisible[] = false

      if (
        getTime() - scrollArea.horizontalScrollBarLastShown[] > scrollArea.horizontalScrollBarHideDelay[] and
        not(scrollArea.horizontalScrollBarArea.hovered[] or scrollArea.horizontalScrollBarArea.pressed[])
      ):
        scrollArea.horizontalScrollBarShouldBeVisible[] = false


  # actual scroll area
  this.makeLayout:
    scrollX := this.targetX[]
    scrollY := this.targetY[]


    - this.scrollY.transition(0.2's):
      easing = outSquareEasing

    - this.scrollX.transition(0.2's):
      easing = outSquareEasing
    
    - scrollArea.verticalScrollbarOpacity.transition(0.2's):
      easing = outSquareEasing

    - scrollArea.horizontalScrollbarOpacity.transition(0.2's):
      easing = outSquareEasing


    - ClipRect():
      this.fill parent

      - MouseArea():
        this.fill parent

        this.scrolled.connectTo root, xy:
          let xy = if this.parentWindow.keyboard.pressed.containsShift(): vec2(xy.y, xy.x) else: xy
          if enableHorizontalScroll in root.settings[]:
            root.targetX[] = (root.targetX[] + xy.x * root.horizontalScrollSpeed).max(0).min((root.scrollW[] - root.w[]).max(0))
          root.targetY[] = (root.targetY[] + xy.y * root.verticalScrollSpeed).max(0).min((root.scrollH[] - root.h[]).max(0))

        - UiObj() as container:
          x := -root.scrollX[]
          y := -root.scrollY[]
    

    - scrollArea.verticalScrollBarArea:
      this.fillVertical(parent, 2)
      this.right = parent.right - 1
      visibility = if hasScrollBar in scrollArea.settings[]: visible else: collapsed

      w = 5

      scrollArea.verticalScrollbarObj --- defaultVerticalScrollBar.UiObj:
        w = binding:
          if (
            shrinkScrollBarWhenNotHovered in scrollArea.settings[] and
            (not scrollArea.verticalScrollBarArea.hovered[] or scrollArea.verticalScrollBarArea.pressed[])
          ):
            scrollArea.verticalScrollBarShrinkedWidth[]
          else:
            scrollArea.verticalScrollBarArea.w[]
        
        h := ((scrollArea.h[] / scrollArea.scrollH[]).min(1).max(0) * parent.h[]).max(scrollArea.verticalScrollBarMinHeight[])
        
        y := (
          scrollArea.scrollY[] / (scrollArea.scrollH[] - scrollArea.h[] + scrollArea.verticalScrollOverFit[])
        ).min(1).max(0) * (parent.h[] - this.h[])

        - this.w.transition(0.2's):
          easing = outSquareEasing
    

    - scrollArea.horizontalScrollBarArea:
      this.fillHorizontal(parent, 2)
      this.bottom = parent.bottom - 1
      visibility = if hasScrollBar in scrollArea.settings[]: visible else: collapsed

      h = 5

      scrollArea.horizontalScrollbarObj --- defaultHorizontalScrollBar.UiObj:
        h = binding:
          if (
            shrinkScrollBarWhenNotHovered in scrollArea.settings[] and
            (not scrollArea.horizontalScrollBarArea.hovered[] or scrollArea.horizontalScrollBarArea.pressed[])
          ):
            scrollArea.horizontalScrollBarShrinkedHeight[]
          else:
            scrollArea.horizontalScrollBarArea.h[]
        
        w := ((scrollArea.w[] / scrollArea.scrollW[]).min(1).max(0) * parent.w[]).max(scrollArea.horizontalScrollBarMinWidth[])
        
        x := (
          scrollArea.scrollX[] / (scrollArea.scrollW[] - scrollArea.w[] + scrollArea.horizontalScrollOverFit[])
        ).min(1).max(0) * (parent.w[] - this.w[])

        - this.h.transition(0.2's):
          easing = outSquareEasing


    this.newChildsObject = container


  template makeScrollBar2(
    makeSbVisibleIfNeeded, sbShouldBeVisible, sbLastShown, sbArea, sbOpacity, scrollY, enableHorizontalScroll
  ) =
    proc makeSbVisibleIfNeeded =
      if (
        hasScrollBar in scrollArea.settings[] and
        showScrollBar in scrollArea.settings[] and
        enableHorizontalScroll
      ):
        scrollArea.sbShouldBeVisible[] = true
        scrollArea.sbLastShown[] = getTime()


    scrollArea.scrollY.changed.connectTo scrollArea:
      makeSbVisibleIfNeeded()
    
    scrollArea.sbArea.hovered.changed.connectTo scrollArea:
      if scrollArea.sbArea.hovered[]: makeSbVisibleIfNeeded()
    
    scrollArea.sbArea.pressed.changed.connectTo scrollArea, x:
      if scrollArea.sbArea.pressed[]: makeSbVisibleIfNeeded()
    

    scrollArea.sbShouldBeVisible.changed.connectTo scrollArea:
      if scrollArea.sbShouldBeVisible[]:
        scrollArea.sbLastShown[] = getTime()


    scrollArea.binding sbOpacity:
      if scrollArea.sbShouldBeVisible[]:
        1.0
      else:
        0.0
  

  makeScrollBar2(
    makeVerticalScrollBarVisibleIfNeeded, verticalScrollBarShouldBeVisible,
    verticalScrollBarLastShown, verticalScrollBarArea, verticalScrollbarOpacity, scrollY,
    true
  )

  makeScrollBar2(
    makeHorizontalScrollBarVisibleIfNeeded, horizontalScrollBarShouldBeVisible,
    horizontalScrollBarLastShown, horizontalScrollBarArea, horizontalScrollbarOpacity, scrollX,
    enableHorizontalScroll in scrollArea.settings[]
  )



when isMainModule:
  import ./[layouts, styles]

  preview(clearColor = color(1, 1, 1), margin = 20,
    withWindow = proc: Uiobj =
      let this = ScrollArea()
      this.makeLayout:
        w = 200
        h = 200

        - Styler():
          style = makeStyle:
            UiRect:
              w = 190
              h = 100

          - Layout():
            parent.fill this
            orientation = vertical

            - UiRect():
              color = color(1, 0, 0)

            - UiRect():
              color = color(0, 1, 0)
              radius = 20

            - UiRect():
              color = color(0, 0, 1)

            - UiRect():
              color = color(1, 0.3, 0.3)

            - UiRect():
              color = color(0.3, 1, 0.3)
              radius = 20

            - UiRect():
              color = color(0.3, 0.3, 1)

      this
  )

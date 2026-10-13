import std/[sequtils, times]
import ./[uibase, events, animations, mouseArea]

type
  ScrollAreaSetting* = enum
    enableVerticalScroll
    enableHorizontalScroll
    
    hasScrollBar
    showScrollBar
    
    shrinkScrollBarWhenNotHovered
    hideScrollBarWhenNotHoveredOrScrolled

    disableAnimationsWhenScrollingUsingBar
    instantScrollWhenClickedOnScrollBarArea


  UiScrollArea* {.deprecated: "use ScrollArea instead".} = ScrollArea
  ScrollArea* = ref object of Uiobj
    scrollY*, scrollX*: /float  # current visual offset
    targetX*, targetY*: /float  # for programmable scroll
    scrollW*, scrollH*: /float  # size of the content

    scrollSpeed*: /float = /100.0
    fitContent*: /bool = /true
    scrollOverFit*: /float
    barMinSize*: /float = /20.0
    barShrinkedSize*: /float = /3.0
    barHideDelay*: /Duration = /1's

    padding*: /SideOffsets
    color*: /Color = /color(0.5, 0.5, 0.5)
    radius*: /float
  
    settings*: /set[ScrollAreaSetting] = /{ScrollAreaSetting.low..ScrollAreaSetting.high}

    verticalBar* {.cursor.}: UiRect
    verticalBarArea* {.cursor.}: MouseArea
    verticalBarOpacity*: /float
      ## has default animation
    verticalBarLastShown: /Time
    verticalBarShouldBeVisible: /bool

    horizontalBar* {.cursor.}: UiRect
    horizontalBarArea*: MouseArea
    horizontalBarOpacity*: /float
      ## has default animation
    horizontalBarLastShown: /Time
    horizontalBarShouldBeVisible: /bool


registerComponent ScrollArea


proc withAlpha(c: Color, a: float): Color = color(c.r, c.g, c.b, a)


proc `padding=`*(this: ScrollArea, v: float32) =
  this.padding[] = v.allSides


proc updateScrollH(this: ScrollArea) =
  if this.fitContent[]:
    let h = this.newChildsObject.childs.mapIt(it.y[] + it.h[]).max
    this.scrollH[] = h + this.scrollOverFit[]

proc updateScrollW(this: ScrollArea) =
  if this.fitContent[]:
    let w = this.newChildsObject.childs.mapIt(it.x[] + it.w[]).max
    this.scrollW[] = w + this.scrollOverFit[]


method recieve*(this: ScrollArea, signal: Signal) =
  procCall this.super.recieve(signal)

  if signal of ChildAdded:
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
  let scrollArea = this
  
  this.fitContent.changed.connectTo this: this.updateScrollH()
  this.scrollOverFit.changed.connectTo this: this.updateScrollH()

  this.fitContent.changed.connectTo this: this.updateScrollW()
  this.scrollOverFit.changed.connectTo this: this.updateScrollW()

  this.root.onTick.connectTo this:
    if hideScrollBarWhenNotHoveredOrScrolled in scrollArea.settings[]:
      if (
        getTime() - scrollArea.verticalBarLastShown[] > scrollArea.barHideDelay[] and
        not(scrollArea.verticalBarArea.hovered[] or scrollArea.verticalBarArea.pressed[])
      ):
        scrollArea.verticalBarShouldBeVisible[] = false

      if (
        getTime() - scrollArea.horizontalBarLastShown[] > scrollArea.barHideDelay[] and
        not(scrollArea.horizontalBarArea.hovered[] or scrollArea.horizontalBarArea.pressed[])
      ):
        scrollArea.horizontalBarShouldBeVisible[] = false
  

  template setupBar(
    this, mouseY, scrollY, targetY, scrollH, y, h, verticalBarObj
  ) =
    var isDraggingScrollbar: bool
    var prevMouseY: float

    proc moveVerticalBarToMouse(mouseY: float) =
      proc setScrollY(scrollArea: ScrollArea, newScrollY: float) =
        if disableAnimationsWhenScrollingUsingBar in scrollArea.settings[]:
          scrollArea.scrollY.setWithoutTransition newScrollY
        scrollArea.targetY[] = newScrollY

      if isDraggingScrollbar:
        let d = mouseY - prevMouseY
        prevMouseY = mouseY
        scrollArea.setScrollY (
          scrollArea.targetY[] + (d / this.h[] * (scrollArea.scrollH[]))
        ).min(scrollArea.scrollH[] - scrollArea.h[]).max(0)
      
      else:
        if instantScrollWhenClickedOnScrollBarArea in scrollArea.settings[]:
          scrollArea.setScrollY (
            (this.mouseY[] - scrollArea.verticalBarObj[].h[] / 2) / (this.h[] - scrollArea.verticalBarObj[].h[]) *
            (scrollArea.scrollH[] - scrollArea.h[])
          ).min(scrollArea.scrollH[] - scrollArea.h[]).max(0)
        
        else:
          if this.mouseY[] notin (
            scrollArea.verticalBarObj[].y[] ..
            (scrollArea.verticalBarObj[].y[] + scrollArea.verticalBarObj[].h[])
          ):
            scrollArea.setScrollY (
              scrollArea.targetY[] +
              scrollArea.scrollSpeed[] * (if this.mouseY[] < scrollArea.verticalBarObj[].y[]: -1 else: 1)
            ).min(scrollArea.scrollH[] - scrollArea.h[]).max(0)

    
    this.pressed.changed.connectTo scrollArea:
      isDraggingScrollbar = this.mouseY[] in (
        scrollArea.verticalBarObj[].y[] ..
        (scrollArea.verticalBarObj[].y[] + scrollArea.verticalBarObj[].h[])
      )
      prevMouseY = this.mouseY[]
      if (hasScrollBar in scrollArea.settings[]) and this.pressed[]: moveVerticalBarToMouse(this.mouseY[])
    
    this.mouseY.changed.connectTo scrollArea:
      if (hasScrollBar in scrollArea.settings[]) and this.pressed[]: moveVerticalBarToMouse(this.mouseY[])



  # actual scroll area
  this.makeLayout:
    scrollX := this.targetX[]
    scrollY := this.targetY[]

    - this.scrollY.transition(0.2's, outSquareEasing)
    - this.scrollX.transition(0.2's, outSquareEasing)
    - root.verticalBarOpacity.transition(0.2's, outSquareEasing)
    - root.horizontalBarOpacity.transition(0.2's, outSquareEasing)

    - ClipRect.new:
      this.fill parent
      radius = binding: root.radius[]

      - MouseArea.new:
        this.fill parent

        this.scrolled.connectTo root, xy:
          let xy = if this.root.keyboardState.pressed.containsShift(): vec2(xy.y, xy.x) else: xy
          if enableHorizontalScroll in root.settings[]:
            let newX =
              (root.targetX[] + xy.x * root.scrollSpeed[])
              .clamp(0, (root.scrollW[] - (root.w[] - root.padding[].left - root.padding[].right)).max(0))
            
            if abs(xy.x) < 0.5:
              root.scrollX.setWithoutTransition newX
              root.targetX[] = newX
            else:
              root.targetX[] = newX

          if enableVerticalScroll in root.settings[]:
            let newY =
              (root.targetY[] + xy.y * root.scrollSpeed[])
              .clamp(0, (root.scrollH[] - (root.h[] - root.padding[].top - root.padding[].bottom)).max(0))
            
            if abs(xy.y) < 0.5:
              root.scrollY.setWithoutTransition newY
              root.targetY[] = newY
            else:
              root.targetY[] = newY

        - Uiobj.new as container:
          x := -root.scrollX[] + root.padding[].left
          y := -root.scrollY[] + root.padding[].top
    

    - MouseArea() as root.verticalBarArea:
      this.fillVertical(parent, 2)
      this.right = parent.right - 1
      visibility = if hasScrollBar in root.settings[]: visible else: collapsed

      w = 5

      - UiRect() as root.verticalBar:
        w = binding:
          if (
            shrinkScrollBarWhenNotHovered in root.settings[] and
            not (root.verticalBarArea.hovered[] or root.verticalBarArea.pressed[])
          ):
            root.barShrinkedSize[]
          else:
            root.verticalBarArea.w[]
        right = parent.right
        
        h := ((root.h[] / (root.scrollH[])).min(1).max(0) * parent.h[]).max(root.barMinSize[])
        
        y := (
          root.scrollY[] / (root.scrollH[] - root.h[])
        ).min(1).max(0) * (parent.h[] - this.h[])

        - this.w.transition(0.2's, outSquareEasing)
        
        radius := this.w[] / 2
        color := root.color[].withAlpha(root.verticalBarOpacity[])

        visibility = binding:
          if this.h[] > root.verticalBarArea.h[] - 1e-6: hidden
          elif root.verticalBarOpacity[] == 0: hidden
          else: visible
      
      setupBar(this, mouseY, scrollY, targetY, scrollH, y, h, verticalBar)
    

    - MouseArea() as root.horizontalBarArea:
      this.fillHorizontal(parent, 2)
      this.bottom = parent.bottom - 1
      visibility = if hasScrollBar in root.settings[]: visible else: collapsed

      h = 5

      - UiRect() as root.horizontalBar:
        h = binding:
          if (
            shrinkScrollBarWhenNotHovered in root.settings[] and
            (not root.horizontalBarArea.hovered[] or root.horizontalBarArea.pressed[])
          ):
            root.barShrinkedSize[]
          else:
            root.horizontalBarArea.h[]
        bottom = parent.bottom
        
        w = binding: ((root.w[] / root.scrollW[]).min(1).max(0) * parent.w[]).max(root.barMinSize[])
        
        x = binding: (
          root.scrollX[] / (root.scrollW[] - root.w[])
        ).min(1).max(0) * (parent.w[] - this.w[])

        - this.h.transition(0.2's, outSquareEasing)
        
        radius := this.h[] / 2
        color := root.color[].withAlpha(root.horizontalBarOpacity[])

        visibility = binding:
          if this.w[] > root.verticalBarArea.w[] - 1e-6: hidden
          elif root.horizontalBarOpacity[] == 0: hidden
          else: visible
      
      setupBar(this, mouseX, scrollX, targetX, scrollW, x, w, horizontalBar)


    this.newChildsObject = container


  template prepareBar(
    makeSbVisibleIfNeeded, sbShouldBeVisible, sbLastShown, sbArea, sbOpacity, scrollY, scrollEnabled
  ) =
    proc makeSbVisibleIfNeeded =
      if (
        hasScrollBar in scrollArea.settings[] and
        showScrollBar in scrollArea.settings[] and
        scrollEnabled
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


    this.bindingProperty sbOpacity:
      if scrollArea.sbShouldBeVisible[]:
        1.0
      else:
        0.0
  

  prepareBar(
    makeVerticalBarVisibleIfNeeded, verticalBarShouldBeVisible,
    verticalBarLastShown, verticalBarArea, verticalBarOpacity, scrollY,
    enableVerticalScroll in scrollArea.settings[]
  )

  prepareBar(
    makeHorizontalBarVisibleIfNeeded, horizontalBarShouldBeVisible,
    horizontalBarLastShown, horizontalBarArea, horizontalBarOpacity, scrollX,
    enableHorizontalScroll in scrollArea.settings[]
  )



when isMainModule:
  import ./[layouts, styles, windowCreation]

  preview:
    this.clearColor = color(1, 1, 1)
    - ScrollArea.new:
      w = 200; h = 200
      this.margin = 10.allSides; padding = 10.allSides

      - Styler.new:
        style = makeStyle:
          UiRect:
            w = 180; h = 100

        - Layout.new:
          parent.fill this
          orientation = vertical

          - UiRect.new:
            color = color(1, 0, 0)

          - UiRect.new:
            color = color(0, 1, 0)
            radius = 20

          - UiRect.new:
            color = color(0, 0, 1)

          - UiRect.new:
            color = color(1, 0.3, 0.3)

          - UiRect.new:
            color = color(0.3, 1, 0.3)
            radius = 20

          - UiRect.new:
            color = color(0.3, 0.3, 1)

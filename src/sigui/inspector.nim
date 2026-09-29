## Element inspector, similar to the "inspect element" tool of web browsers.
##
## Can be used in two ways:
##
## 1. In a separate window, using `openInspector`:
##
## ```nim
## import sigui, sigui/inspector
##
## let win = newUiWindow(title = "app")
## win.makeLayout:
##   # ...
##
## openInspector win
## run win
## ```
##
## 2. As a regular component, added into any window (for example, docked into the main window of the application):
##
## ```nim
## import sigui, sigui/inspector
##
## let win = newUiWindow(title = "app")
## win.makeLayout:
##   - MyUi.new:
##     w = 400; h = 300
##
##   - Inspector.new as inspector:
##     x = 400; w = 400; h = 300
##     target = win
##     this.overlay = overlay
##
##   - InspectorOverlay.new as overlay:
##     this.fill(parent)
##     this.inspector = inspector
## ```

import std/[tables, times, strutils]
import pkg/[vmath, chroma]
import pkg/siwin/platforms/any/window
import ./[uibase, layouts, mouseArea, scrollArea, windowCreation, systemFonts]


#* ------------- types ------------- *#

type
  WalkNode* = object
    ## a node of the inspected tree, as displayed by the inspector
    obj* {.cursor.}: Uiobj
    depth*: int


  InspectorOverlay* = ref object of Uiobj
    ## internal component, placed into the inspected window (as the top layer).
    ## draws the hover/selected highlight
    inspector* {.cursor.}: Inspector
      ## linked inspector

    hovered: Property[Uiobj]
      ## component under cursor while picking

    badgeText: string
    badgeTypeface: Typeface
    badgeArrangement: Arrangement


  ComponentDetails* = ref object of Layout
    ## information about the selected component

    target*: Uiobj
      ## target selected component, must be set before init
    font*: Font
      ## must be set before init


  Inspector* = ref object of Uiobj
    ## component that displays and allows to explore a component tree of `target`.
    ## can be added into any window, or opened in a separate window using `openInspector`

    overlay* {.cursor.}: InspectorOverlay
      ## linked overlay

    target*: Property[Uiobj]
      ## root of the inspected tree (usually the UiWindow of the application)

    selected*: Property[Uiobj]
      ## component, currently selected in the inspector

    picking*: Property[bool]
      ## while true, mouse events of the inspected window are intercepted,
      ## the component under cursor is highlighted and can be selected by a click.
      ## Esc exits this mode

    showHighlight*: Property[bool] = true.property
      ## draw the highlight of the selected component in the inspected window

    font*: Property[Font]
      ## font used by the inspector texts
      ## (assigned to a system font at init, can be overridden)
    
    updatePeriod*: Property[Duration] = initDuration(milliseconds = 100).property
      ## time between automatic updates

    #--- internal ---

    connectedRoot: UiRoot
      ## root, which gotSignal is currently connected to pickHandler
    pickHandler: EventHandler

    treeScroll: ScrollArea
    treeContainer: Uiobj
      ## rows container of the tree pane

    details: ChangableChild[ComponentDetails]
    updateDetails: Event[void]

    treeNodes: seq[WalkNode]
      ## all nodes of the inspected tree, in depth-first order
    visibleNodes: seq[WalkNode]
      ## nodes displayed in the tree pane (collapapsed subtrees are skipped)
    expanded: Table[int, bool]
      ## manually toggled expanded/collapsed states, by object identity
    fingerprint: seq[int]
      ## structure of the inspected tree on the last tree rebuild
    
    lastUpdated: Time


registerComponent InspectorOverlay
registerComponent Inspector


#* ------------- constants ------------- *#

const
  inspectorRowHeight = 22'f32
  inspectorRowIndent = 13'f32
  inspectorToolbarHeight = 34'f32
  inspectorDefaultWidth = 400'f32
  inspectorDefaultHeight = 300'f32
  inspectorDefaultExpandDepth = 3
    ## nodes that are less deep than this are expanded by default
  inspectorFontSize = 13

  color_panelBg* = "#202020".color
  color_toolbar* = "#202020".color
  color_divider* = "#303030".color
  color_text* = "#c1c1c1".color
  color_textDim* = "#808080".color
  color_accent* = "#3B8BD8".color
  color_rowHover* = "#404040".color
  color_rowPressed* = "#303030".color
  color_rowSelected* = "#405e8c".color
  color_scrollbar* = "#c1c1c1".color

  color_hoverOverlayFill* = "#7090A040".color
  color_hoverOverlayBorder* = "#7090A0C0".color
  color_selectedOverlayBorder* = "#7090A0".color
  color_selectedOverlayFill* = "#7090A020".color
  color_overlayBadge* = "#204060C0".color


const
  crosshairIconSvg* = """<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg">
    <circle cx="8" cy="8" r="4.2" fill="none" stroke="black" stroke-width="1.4"/>
    <line x1="8" y1="0.5" x2="8" y2="3.6" stroke="black" stroke-width="1.4"/>
    <line x1="8" y1="12.4" x2="8" y2="15.5" stroke="black" stroke-width="1.4"/>
    <line x1="0.5" y1="8" x2="3.6" y2="8" stroke="black" stroke-width="1.4"/>
    <line x1="12.4" y1="8" x2="15.5" y2="8" stroke="black" stroke-width="1.4"/>
  </svg>"""

  eyeIconSvg* = """<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg">
    <path d="M1 8 C3 4.5 5.5 3 8 3 C10.5 3 13 4.5 15 8 C13 11.5 10.5 13 8 13 C5.5 13 3 11.5 1 8 Z" fill="none" stroke="black" stroke-width="1.4"/>
    <circle cx="8" cy="8" r="2.4" fill="none" stroke="black" stroke-width="1.4"/>
  </svg>"""

  eyeDisabledIconSvg* = """<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg">
    <path d="M3 4 C1.7 5.1 1.2 6.9 1 8 C1.5 10 4 13 8 13 C9.3 13 10.4 12.7 11.4 12.2 M13 10.9 C14 10 14.7 8.9 15 8 C14.5 6 12 3 8 3 C7.5 3 7 3 6.6 3.1" fill="none" stroke="black" stroke-width="1.4"/>
    <line x1="2.5" y1="13.5" x2="13.5" y2="2.5" stroke="black" stroke-width="1.4"/>
  </svg>"""

  refreshIconSvg* = """<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg">
    <path d="M13.5 8 A5.5 5.5 0 1 1 11.9 4.1" fill="none" stroke="black" stroke-width="1.6"/>
    <path d="M12.3 1.2 L12.6 5.2 L8.8 3.6 Z" fill="black"/>
  </svg>"""

  chevronRightIconSvg* = """<svg width="9" height="9" viewBox="0 0 9 9" xmlns="http://www.w3.org/2000/svg">
    <path d="M2.5 1 L7 4.5 L2.5 8 Z" fill="black"/>
  </svg>"""

  chevronDownIconSvg* = """<svg width="9" height="9" viewBox="0 0 9 9" xmlns="http://www.w3.org/2000/svg">
    <path d="M1 2.5 L8 2.5 L4.5 7 Z" fill="black"/>
  </svg>"""


#* ------------- helpers ------------- *#

proc sameObj(a, b: Uiobj): bool {.inline.} =
  cast[int](a) == cast[int](b)


proc isInspectorInternalObj(o: Uiobj): bool =
  ## is this object a part of an Inspector/InspectorOverlay
  ## (such objects are hidden from the tree view and pick mode)
  var c {.cursor.} = o
  while c != nil:
    if c of Inspector or c of InspectorOverlay: return true
    c = c.parent


proc deepestComponentAt*(root: Uiobj, pos: Vec2): Uiobj =
  ## returns the frontmost (deepest) component of the subtree that contains `pos` (in window coordinates).
  ## returns nil if there is none.
  ## inspector-internal components and hidden/collapsed subtrees are skipped
  proc impl(o: Uiobj): Uiobj =
    if o == nil or o of Inspector or o of InspectorOverlay: return nil
    if o.visibility[] in {hidden, collapsed}: return nil

    for i in countdown(o.childs.high, 0):
      let res = impl(o.childs[i])
      if res != nil: return res

    if pos.x in o.globalX[] .. (o.globalX[] + o.w[]) and
        pos.y in o.globalY[] .. (o.globalY[] + o.h[]):
      result = o

  result = impl(root)


#* ------------- overlay drawing ------------- *#

proc handleAutoUpdate(this: Inspector)

proc updateBadge(this: InspectorOverlay, obj: Uiobj) =
  let text = $obj.w[].round.int & " × " & $obj.h[].round.int
  let typeface = this.inspector.font[].typeface
  if text != this.badgeText or this.badgeTypeface != typeface:
    this.badgeText = text
    this.badgeTypeface = typeface
    this.badgeArrangement = typeset(typeface.withSize(11), text)


proc drawBadge(this: InspectorOverlay, ctx: DrawContext, obj: Uiobj) =
  this.updateBadge(obj)
  if this.badgeArrangement == nil: return

  let bounds = this.badgeArrangement.layoutBounds
  var pos = vec2(obj.globalX[], obj.globalY[] + obj.h[] + 2)

  let win = this.parentRoot
  if win != nil and pos.y + bounds.y + 4 > win.h[]:
    pos.y = obj.globalY[] - bounds.y - 6

  ctx.fillRect(rect(pos, vec2(bounds.x + 8, bounds.y + 4)), color_overlayBadge, 2, true)
  ctx.drawRasterText(pos + vec2(4, 2), this.badgeArrangement, color(1, 1, 1, 1))


method recieve*(this: InspectorOverlay, signal: Signal) =
  procCall this.super.recieve(signal)
  if this.inspector == nil or this.inspector.isDeteached: return

  if signal of BeforeDraw:
    if this.inspector.root != this.root:
      handleAutoUpdate(this.inspector)


method drawInner*(this: InspectorOverlay, ctx: DrawContext) =
  if this.inspector == nil or this.inspector.isDeteached: return
  let insp = this.inspector

  if insp.picking[] and this.hovered[] != nil and not this.hovered[].isDeteached:
    let r = rect(this.hovered[].globalXy, this.hovered[].wh)
    if r.w > 0 and r.h > 0:
      ctx.fillRect(r, color_hoverOverlayFill, 0, true)
      ctx.drawRect(r, color_hoverOverlayBorder, thickness = 1)
      this.drawBadge(ctx, this.hovered[])

  if insp.showHighlight[] and insp.selected[] != nil and not insp.selected[].isDeteached:
    let r = rect(insp.selected[].globalXy, insp.selected[].wh)
    if r.w > 0 and r.h > 0:
      ctx.fillRect(r, color_selectedOverlayFill, 0, true)
      ctx.drawRect(r, color_selectedOverlayBorder, thickness = 2)
      this.drawBadge(ctx, insp.selected[])


#* ------------- tree model ------------- *#

proc collectNodesInto(result: var seq[WalkNode], o: Uiobj, depth: int) =
  if o == nil: return
  if o of Inspector or o of InspectorOverlay: return

  result.add WalkNode(obj: o, depth: depth)
  for child in o.childs:
    result.collectNodesInto(child, depth + 1)


proc isExpanded*(this: Inspector, node: WalkNode): bool =
  let key = cast[int](node.obj)
  if this.expanded.hasKey(key): this.expanded[key]
  else: node.depth < inspectorDefaultExpandDepth


proc collectVisibleNodes(this: Inspector): seq[WalkNode] =
  var skipDepth = -1
  for node in this.treeNodes:
    if skipDepth != -1:
      if node.depth > skipDepth: continue
      skipDepth = -1
    result.add node
    if node.obj.childs.len > 0 and not this.isExpanded(node):
      skipDepth = node.depth


proc computeFingerprint(this: Inspector): seq[int] =
  for node in this.treeNodes:
    result.add cast[int](node.obj)
    result.add node.depth


proc buildRow*(this: Inspector, parent: Uiobj, node: WalkNode, index: int)

proc rebuildTree*(this: Inspector) =
  ## rebuilds the rows of the tree pane from the current state of `target`
  this.treeNodes = @[]
  collectNodesInto(this.treeNodes, this.target[], 0)
  this.visibleNodes = this.collectVisibleNodes()

  if this.treeContainer != nil:
    this.treeContainer.delete()

  let container = Uiobj.new
  this.treeScroll.addChild container
  initIfNeeded container
  this.treeContainer = container

  for i, node in this.visibleNodes:
    this.buildRow(this.treeContainer, node, i)


proc scrollTreeToSelected(this: Inspector) =
  if this.selected[] == nil or this.treeScroll == nil: return

  var index = -1
  for i, node in this.visibleNodes:
    if node.obj.sameObj(this.selected[]):
      index = i
      break
  if index == -1: return

  let y = index.float32 * inspectorRowHeight
  let view = this.treeScroll.h[]
  let cur = this.treeScroll.targetY[]

  if y < cur:
    this.treeScroll.targetY[] = max(0'f32, y - 8)
  elif y + inspectorRowHeight > cur + view:
    this.treeScroll.targetY[] = y + inspectorRowHeight - view + 8


proc select*(this: Inspector, obj: Uiobj, focus = true) =
  ## selects `obj` in the inspector, revealing it in the tree view
  this.selected[] = obj

  if obj != nil:
    var needRebuild = false
    var p {.cursor.} = obj.parent
    while p != nil:
      for node in this.treeNodes:
        if node.obj.sameObj(p):
          if not this.isExpanded(node):
            this.expanded[cast[int](p)] = true
            needRebuild = true
          break
      p = p.parent

    if needRebuild:
      this.rebuildTree()

  if focus:
    this.scrollTreeToSelected()
    # todo: this.root.UiWindow.siwinWindow.focused = true


proc togglePicking*(this: Inspector) =
  ## enables/disables the pick mode
  this.picking[] = not this.picking[]


#* ------------- tree pane ------------- *#

proc buildRow(this: Inspector, parent: Uiobj, node: WalkNode, index: int) =
  let insp = this
  let rowY = index.float32 * inspectorRowHeight
  let expanded = this.isExpanded(node)
  let hasChilds = node.obj.childs.len > 0

  parent.makeLayout:
    this.h[] = this.h[] + inspectorRowHeight

    - Uiobj.new as row:
      y = rowY
      w := insp.treeScroll.w[]
      h = inspectorRowHeight

      - UiRect.new as bg:
        this.fill parent
        radius = 3

        color = binding:
          if insp.selected[].sameObj(node.obj): color_rowSelected
          elif mouse.hovered[]: color_rowHover
          else: color(0, 0, 0, 0)

      - MouseArea.new as mouse:
        this.fill parent

        on this.clicked:
          insp.select(node.obj)

      if hasChilds:
        - MouseArea.new as toggle:
          x = inspectorRowIndent * node.depth.float32
          y = 0
          w = 16
          h = inspectorRowHeight

          on this.clicked:
            insp.expanded[cast[int](node.obj)] = not insp.isExpanded(node)
            insp.rebuildTree()

          - UiSvgImage.new:
            this.centerIn parent
            image = if expanded: chevronDownIconSvg else: chevronRightIconSvg
            color = color_textDim

      - UiText.new:
        x = inspectorRowIndent * node.depth.float32 + (if hasChilds: 20'f32 else: 4'f32)
        centerY = parent.center
        text = node.obj.componentTypeName
        font = insp.font[]
        color = if node.obj.visibility[] == visible: color_text else: color_textDim


#* ------------- picking ------------- *#

proc pickHitTest(this: Inspector, pos: Vec2): Uiobj =
  if this.target[] == nil: return nil
  this.target[].deepestComponentAt(pos)


proc setPickCursor(this: Inspector, hit: Uiobj) =
  if this.target[] == nil: return
  let win = this.target[].root

  if hit != nil and not hit.isInspectorInternalObj:
    win.cursor = Cursor(kind: builtin, builtin: BuiltinCursor.cross)
  else:
    win.cursor = Cursor()


proc handlePickSignal(this: Inspector, signal: Signal) =
  ## intercepts the window events of the inspected application while picking
  if not this.picking[]: return

  if signal of WindowEvent:
    let we = signal.WindowEvent
    let ev = we.event

    if ev of MouseMoveEvent:
      let e = ((ref MouseMoveEvent)ev)[]
      let hit = this.pickHitTest(e.pos)
      this.overlay.hovered[] = hit
      we.handled = true
      this.setPickCursor(hit)

    elif ev of MouseButtonEvent:
      let e = ((ref MouseButtonEvent)ev)[]
      let hit = this.pickHitTest(e.window.mouse.pos)

      if e.pressed:
        # block the application, but let the clicks into the inspector itself
        if hit != nil and not hit.isInspectorInternalObj:
          we.handled = true

      else:
        if hit != nil and not hit.isInspectorInternalObj:
          we.handled = true
          this.select hit
          this.picking[] = false

    elif ev of KeyEvent:
      let e = ((ref KeyEvent)ev)[]
      we.handled = true
      if e.pressed and e.key == Key.escape:
        this.picking[] = false

    elif (
      ev of ScrollEvent or ev of ClickEvent or ev of TextInputEvent or
      ev of StateBoolChangedEvent or ev of DropEvent
    ):
      we.handled = true

  elif signal of GetActiveCursor:
    let hit = this.pickHitTest(this.target[].root.mouseState.pos)
    if hit != nil and not hit.isInspectorInternalObj:
      signal.GetActiveCursor.cursor = (ref Cursor)(kind: builtin, builtin: BuiltinCursor.cross)
      signal.GetActiveCursor.handled = true


proc updatePicking(this: Inspector) =
  ## (dis)connects the pick mode event interception from the target window
  if this.connectedRoot != nil:
    disconnect this.connectedRoot.gotSignal, this.pickHandler
    this.connectedRoot = nil

  if this.overlay != nil: this.overlay.hovered[] = nil

  if this.picking[] and this.target[] != nil:
    let r = this.target[].root
    connect r.gotSignal, this.pickHandler, proc(signal: Signal) =
      this.handlePickSignal(signal)
    this.connectedRoot = r

  if this.overlay != nil: redraw this.overlay


proc retarget(this: Inspector) =
  ## re-attach to the current value of `target`
  this.updatePicking()  # disconnects pick interception from the old root
  this.fingerprint = @[]  # force rebuild on the next tick
  this.rebuildTree()
  this.updateDetails.emit()


proc handleAutoUpdate(this: Inspector) =
  # drop the selection if the object was deleted
  if this.selected[] != nil and this.selected[].isDeteached:
    this.selected[] = nil
    this.updateDetails.emit()

  if this.target[] != nil:
    this.treeNodes = @[]
    this.treeNodes.collectNodesInto(this.target[], 0)
    let fp = this.computeFingerprint()
    if fp != this.fingerprint:
      this.fingerprint = fp
      this.rebuildTree()

  if this.selected[] != nil:
    this.updateDetails.emit()

  this.lastUpdated = getTime()


#* ------------- ui ------------- *#

method init*(this: ComponentDetails) =
  procCall this.super.init()

  this.makeLayout:
    this.col(4)
    padding = 12.allSides

    if root.target == nil:
      - UiText.new:
        text = "Select an element to inspect"
        font = root.font
        color = color_textDim

    else:
      - UiText.new:
        text = root.target.componentTypeName
        font = root.font.typeface.withSize(16)
        color = color_accent

      - UiText.new:
        var parts: seq[string] = @[root.target.componentTypeName]
        var p {.cursor.} = root.target.parent
        while p != nil:
          parts.insert(p.componentTypeName, 0)
          p = p.parent
        text = parts.join(" › ")
        font = root.font.typeface.withSize(11)
        color = color_textDim

      - Uiobj.new:
        h = 6

      for field in root.target.formatFields():
        let i = field.find(':')

        if i != -1:
          let
            fieldName = field[0 ..< i].strip
            fieldValue = field[(i+1) ..< field.len].strip

          - Layout.new:
            orientation = horizontal
            gap = 8
            w := parent.w[]

            - UiText.new:
              text = fieldName
              font = root.font.typeface.withSize(12)
              color = color_textDim
              w = 130

            - UiText.new:
              text = fieldValue
              font = root.font.typeface.withSize(12)
              color = color_text


method init*(this: Inspector) =
  # note: init runs before the property assignments of the outer makeLayout
  # block, so these defaults are always overridden by explicit external
  # position/size (used to dock the inspector into a part of the window)
  if this.w[] == 0: this.w[] = inspectorDefaultWidth
  if this.h[] == 0: this.h[] = inspectorDefaultHeight

  this.makeLayout:
    on this.target.changed:
      this.retarget()
      if this.overlay != nil: redraw this.overlay

    on this.selected.changed:
      if this.overlay != nil: redraw this.overlay
    
    on this.showHighlight.changed:
      if this.overlay != nil: redraw this.overlay

    on this.picking.changed:
      this.updatePicking()
    
    on this.font.changed:
      this.rebuildTree()

    on this.root.onTick:
      if (getTime() - root.lastUpdated) > root.updatePeriod[]:
        handleAutoUpdate(root)

    - UiRect.new:
      this.fill parent
      color = color_panelBg

    - UiRect.new as toolbar:
      this.fillHorizontal parent
      h = inspectorToolbarHeight
      color = color_toolbar

      - UiRect.new:
        x = 0
        y = parent.h[]
        w := parent.w[]
        h = 1
        color = color_divider

      # pick mode toggle button
      - UiRect.new:
        x = 6
        centerY = parent.center
        w = 26
        h = 26
        radius = 5

        color = binding:
          if root.picking[]: color_accent
          elif pickMa.hovered[]: color_rowHover
          else: color(0, 0, 0, 0)

        - MouseArea.new as pickMa:
          this.fill parent
          cursor = BuiltinCursor.pointingHand

          on this.clicked:
            root.togglePicking()

        - UiSvgImage.new:
          this.centerIn parent
          image = crosshairIconSvg
          color = binding:
            if root.picking[]: color(1, 1, 1, 1)
            elif pickMa.hovered[]: color_text
            else: color_textDim

      # refresh button
      - UiRect.new:
        x = 38
        centerY = parent.center
        w = 26
        h = 26
        radius = 5

        color = binding:
          if refreshMa.hovered[]: color_rowHover
          else: color(0, 0, 0, 0)

        - MouseArea.new as refreshMa:
          this.fill parent
          cursor = BuiltinCursor.pointingHand

          on this.clicked:
            root.fingerprint = @[]
            root.rebuildTree()
            root.updateDetails.emit()

        - UiSvgImage.new:
          this.centerIn parent
          image = refreshIconSvg
          color = binding:
            if refreshMa.hovered[]: color_text
            else: color_textDim

      # highlight toggle button
      - UiRect.new:
        x = 70
        centerY = parent.center
        w = 26
        h = 26
        radius = 5

        color = binding:
          if root.showHighlight[]: color_accent
          elif highlightMa.hovered[]: color_rowHover
          else: color(0, 0, 0, 0)

        - MouseArea.new as highlightMa:
          this.fill parent
          cursor = BuiltinCursor.pointingHand

          on this.clicked:
            root.showHighlight[] = not root.showHighlight[]

        - UiSvgImage.new:
          this.centerIn parent
          image = binding:
            if root.showHighlight[]: eyeIconSvg else: eyeDisabledIconSvg
          color = binding:
            if root.showHighlight[]: color(1, 1, 1, 1)
            elif highlightMa.hovered[]: color_text
            else: color_textDim

    - ScrollArea.new as root.treeScroll:
      top = toolbar.bottom; bottom = parent.bottom
      x = 0; w := parent.w[] * 0.45

      + this.verticalScrollbar[].UiRect:
        color = color_scrollbar
      + this.horizontalScrollbar[].UiRect:
        color = color_scrollbar

      # note: here will be the root.treeContainer

    - UiRect.new:
      top = toolbar.bottom; bottom = parent.bottom
      left = root.treeScroll.right; w = 1
      color = color_divider

    - ScrollArea.new:
      top = toolbar.bottom
      bottom = parent.bottom
      left = root.treeScroll.right + 1
      right = parent.right

      + this.verticalScrollbar[].UiRect:
        color = color_scrollbar
      + this.horizontalScrollbar[].UiRect:
        color = color_scrollbar

      root.details --- ComponentDetails(target: root.selected[], font: root.font[]):
        <--- {update}: root.selected[]; root.font[]; root.updateDetails[]

  if this.font[] == nil:
    this.font[] = findSystemFont().withSize(inspectorFontSize)

  if this.target[] != nil:
    this.retarget()


method recieve*(this: Inspector, signal: Signal) =
  procCall this.super.recieve(signal)

  # exit pick mode on Esc pressed while the mouse is over the inspector itself
  if signal of WindowEvent and signal.WindowEvent.event of KeyEvent:
    let e = ((ref KeyEvent)signal.WindowEvent.event)[]
    if e.pressed and e.key == Key.escape and this.picking[]:
      this.picking[] = false


#* ------------- separate window mode ------------- *#

proc openInspector*(
  target: Uiobj,
  size = ivec2(960, 640),
  title = "Inspector",
) =
  ## opens an inspector for `target` in a separate window and returns it.
  ##
  ## the returned window should be run using `runWithInspector` (together
  ## with the main window), unless `window` was provided by the caller.

  var win = newUiWindow(size = size, title = title)
  win.clearColor = color_panelBg
  win.siwinWindow.firstStep()
  var overlay: InspectorOverlay
  
  target.root.makeLayout:
    - InspectorOverlay.new as (overlay):
      layer = after parent
      this.fill parent

  win.makeLayout:
    on target.root.onTick:
      if win != nil and win.siwinWindow.opened:
        win.siwinWindow.step()
        if target.root of UiWindow:
          makeCurrent target.root.UiWindow.siwinWindow
      else:
        win = nil
    
    - Inspector.new:
      this.fill parent
      this.overlay = overlay
      overlay.inspector = this
      target = target

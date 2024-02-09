import times, unicode, strutils
import siwin, fusion/matching
import ./[uibase, mouseArea]

type
  Blinking* = object
    enabled*: Property[bool] = true.property
    period*: Property[Duration] = initDuration(milliseconds = 1000).property

    time: Property[Duration]


  TextAreaInteraction* = enum
    textInput
    activatingUsingMouse
    deactivatingUsingMouse
    deactivatingUsingEsc
    navigationUsingArrows
    navigationUsingMouse
    # selecting
    # selectingWordsByDobleClick
    # selectingAllTextByDobleClick
    # selectingAllTextByTripleClick
    # # note: implement selecting all text on activation by yourself if you need it
    # copyingUsingCtrlC
    # copyingUsingSelection
    # pastingUsingCtrlV
    # pastingUsingMiddleMouseButton
    # deactivatingAndActivatingUsingMiddleMouseButton

  TextArea* = ref object of Uiobj
    cursorObj*: CustomProperty[UiObj]
    selectionObj*: CustomProperty[Uiobj]
    textObj*: CustomProperty[UiText]

    active*: Property[bool]
    text*: Property[string]
    cursorPos*: CustomProperty[int]
    blinking*: Blinking

    cursorX*: Property[float32]  # in pixels
    offset*: Property[float32]  # in pixels
    # note: cursorX and offset is provided in case if you want to animate them
    followCursorOffset*: Property[float32]  # in pixels
    
    allowedInteractions*: set[TextAreaInteraction] = {
      TextAreaInteraction.textInput,
      activatingUsingMouse,
      deactivatingUsingMouse,
      deactivatingUsingEsc,
      navigationUsingArrows,
      navigationUsingMouse,
      # selecting,
      # selectingWordsByDobleClick,
      # selectingAllTextByTripleClick,
      # copyingUsingCtrlC,
      # copyingUsingSelection,
      # pastingUsingCtrlV,
      # pastingUsingMiddleMouseButton,
      # deactivatingAndActivatingUsingMiddleMouseButton,
    }
    
    m_cursorPos: int

registerComponent TextArea


proc `mod`(a, b: Duration): Duration =
  result = a
  while result > b:
    result -= b


method recieve*(this: TextArea, signal: Signal) =
  procCall this.super.recieve(signal)

  proc findLeftCtrlWord(): int =
    var fondLetter = false
    result = 0
    for i in countdown(this.cursorPos[].min(this.text[].runeLen) - 1, 0):
      if fondLetter and not this.text[].runeAtPos(i).isAlpha:
        result = i + 1
        break
      elif this.text[].runeAtPos(i).isAlpha:
        fondLetter = true
  
  proc findRightCtrlWord(): int =
    var fondLetter = false
    result = this.text[].runeLen
    for i in countup(this.cursorPos[].max(0), this.text[].runeLen - 1):
      if fondLetter and not this.text[].runeAtPos(i).isAlpha:
        result = i
        break
      elif this.text[].runeAtPos(i).isAlpha:
        fondLetter = true

  case signal
  of of WindowEvent(event: @ea is of KeyEvent(), handled: false):
    let e = (ref KeyEvent)ea
    if navigationUsingArrows in this.allowedInteractions and this.active[]:
      case e
      of (window: @window, key: @key, pressed: true, generated: false):
        case key
        of Key.left:
          if Key.lcontrol in window.keyboard.pressed or Key.rcontrol in window.keyboard.pressed:
            this.cursorPos[] = findLeftCtrlWord()
          else:
            this.cursorPos[] = this.cursorPos[] - 1

        of Key.right:
          if Key.lcontrol in window.keyboard.pressed or Key.rcontrol in window.keyboard.pressed:
            this.cursorPos[] = findRightCtrlWord()
          else:
            this.cursorPos[] = this.cursorPos[] + 1
        
        of Key.up:
          this.cursorPos[] = 0
        
        of Key.down:
          this.cursorPos[] = this.text[].runeLen

        else: discard

    if textInput in this.allowedInteractions and this.active[]:
      case e
      of (window: @window, key: @key, pressed: true, generated: false):
        case key
        of Key.backspace:
          if this.cursorPos[] > 0:
            if Key.lcontrol in window.keyboard.pressed or Key.rcontrol in window.keyboard.pressed:
              let i = findLeftCtrlWord()
              let offset = this.text[].runeOffset(i)
              let offset2 =
                if this.cursorPos[] == this.text[].runeLen:
                  this.text[].len
                else:
                  this.text[].runeOffset(this.cursorPos[])
              this.text{}.delete offset..(offset2 - 1)
              this.text.changed.emit(this.text[])
              this.cursorPos[] = i
            else:
              let i = this.cursorPos[] - 1
              let offset = this.text[].runeOffset(this.cursorPos[] - 1)
              this.text{}.delete offset..(offset + this.text[].runeLenAt(offset) - 1)
              this.text.changed.emit(this.text[])
              this.cursorPos[] = i

        of Key.del:
          if this.cursorPos[] < this.text[].runeLen:
            if Key.lcontrol in window.keyboard.pressed or Key.rcontrol in window.keyboard.pressed:
              let i = findRightCtrlWord()
              let offset = this.text[].runeOffset(this.cursorPos[])
              let offset2 =
                if i == this.text[].runeLen:
                  this.text[].len
                else:
                  this.text[].runeOffset(i)
              this.text{}.delete offset..(offset2 - 1)
              this.text.changed.emit(this.text[])
            else:
              let offset = this.text[].runeOffset(this.cursorPos[])
              this.text{}.delete offset..(offset + this.text[].runeLenAt(offset) - 1)
              this.text.changed.emit(this.text[])
        
        else: discard
    
    if deactivatingUsingEsc in this.allowedInteractions and this.active[]:
      case e
      of (window: @window, key: @key, pressed: true, generated: false):
        if key == Key.escape:
          this.active[] = false


  of of WindowEvent(event: @ea is of TextInputEvent(), handled: false):
    let e = (ref TextInputEvent)ea
    if textInput in this.allowedInteractions and this.active[]:
      if e.text in ["\8", "\13", "\127"]:
        ## ignore backspace, enter and delete  # todo: in siwin
      else:
        if this.cursorPos[] == this.text[].runeLen:
          this.text[] = this.text[] & e.text
        else:
          this.text{}.insert e.text, this.text[].runeOffset(this.cursorPos[])
          this.text.changed.emit(this.text[])
        this.cursorPos[] = this.cursorPos[] + e.text.runeLen
        signal.WindowEvent.handled = true


method init*(this: TextArea) =
  if this.initialized: return
  procCall this.super.init()

  this.cursorPos = CustomProperty[int](
    get: proc(): int = this.m_cursorPos,
    set: proc(x: int) = this.m_cursorPos = x.max(0).min(this.text[].runeLen),
  )
  
  this.text.changed.connectTo this:
    this.cursorPos[] = this.cursorPos[].max(0).min(this.text[].runeLen)
    this.blinking.time[] = DurationZero
  
  this.cursorPos.changed.connectTo this:
    this.blinking.time[] = DurationZero

  this.makeLayout:
    this.withWindow win:
      win.onTick.connectTo this:
        this.blinking.time[] = (this.blinking.time + e.deltaTime) mod (this.blinking.period[] * 2)

    - MouseArea():
      this.fill parent

      this.onSignal.connectTo this, signal:
        if deactivatingUsingMouse in root.allowedInteractions and root.active[] and not this.hovered[]:
          case signal
          of of WindowEvent(event: @ea is of MouseButtonEvent(), handled: false):
            let e = (ref MouseButtonEvent)ea
            if e.pressed: root.active[] = false

      this.pressed.changed.connectTo root, pressed:
        if activatingUsingMouse in root.allowedInteractions and pressed:
          root.active[] = true
        if navigationUsingMouse in root.allowedInteractions and pressed:
          let arrangement = root.textObj{}.arrangement[]
          if arrangement != nil:
            var i = 0
            while true:
              if i > arrangement.selectionRects.high: break
              if arrangement.selectionRects[i].x + arrangement.selectionRects[i].w / 2 > this.mouseX[]: break
              inc i
            root.cursorPos[] = i
          

      - ClipRect() as clip:
        this.fill parent

        - Uiobj() as offset:
          this.fillVertical parent
          # this.binding w: root.textObj[].w[]
          this.binding x: root.offset[]

          root.textObj --- newUiText():
            this.centerY = parent.center
            this.binding text: root.text[]
            this.x[] = 1

          root.cursorObj --- newUiRect().UiObj:
            this.fillVertical parent
            this.w[] = 2
            this.binding visibility:
              if root.active[]:
                if root.blinking.enabled[]:
                  if root.blinking.time[] <= root.blinking.period[]:
                    Visibility.visible
                  else:
                    Visibility.hiddenTree
                else: Visibility.visible
              else: Visibility.hiddenTree
            do: discard
            do: false  # redraw

            this.visibility.changed.connectTo this:
              redraw this

            this.binding x: root.cursorX[]
            root.binding cursorX:
              let arrangement = root.textObj{}.arrangement[]
              if arrangement != nil:
                let pos = root.cursorPos[]
                if pos > arrangement.positions.high:
                  arrangement.layoutBounds.x
                else:
                  arrangement.positions[pos].x
              else: 0
            
            proc followCursor =
              let x = this.x[] + offset.x[]
              if x > clip.w[] - root.followCursorOffset[] - 2:
                offset.x[] = -this.x[] + clip.w[] - root.followCursorOffset[] - 2
              elif x < root.followCursorOffset[]:
                offset.x[] = -this.x[] + root.followCursorOffset[]
            
            this.x.changed.connectTo root: followCursor()
            root.followCursorOffset.changed.connectTo root: followCursor()
    
    this.newChildsObject = clip


when isMainModule:
  const typefaceFile = staticRead "../../tests/Roboto-Regular.ttf"
  let typeface = parseTtf(typefaceFile)

  preview(clearColor = color(1, 1, 1), margin = 20,
    withWindow = proc: Uiobj =
      let this = TextArea()
      init this
      this.text[] = "start text"
      this.textObj[].font[] = typeface.withSize(24)
      this.w[] = 400
      this.h[] = this.textObj[].h[]
      this.makeLayout:
        - UiRectBorder():
          this.fill(parent, -1)
      this
  )

import times, unicode, strutils
import siwin
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
    
    selectingUsingMouse
    selectingUsingKeyboard
    selectingWordsByDobleClick
    selectingAllTextByDobleClick
    selectingAllTextByTripleClick
    selectingAllTextByCtrlA
    # note: implement selecting all text on activation by yourself if you need it
    
    copyingUsingCtrlC
    cuttingUsingCtrlX
    pastingUsingCtrlV

    savingUndoStates  # automatically push states to undo buffer before handling cenrtain interactions
    undoingUsingCtrlZ
    redoingUsingCtrlShiftZ
    
    # copyingUsingSelection
    # pastingUsingMiddleMouseButton
    # deactivatingAndActivatingUsingMiddleMouseButton


  TextArea* = ref object of Uiobj
    cursorObj*: ChangableChild[Uiobj]
    selectionObj*: ChangableChild[Uiobj]
    textObj*: ChangableChild[UiText]

    active*: Property[bool]
    text*: Property[string]
    cursorPos*: CustomProperty[int]
    blinking*: Blinking
    selectionStart*, selectionEnd*: CustomProperty[int]
    followCursorOffset*: Property[float32]  # in pixels

    keyDown*: Event[KeyEvent]

    cursorX*: Property[float32]  # in pixels
    offset*: Property[float32]  # in pixels
    selectionStartX*, selectionEndX*: Property[float32]  # in pixels
    # note: provided in case if you want to animate them
    
    allowedInteractions*: set[TextAreaInteraction] =
      {TextAreaInteraction.low..TextAreaInteraction.high} -
      {TextAreaInteraction.selectingAllTextByDobleClick}

    undoBuffer*: seq[tuple[text: string, cursorPos: int, selectionStart, selectionEnd: int]]
    undoBufferLimit*: int = 200
    redoIndex*: int

    doubleClick: bool
    lastDoubleClickTime: Time
    
    m_cursorPos: int
    m_selectionStart, m_selectionEnd: int

registerComponent TextArea


proc `mod`(a, b: Duration): Duration =
  result = a
  while result > b:
    result -= b


proc eraseSelectedText*(this: TextArea) =
  if this.selectionStart[] == this.selectionEnd[]: return

  let selStart = min(this.selectionStart[], this.selectionEnd[])
  let selEnd = max(this.selectionStart[], this.selectionEnd[])

  let startOffset = this.text[].runeOffset(selStart)
  let endOffset = this.text[].runeOffset(selEnd)
  
  this.text{}.delete startOffset..<(if endOffset == -1: this.text[].len else: endOffset)
  this.text.changed.emit()
  
  this.selectionStart[] = selStart
  this.selectionEnd[] = selStart
  this.cursorPos[] = selStart


proc selectedText*(this: TextArea): string =
  if this.selectionStart[] == this.selectionEnd[]: return ""

  let selStart = min(this.selectionStart[], this.selectionEnd[])
  let selEnd = max(this.selectionStart[], this.selectionEnd[])

  let startOffset = this.text[].runeOffset(selStart)
  let endOffset = this.text[].runeOffset(selEnd)

  result = this.text[][startOffset..<(if endOffset == -1: this.text[].len else: endOffset)]


proc pushState*(this: TextArea) =
  if this.redoIndex != this.undoBuffer.len:
    this.undoBuffer.setLen(this.redoIndex+1)

  if this.undoBufferLimit > 0 and this.undoBuffer.len >= this.undoBufferLimit:
    this.undoBuffer.delete(0)

  this.undoBuffer.add (this.text[], this.cursorPos[], this.selectionStart[], this.selectionEnd[])
  this.redoIndex = this.undoBuffer.len


proc restoreState(this: TextArea, state: tuple[text: string, cursorPos: int, selectionStart, selectionEnd: int]) =
  this.text[] = state.text
  this.cursorPos[] = state.cursorPos
  this.selectionStart[] = state.selectionStart
  this.selectionEnd[] = state.selectionEnd


proc undo*(this: TextArea) =
  if this.redoIndex - 1 notin 0..this.undoBuffer.high: return

  if this.redoIndex == this.undoBuffer.len:
    this.pushState()
    this.redoIndex = this.undoBuffer.high-1
    this.restoreState(this.undoBuffer[this.redoIndex])
  else:
    this.redoIndex -= 1
    this.restoreState(this.undoBuffer[this.redoIndex])


proc redo*(this: TextArea) =
  if this.redoIndex + 1 notin 0..this.undoBuffer.high: return

  this.redoIndex += 1
  this.restoreState(this.undoBuffer[this.redoIndex])


template onKeyDown*(this: TextArea, expectedKey: Key, body: untyped) =
  this.keyDown.connectTo this, event:
    if event.key == expectedKey: body


proc findLeftCtrlWord(this: TextArea, inBorders: bool = false): int =
  var fondLetter = inBorders
  result = 0
  for i in countdown(this.cursorPos[].min(this.text[].runeLen) - 1, 0):
    if fondLetter and not this.text[].runeAtPos(i).isAlpha:
      result = i + 1
      break
    elif this.text[].runeAtPos(i).isAlpha:
      fondLetter = true

proc findRightCtrlWord(this: TextArea, inBorders: bool = false): int =
  var fondLetter = inBorders
  result = this.text[].runeLen
  for i in countup(this.cursorPos[].max(0), this.text[].runeLen - 1):
    if fondLetter and not this.text[].runeAtPos(i).isAlpha:
      result = i
      break
    elif this.text[].runeAtPos(i).isAlpha:
      fondLetter = true


method recieve*(this: TextArea, signal: Signal) =
  procCall this.super.recieve(signal)
  
  if signal of WindowEvent and signal.WindowEvent.event of KeyEvent and signal.WindowEvent.handled == false:
    let e = (ref KeyEvent)signal.WindowEvent.event

    if this.active[]:
      if e.pressed and (not e.generated):
        this.keyDown.emit(e[])

    if navigationUsingArrows in this.allowedInteractions and this.active[]:
      if e.pressed and (not e.generated):
        let window = e.window

        proc handleSelection =
          if selectingUsingKeyboard in this.allowedInteractions:
            if Key.lshift in window.keyboard.pressed or Key.rshift in window.keyboard.pressed:
              this.selectionEnd[] = this.cursorPos[]
            else:
              this.selectionStart[] = this.cursorPos[]
              this.selectionEnd[] = this.cursorPos[]
        
        case e.key
        of Key.left:
          if Key.lcontrol in window.keyboard.pressed or Key.rcontrol in window.keyboard.pressed:
            this.cursorPos[] = this.findLeftCtrlWord()
          else:
            this.cursorPos[] = this.cursorPos[] - 1
          handleSelection()

        of Key.right:
          if Key.lcontrol in window.keyboard.pressed or Key.rcontrol in window.keyboard.pressed:
            this.cursorPos[] = this.findRightCtrlWord()
          else:
            this.cursorPos[] = this.cursorPos[] + 1
          handleSelection()

        of Key.up, Key.home:
          this.cursorPos[] = 0
          handleSelection()

        of Key.down, Key.End:
          this.cursorPos[] = this.text[].runeLen
          handleSelection()

        else: discard

    if this.active[]:
      if e.pressed and (not e.generated):
        let window = e.window
        
        case e.key
        of Key.a:
          if selectingAllTextByCtrlA in this.allowedInteractions:
            if window.keyboard.pressed.containsControl():   # when crl+a pressed and selectingAllTextByCtrlA enabled
              # select all text
              this.selectionStart[] = 0
              this.selectionEnd[] = this.text[].runeLen
        
        of Key.c:
          if copyingUsingCtrlC in this.allowedInteractions:
            if window.keyboard.pressed.containsControl():  # when crl+c pressed and copyingUsingCtrlC enabled
              # copy selected text
              if this.selectionStart[] != this.selectionEnd[]:
                this.parentWindow.clipboard.text = this.selectedText
              else:
                this.parentWindow.clipboard.text = this.text[]
        
        of Key.v:
          if pastingUsingCtrlV in this.allowedInteractions:
            if window.keyboard.pressed.containsControl():  # when crl+v pressed and pastingUsingCtrlV enabled
              # paste selected text
              if savingUndoStates in this.allowedInteractions:
                this.pushState()
              this.eraseSelectedText()

              let ct = this.parentWindow.clipboard.text
              let offset = this.text.runeOffset(this.cursorPos[])
              this.text{}.insert(ct, (if offset == -1: this.text.len else: offset))
              this.text.changed.emit()
              this.cursorPos[] = this.cursorPos[] + ct.runeLen
              this.selectionStart[] = this.cursorPos[]
              this.selectionEnd[] = this.cursorPos[]

        of Key.x:
          if cuttingUsingCtrlX in this.allowedInteractions:
            if window.keyboard.pressed.containsControl():  # when crl+x pressed and cuttingUsingCtrlX enabled
              # cut selected text
              if this.selectionStart[] != this.selectionEnd[]:
                if savingUndoStates in this.allowedInteractions:
                  this.pushState()
                this.parentWindow.clipboard.text = this.selectedText
                this.eraseSelectedText()
        
        of Key.z:
          if undoingUsingCtrlZ in this.allowedInteractions:
            if window.keyboard.pressed.containsControl():  # when crl+z pressed and undoingUsingCtrlZ enabled
              if redoingUsingCtrlShiftZ in this.allowedInteractions and window.keyboard.pressed.containsShift():
                this.redo()
              else:
                this.undo()

        else: discard

    if textInput in this.allowedInteractions and this.active[]:
      if e.pressed and (not e.generated):
        let window = e.window
        
        case e.key
        of Key.backspace:
          if savingUndoStates in this.allowedInteractions:
            this.pushState()

          if this.selectionStart[] != this.selectionEnd[]:
            this.eraseSelectedText()

          elif this.cursorPos[] > 0:
            if window.keyboard.pressed.containsControl():
              # delete whole word
              let i = this.findLeftCtrlWord()
              let offset = this.text[].runeOffset(i)
              let offset2 =
                if this.cursorPos[] == this.text[].runeLen:
                  this.text[].len
                else:
                  this.text[].runeOffset(this.cursorPos[])
              this.text{}.delete offset..(offset2 - 1)
              this.text.changed.emit()
              this.cursorPos[] = i

            else:
              # delete single letter
              let i = this.cursorPos[] - 1
              let offset = this.text[].runeOffset(this.cursorPos[] - 1)
              this.text{}.delete offset..(offset + this.text[].runeLenAt(offset) - 1)
              this.text.changed.emit()
              this.cursorPos[] = i

        of Key.del:
          if savingUndoStates in this.allowedInteractions:
            this.pushState()

          if this.selectionStart[] != this.selectionEnd[]:
            this.eraseSelectedText()

          elif this.cursorPos[] < this.text[].runeLen:
            if window.keyboard.pressed.containsControl():
              # delete whole word
              let i = this.findRightCtrlWord()
              let offset = this.text[].runeOffset(this.cursorPos[])
              let offset2 =
                if i == this.text[].runeLen:
                  this.text[].len
                else:
                  this.text[].runeOffset(i)
              this.text{}.delete offset..(offset2 - 1)
              this.text.changed.emit()

            else:
              # delete single letter
              let offset = this.text[].runeOffset(this.cursorPos[])
              this.text{}.delete offset..(offset + this.text[].runeLenAt(offset) - 1)
              this.text.changed.emit()
        
        else: discard
    
    if deactivatingUsingEsc in this.allowedInteractions and this.active[]:
      if e.pressed and (not e.generated):
        if e.key == Key.escape:
          this.active[] = false


  if signal of WindowEvent and signal.WindowEvent.event of TextInputEvent and signal.WindowEvent.handled == false:
    let e = (ref TextInputEvent)signal.WindowEvent.event

    if textInput in this.allowedInteractions and this.active[]:
      if e.text in ["\8", "\13", "\127"]:
        ## ignore backspace, enter and delete  # todo: in siwin
      else:
        if savingUndoStates in this.allowedInteractions:
          this.pushState()

        this.eraseSelectedText()
        
        if this.cursorPos[] == this.text[].runeLen:
          this.text[] = this.text[] & e.text
        else:
          this.text{}.insert e.text, this.text[].runeOffset(this.cursorPos[])
          this.text.changed.emit()
        
        this.cursorPos[] = this.cursorPos[] + e.text.runeLen
        signal.WindowEvent.handled = true
        
        if selectingUsingKeyboard in this.allowedInteractions:
          this.selectionStart[] = this.cursorPos[]
          this.selectionEnd[] = this.cursorPos[]


method init*(this: TextArea) =
  procCall this.super.init()

  this.cursorPos = CustomProperty[int](
    get: proc(): int = this.m_cursorPos,
    set: proc(x: int) = this.m_cursorPos = x.max(0).min(this.text[].runeLen),
  )

  this.selectionStart = CustomProperty[int](
    get: proc(): int = this.m_selectionStart,
    set: proc(x: int) = this.m_selectionStart = x.max(0).min(this.text[].runeLen),
  )

  this.selectionEnd = CustomProperty[int](
    get: proc(): int = this.m_selectionEnd,
    set: proc(x: int) = this.m_selectionEnd = x.max(0).min(this.text[].runeLen),
  )

  
  proc positionOfCharacter(arrangement: Arrangement, pos: int): float =
    if arrangement != nil:
      if pos > arrangement.positions.high:
        arrangement.layoutBounds.x
      else:
        arrangement.selectionRects[pos].x
    else: 0
  
  proc characterAtPosition(arrangement: Arrangement, pos: float): int =
    if arrangement != nil:
      while true:
        if result > arrangement.selectionRects.high: break
        if arrangement.selectionRects[result].x + arrangement.selectionRects[result].w / 2 > pos: break
        inc result
  

  this.text.changed.connectTo this:
    this.cursorPos[] = this.cursorPos[]
    this.selectionStart[] = this.selectionStart[]
    this.selectionEnd[] = this.selectionEnd[]
    this.blinking.time[] = DurationZero
  

  this.cursorPos.changed.connectTo this:
    this.blinking.time[] = DurationZero

  
  this.makeLayout:
    this.withWindow win:
      win.onTick.connectTo this:
        this.blinking.time[] = (this.blinking.time + e.deltaTime) mod (this.blinking.period[] * 2)

    - MouseArea.new:
      this.fill parent

      this.onSignal.connectTo this, signal:
        if deactivatingUsingMouse in root.allowedInteractions and root.active[] and not this.hovered[]:
          if signal of WindowEvent and signal.WindowEvent.event of MouseButtonEvent and signal.WindowEvent.handled == false:
            let e = (ref MouseButtonEvent)signal.WindowEvent.event
            if e.pressed: root.active[] = false


      this.clicked.connectTo root, e:
        if selectingWordsByDobleClick in root.allowedInteractions and e.double:
          root.selectionStart[] = root.findLeftCtrlWord(inBorders=true)
          root.selectionEnd[] = root.findRightCtrlWord(inBorders=true)
          root.cursorPos[] = root.selectionEnd[]
          root.doubleClick = true
        
        if selectingAllTextByDobleClick in root.allowedInteractions and e.double:
          root.selectionStart[] = 0
          root.selectionEnd[] = root.text[].runeLen
          root.cursorPos[] = root.selectionEnd[]
          root.doubleClick = true
        
        if getTime() - root.lastDoubleClickTime <= initDuration(milliseconds=300):
          if selectingAllTextByTripleClick in root.allowedInteractions:
            root.selectionStart[] = 0
            root.selectionEnd[] = root.text[].runeLen
            root.cursorPos[] = root.selectionEnd[]

        if e.double:
          root.lastDoubleClickTime = getTime()


      this.pressed.changed.connectTo root:
        if not this.pressed[]:
          root.doubleClick = false
        
        if activatingUsingMouse in root.allowedInteractions and this.pressed[]:
          root.active[] = true
        
        if navigationUsingMouse in root.allowedInteractions and this.pressed[] and (not root.doubleClick):
          root.cursorPos[] = characterAtPosition(root.textObj{}.arrangement[], this.mouseX[] - root.offset[])

          if selectingUsingMouse in root.allowedInteractions:
            if root.parentWindow.keyboard.pressed.containsShift():
              root.selectionEnd[] = root.cursorPos[]
            else:
              root.selectionStart[] = root.cursorPos[]
              root.selectionEnd[] = root.cursorPos[]


      this.mouseX.changed.connectTo root, mouseX:
        if navigationUsingMouse in root.allowedInteractions and this.pressed[]:
          root.cursorPos[] = characterAtPosition(root.textObj{}.arrangement[], this.mouseX[] - root.offset[])

          if selectingUsingMouse in root.allowedInteractions:
            root.selectionEnd[] = root.cursorPos[]


      - ClipRect.new as clip:
        this.fill parent

        - Uiobj.new as offset:
          this.fillVertical parent
          # w := root.textObj[].w[]
          x := root.offset[]
          

          root.selectionObj --- (let r = UiRect(); initIfNeeded(r); r.color[] = "78A7FF"; r.fillVertical root; r.Uiobj):
            x := min(root.selectionStartX[], root.selectionEndX[])
            w := max(root.selectionStartX[], root.selectionEndX[]) - min(root.selectionStartX[], root.selectionEndX[])


          root.textObj --- UiText.new:
            centerY = parent.center
            text = binding:
              if root.text[].len == 0: ""  # workaround https://github.com/nim-lang/Nim/issues/24080
              else: root.text[]
            x = 1


          root.binding selectionStartX: positionOfCharacter(root.textObj{}.arrangement[], root.selectionStart[])
          root.binding selectionEndX: positionOfCharacter(root.textObj{}.arrangement[], root.selectionEnd[])
          

          root.cursorObj --- (let r = UiRect(); initIfNeeded(r); r.fillVertical root; r.w[] = 2; r.Uiobj):
            x := root.cursorX[]

            visibility = binding:
              if root.active[]:
                if root.blinking.enabled[]:
                  if root.blinking.time[] <= root.blinking.period[]:
                    Visibility.visible
                  else:
                    Visibility.hiddenTree
                else: Visibility.visible
              else: Visibility.hiddenTree

            root.binding cursorX: positionOfCharacter(root.textObj{}.arrangement[], root.cursorPos[])
            
            proc followCursor =
              let x = this.x[] + offset.x[]
              if x > clip.w[] - root.followCursorOffset[] - 2:
                root.offset[] = -this.x[] + clip.w[] - root.followCursorOffset[] - 2
              elif x < root.followCursorOffset[]:
                root.offset[] = -this.x[] + root.followCursorOffset[]
            
            this.x.changed.connectTo root: followCursor()
            root.followCursorOffset.changed.connectTo root: followCursor()
    
    this.newChildsObject = clip


when isMainModule:
  const typefaceFile = staticRead "../../tests/Roboto-Regular.ttf"
  let typeface = parseTtf(typefaceFile)

  preview(clearColor = color(1, 1, 1), margin = 20,
    withWindow = proc: Uiobj =
      let this = TextArea()
      this.makeLayout:
        text = "start text"
        this.textObj[].font[] = typeface.withSize(24)
        w = 400
        h = this.textObj[].h[].max(24)

        - UiRectBorder.new:
          this.fill(parent, -1)
      this
  )

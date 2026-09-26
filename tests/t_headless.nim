## Automated UI tests without any visible window or user interaction.
##
## Uses sigui/testutils to:
## - render the gallery (tests/gallery.nim) into an offscreen framebuffer,
## - emulate mouse and keyboard input,
## - inspect the component tree via machine-readable dumps,
## - check rendered pixels.
##
## Run: nim r t_headless.nim

import std/[os, strutils, math, json]
import unittest
import pkg/[chroma, vmath]
import pkg/pixie
import sigui, sigui/testutils
import components, gallery

var win: HeadlessUiWindow
var refs: Gallery

win = newHeadlessUiWindow(size = ivec2(560, 540))
win.makeLayout:
  - Gallery.new as (refs)
win.settleAnimations()


suite "headless rendering":

  test "window renders offscreen into an image":
    # background is white
    check win.pixelColor(5, 5) == color(1, 1, 1)
    # button fill is system blue
    check refs.button != nil
    check win.pixelColor(refs.button.centerOf) == color_blue
    # disabled button is gray
    check win.pixelColor(refs.disabledButton.centerOf) == color_gray4

  test "screenshot can be saved to a file":
    let path = getTempDir() / "sigui_test_gallery.png"
    win.saveScreenshot path
    check fileExists(path)
    let img = readImage(path)
    check img.width == 560
    check img.height == 540

  test "resizing the drawing area works":
    let oldSize = win.size
    win.size = ivec2(300, 200)
    win.render()
    check win.pixelColor(299, 199) != color(0, 0, 0, 0)
    check win.pixelColor(400, 300) == color(0, 0, 0, 0)  # outside of new bounds
    win.size = oldSize
    win.render()
    check win.pixelColor(5, 5) == color(1, 1, 1)


suite "machine readable dumps":

  test "uiRepr dumps the component tree":
    let repr = win.uiRepr
    check repr.contains("UiWindow(globalBox = [0, 0, 560x540]")
    check repr.contains("Button(globalBox = [")
    check repr.contains("Switch(globalBox = [")
    check repr.contains("TableView(globalBox = [")
    check repr.contains("title = Button")
    check repr.contains("isOn = false")

  test "uiJson produces structured data":
    let root = win.uiJson
    check root["type"].getStr == "UiWindow"
    check root["globalBox"][2].getInt == 560
    check root["childs"].len > 0

    let buttonJson = refs.button.uiJson
    check buttonJson["type"].getStr == "Button"
    check buttonJson["title"].getStr == "Button"
    check buttonJson["enabled"].getBool == true
    check buttonJson["globalBox"].len == 4

  test "components can be found by type":
    check win.findComponents(Button).len == 2
    check win.findComponent(Slider) == refs.slider
    check win.findComponent(PluginUiRoot) == nil

  test "componentAt performs hit testing":
    check win.componentAt(refs.button.centerOf).componentTypeName == "MouseArea"
    check win.componentAt(vec2(5, 5)) == refs
    check win.componentAt(vec2(-50, -50)) == nil


suite "mouse input":

  test "clicking a button emits tapped":
    check refs.buttonTaps == 0
    win.clickAt(refs.button)
    check refs.buttonTaps == 1

    # a click on the disabled button does nothing
    win.clickAt(refs.disabledButton)
    check refs.buttonTaps == 1

    # double click counts as two taps
    win.mouseDoubleClick(refs.button.centerOf)
    check refs.buttonTaps == 3

  test "press-move-release outside of the area is not a click":
    refs.buttonTaps = 0
    win.mouseMoveTo(refs.button.centerOf)
    win.mousePress()
    win.mouseMoveBy(vec2(200, 0))
    win.mouseRelease()
    check refs.buttonTaps == 0

  test "clicking a switch toggles it with an animation":
    let sw = refs.switch
    check sw.isOn[] == false
    check refs.switchChanges == 0

    # the left side of the switch is covered by the knob when it is off
    let leftPos = sw.centerOf + vec2(-21, 0)
    check win.pixelColor(leftPos) == color(1, 1, 1)

    # click: state changes instantly, knob moves with an animation
    win.clickAt(sw)
    check sw.isOn[] == true
    check refs.switchChanges == 1

    # the knob is still on the left (the animation has not ticked yet)
    check win.pixelColor(leftPos) == color(1, 1, 1)

    # after settling all animations the knob moved right and the track is green
    win.settleAnimations()
    check win.pixelColor(leftPos) == sw.tintColor[]

    # and clicking again turns it off
    win.clickAt(sw)
    check sw.isOn[] == false
    check refs.switchChanges == 2
    win.settleAnimations()
    check win.pixelColor(leftPos) == color(1, 1, 1)

  test "slider value follows the mouse":
    let slider = refs.slider
    check abs(slider.value[] - 0.3) < 0.001

    # click at 80% of the track
    win.mouseClick(slider.centerOf + vec2(slider.w[] * 0.8 - slider.w[] / 2, 0))
    check abs(slider.value[] - 0.8) < 0.03
    check refs.sliderEdits == 1

    # drag from the left edge to the right edge
    let y = 0'f32
    win.mouseDrag(
      slider.centerOf + vec2(-slider.w[] / 2 + 4, y),
      slider.centerOf + vec2(slider.w[] / 2 - 4, y),
    )
    check abs(slider.value[] - 1.0) < 0.05
    check refs.sliderEdits > 1

  test "segmented control switches selection on click":
    let seg = refs.segmented
    check seg.selectedIndex[] == 0

    # the second segment is located at the center of the control
    win.clickAt(seg)
    check seg.selectedIndex[] == 1

    # the first segment is on the left
    win.clickAt(seg, vec2(-72, 0))
    check seg.selectedIndex[] == 0

  test "stepper increments and decrements with clamping":
    let stepper = refs.stepper
    stepper.minimum[] = -1
    stepper.maximum[] = 2

    win.clickAt(stepper.plusButton)
    check stepper.value[] == 1
    win.clickAt(stepper.plusButton)
    check stepper.value[] == 2
    # clamped at maximum, no extra event
    win.clickAt(stepper.plusButton)
    check stepper.value[] == 2
    check refs.stepperChanges == 2

    win.clickAt(stepper.minusButton)
    win.clickAt(stepper.minusButton)
    win.clickAt(stepper.minusButton)
    check stepper.value[] == -1
    check refs.stepperChanges == 5

  test "page control switches pages on dot clicks":
    let pc = refs.pageControl
    check pc.currentPage[] == 1

    # dots are 10px wide with 8px gaps, starting at the left edge;
    # dot i center is at offset (18*i - 45) from the control center
    win.clickAt(pc, vec2(9, 0))  # fourth dot
    check pc.currentPage[] == 3

  test "check box toggles on click":
    let cb = refs.checkBox
    var toggles = 0
    cb.toggled.connectTo cb:
      inc toggles

    check cb.isChecked[] == true
    win.clickAt(cb)
    check cb.isChecked[] == false
    check toggles == 1
    win.clickAt(cb)
    check cb.isChecked[] == true
    check toggles == 2

  test "table view selects a row on click":
    let table = refs.tableView
    check table.selectedIndex[] == -1

    # the middle of the table is the second row ("beta")
    win.clickAt(table)
    check table.selectedIndex[] == 1

    win.clickAt(table, vec2(0, 44))  # third row
    check table.selectedIndex[] == 2

  test "navigation bar back button":
    check refs.backTaps == 0
    # the back button is at the left side of the bar
    win.clickAt(refs.navBar, vec2(-67, 0))
    check refs.backTaps == 1

  test "tab bar switches tabs on click":
    let bar = refs.tabBar
    check bar.selectedIndex[] == 0

    # the second tab is located at the center of the bar
    win.clickAt(bar)
    check bar.selectedIndex[] == 1

    win.clickAt(bar, vec2(-73, 0))  # first tab
    check bar.selectedIndex[] == 0


suite "keyboard input":

  test "typing into a text field":
    let field = refs.textField
    check field.text == ""

    win.typeInto(field.textArea, "hello")
    check field.text == "hello"
    check field.textArea.active[] == true

    win.keyTap(Key.backspace)
    check field.text == "hell"

    win.keyTap(Key.left)
    win.typeText("x")
    check field.text == "helxl"

    # ctrl+a selects all text, typing replaces it
    win.hotkey(Key.lcontrol, Key.a)
    win.typeText("new")
    check field.text == "new"

  test "text field placeholder is hidden while typing":
    let field = refs.textField
    field.text = ""

    proc findByText(node: JsonNode, text: string): JsonNode =
      if node.kind == JObject:
        if node.hasKey("text") and node["text"].getStr == text:
          return node
        if node.hasKey("childs"):
          for child in node["childs"]:
            let res = child.findByText(text)
            if res != nil: return res

    # when the field is empty the placeholder is visible,
    # "visibility" is omitted in the dump because visible is the default value
    check field.uiJson.findByText("Placeholder").hasKey("visibility") == false

    win.typeInto(field.textArea, "hi")
    check field.text == "hi"
    check field.uiJson.findByText("Placeholder")["visibility"].getStr == "collapsed"

  test "escape deactivates the text field":
    let field = refs.textField
    win.typeInto(field.textArea, "abc")
    check field.textArea.active[] == true
    win.keyTap(Key.escape)
    check field.textArea.active[] == false

  test "global keybindings react to hotkeys":
    var activated = 0

    win.makeLayout:
      - globalKeybinding({Key.lcontrol, Key.k}):
        on this.activated:
          inc activated

    win.hotkey(Key.k)
    check activated == 0

    win.hotkey(Key.lcontrol, Key.k)
    check activated == 1

    win.keyPress(Key.lshift)
    win.hotkey(Key.lcontrol, Key.k)
    # exact binding does not trigger with an extra modifier held
    check activated == 1
    win.keyRelease(Key.lshift)


suite "frame loop and animations":

  test "activity indicator rotates over ticks":
    let spinner = refs.spinner
    let topSpoke = spinner.centerOf + vec2(0, -12)

    win.settleAnimations()  # resets spinner time to a multiple of the rotation
    let beforeTop = win.pixelColor(topSpoke)

    # after 100ms (36 degrees) a different set of spokes fills the top spot
    win.tick(initDuration(milliseconds = 100))
    win.render()
    let afterTop = win.pixelColor(topSpoke)
    check beforeTop != afterTop

  test "tickUntil waits for a condition":
    refs.button.enabled[] = false
    # condition never becomes true, timeout is returned
    check not win.tickUntil(proc(): bool = refs.button.enabled[], timeout = 1's)

    var counter = 0
    check win.tickUntil(proc(): bool = (inc counter; counter > 5))
    check counter == 6

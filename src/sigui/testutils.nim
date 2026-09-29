## Utilities for testing sigui applications without a visible window and without user interaction.
##
## Designed to be used by automated tests and AI agents:
##
## - `newHeadlessUiWindow` creates a UiWindow that renders into an offscreen framebuffer,
##   so no window is shown on screen
## - `screenshot`/`saveScreenshot` render the window content into an image
## - mouse and keyboard input can be emulated programmatically (`mouseClick`, `mouseDrag`,
##   `typeText`, `hotkey`, etc.)
## - `uiRepr`/`uiJson` dumps a component tree in a compact machine-readable form
##
## ```nim
## import unittest, sigui, sigui/testutils
##
## let win = newHeadlessUiWindow(size = ivec2(200, 100))
## win.makeLayout:
##   this.clearColor = "#202020".color
##   - UiRect.new as rect:
##     w = 50; h = 50
##     color = "#ff0000".color
##
##     - MouseArea.new as mouse:
##       this.fill parent
##       on this.clicked: rect.color[] = "#00ff00".color
##
## win.saveScreenshot "rect.png"
## win.clickAt(vec2(25, 25))
## check rect.color[] == "#00ff00".color
## ```
##
## note: headless rendering uses an invisible X11 window to obtain an OpenGL context,
## so on Linux it requires X11 (or XWayland) to be available

import pkg/pixie/images
import ./testutils/[inputEmulation, headlessWindow, jsonDump]
export images, inputEmulation, headlessWindow, jsonDump


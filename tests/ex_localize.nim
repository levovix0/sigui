import unittest, json
import sigui, siwin, localize

test "localize":
  var locale = globalLocale.property
  locale[] = locale(
    "ru", "",
    parseLocaleTable %*{
      "sigui": {
        "tests/ot_localize.nim": {
          "Hello, world!": {
            "": "Привет, мир!"
          },
        },
      }
    }
  )

  let win = newSiwinGlobals().newOpenglWindow(size=ivec2(1280, 720), title="Hello sigui").newUiWindow

  win.clearColor = "202020"

  const typefaceFile = staticRead "Roboto-Regular.ttf"
  let typeface = parseTtf(typefaceFile)

  win.makeLayout:
    - UiText.new:
      this.centerIn(parent)
      font = typeface.withSize(32)
      color = "fff"
      text := tr("Hello, world!", "", locale[])

  run win.siwinWindow

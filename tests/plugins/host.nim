import sigui

proc glLoad(name: cstring): pointer {.cdecl.} =
  glGetProc(name)

proc plugin_init(glLoad: pointer) {.dynlib: "libplugin.so", cdecl, importc: "init".}
proc plugin_getUi(): ptr UiPlugin {.dynlib: "libplugin.so", cdecl, importc: "getUi".}


let win = newUiWindow(size=ivec2(1280, 720), title="sigui host")

plugin_init(glLoad)

win.makeLayout:
  this.clearColor = "#202020".color

  - HostUiRoot.new:
    this.setPlugin plugin_getUi()
    this.centerIn parent

run win

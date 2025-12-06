import sigui
import opengl/private/prelude {.all.}


let panel = newPluginUiRoot()

panel.makeLayout:
  w = 200
  h = 80

  - UiRect.new:
    this.fill parent
    color = "#ff4040".color



proc init(glLoad: pointer) {.dynlib, cdecl, exportc.} =
  glxGetProcAddress = cast[typeof(glxGetProcAddress)](glLoad)
  prelude.loadExtensions()

proc getUi(): ptr UiPlugin {.dynlib, cdecl, exportc.} =
  panel.plugin.addr

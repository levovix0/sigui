import std/strutils


const componentFileTemplate = """
import sigui/[uibase]

type
  <|name|>* = ref object of Uiobj

registerComponent <|name|>


method init*(this: <|name|>) =
  procCall this.super.init()

  this.makeLayout:
    ##


when isMainModule:
  preview(
    clearColor = color(1, 1, 1), margin = 20,
    withWindow = proc: Uiobj = (var r = <|name|>.new; init r; r)
  )
"""


macro doRefactor_siguiComponentFile*(
  name: untyped,
  instInfo: static tuple[filename: string, line: int, column: int]
) =
  writeFile instInfo.filename, componentFileTemplate.replace("<|name|>", name.repr)
  quit 0


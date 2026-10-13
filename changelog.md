### 0.2.3

- add: `sigui/inspector` — an "inspect element"-like tool: component tree, properties of the selected component, pick mode and highlight of the selected component. Can be opened in a separate window via `openInspector` or added into any window as a regular component `Inspector.new`.
- fix: uiobj anchors are now handled by regular closures instead of {.nimcall.} + pointer env closures, which crashed the ORC cycle collector when a ui tree was destroyed
- add: `- Component(w = 100, h := this.w[], centerIn parent)` syntax for makeLayout (as an alias for `- Component.new: this.w[] = 100, this.h[] = binding: this.w[], this.centerIn(parent)`). This syntax only applies if first arg is not exprColonExpr. Use braces or the new `> func(args)` syntax if you need to explicitly call a function.

### 0.2.2
changelog created at 2025/04/23, [0a8b0b7d](https://github.com/levovix0/sigui/commit/0a8b0b7d)

[215d664a](https://github.com/levovix0/sigui/commit/215d664a):
- fix/change: WindowEvent signals are now revieved in backward order of childs
- add: `on prop[] == value: body` sugar
- add: allow "202020".color instead of "202020".litToColor.static

[28e3c761](https://github.com/levovix0/sigui/commit/28e3c761):
- add: UiPath

[a70c1377](https://github.com/levovix0/sigui/commit/a70c1377):
- add: BeforeDraw signal

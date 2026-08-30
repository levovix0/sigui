# should be used instead of directly importing siwin
# todo: add windy support

import pkg/siwin/platforms/any/[window, clipboards]

export MouseButton, Key, ModifierKey, Touch, Cursor, CursorKind, BuiltinCursor, ImageCursor
export Window, Mouse, Keyboard, TouchScreen
export
  AnyWindowEvent, CloseEvent, RenderEvent, TickEvent, ResizeEvent, WindowMoveEvent,
  MouseMoveEvent, MouseMoveKind, MouseButtonEvent, ScrollEvent, ClickEvent,
  KeyEvent, TextInputEvent,
  TouchEvent, TouchMoveEvent,
  StateBoolChangedEventKind, StateBoolChangedEvent, DropEvent

export clipboards

export `size=`, size, clipboard


converter toRefCursor*(x: BuiltinCursor): ref Cursor =
  (ref Cursor)(kind: builtin, builtin: x)



# should be used instead of directly importing siwin
# todo: add windy support

import pkg/siwin/platforms/any/window

export MouseButton, Key, Touch, Cursor, CursorKind, BuiltinCursor, ImageCursor
export Window, Mouse, Keyboard, TouchScreen
export
  AnyWindowEvent, CloseEvent, RenderEvent, TickEvent, ResizeEvent, WindowMoveEvent,
  MouseMoveEvent, MouseButtonEvent, ScrollEvent, ClickEvent,
  KeyEvent, TextInputEvent,
  TouchEvent, TouchMoveEvent,
  StateBoolChangedEventKind, StateBoolChangedEvent, DropEvent

export `size=`, size



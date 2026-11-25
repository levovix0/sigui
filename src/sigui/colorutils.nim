import pkg/chroma
import std/[strutils, macros]


proc toColor*(s: string): Color =
  var i = 0
  if s[0] == '#':
    inc i

  case s.len - i
  of 3:
    result = Color(
      r: ($s[i+0]).parseHexInt.float32 / 15.0,
      g: ($s[i+1]).parseHexInt.float32 / 15.0,
      b: ($s[i+2]).parseHexInt.float32 / 15.0,
      a: 1,
    )
  of 4:
    result = Color(
      r: ($s[i+0]).parseHexInt.float32 / 15.0,
      g: ($s[i+1]).parseHexInt.float32 / 15.0,
      b: ($s[i+2]).parseHexInt.float32 / 15.0,
      a: ($s[i+3]).parseHexInt.float32 / 15.0,
    )
  of 6:
    result = Color(
      r: (s[i+0 .. i+1].parseHexInt.float32) / 255.0,
      g: (s[i+2 .. i+3].parseHexInt.float32) / 255.0,
      b: (s[i+4 .. i+5].parseHexInt.float32) / 255.0,
      a: 1,
    )
  of 8:
    result = Color(
      r: (s[i+0 .. i+1].parseHexInt.float32) / 255.0,
      g: (s[i+2 .. i+3].parseHexInt.float32) / 255.0,
      b: (s[i+4 .. i+5].parseHexInt.float32) / 255.0,
      a: (s[i+6 .. i+7].parseHexInt.float32) / 255.0,
    )
  else:
    raise ValueError.newException("invalid color: " & s)


converter litToColor*(s: string{lit}): Color =
  s.toColor


macro color*(s: static string): Color =
  s.toColor.newLit

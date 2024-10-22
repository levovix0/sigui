import std/[unicode, tables, math]
import pkg/[chroma]
import pkg/pixie/[fonts, images, paints]
import ./[gl]

type
  GlyphFamily* = object
    typefaceId*: int
    size*: float32
    underline*: bool
    strikethrough*: bool
    noKerningAdjustments*: bool

  GlyphPlacement* = object
    texture*: GlUint
    x*, y*: int16
  
  GlyphFamilyBuffer* = object
    placements: Table[Rune, GlyphPlacement]
    textures: seq[GlUint]
    freeX, freeY, freeH: int16

  GlyphBuffer* = object
    families*: Table[GlyphFamily, GlyphFamilyBuffer]


const sigui_glyphBuffer_textureSize* {.intdefine.} = 1024

const ts = sigui_glyphBuffer_textureSize


proc render(familyBuffer: var GlyphFamilyBuffer, placement: var GlyphPlacement, rune: Rune, font: Font, size: Vec2) =
  let w = size.x.ceil.int16
  let h = size.y.ceil.int16

  if familyBuffer.freeY + h > ts or familyBuffer.textures.len == 0:
    # we need new texture
    var textureId: GlUint
    glGenTextures(1, textureId.addr)
    familyBuffer.textures.add textureId

    glBindTexture(GlTexture2d, textureId)

    let buffer = alloc0(ts * ts * 4)

    glTexImage2D(GlTexture2d, 0, GlRgba.GLint, ts.GLsizei, ts.GLsizei, 0, GlRgba, GlUnsignedByte, buffer)
    glGenerateMipmap(GlTexture2d)

    glBindTexture(GlTexture2d, 0)

    dealloc buffer

    familyBuffer.freeX = 0
    familyBuffer.freeY = 0
    familyBuffer.freeH = h
  
  elif familyBuffer.freeX + w > ts:
    # we need new line
    familyBuffer.freeX = 0
    familyBuffer.freeY = familyBuffer.freeY + familyBuffer.freeH
    familyBuffer.freeH = h
  
  placement.texture = familyBuffer.textures[^1]
  placement.x = familyBuffer.freeX
  placement.y = familyBuffer.freeY
  
  familyBuffer.freeX = familyBuffer.freeX + w
  if h > familyBuffer.freeH:
    familyBuffer.freeH = h
  
  if w == 0 or h == 0: return

  let image = newImage(w.int, h.int)
  image.fill(color(0, 0, 0, 0))

  let paint = font.paint
  font.paint = newPaint(SolidPaint)
  font.paint.color = color(1, 1, 1, 1)
  
  image.fillText(font.typeset($rune))

  font.paint = paint

  glBindTexture(GlTexture2d, placement.texture)
  glTexSubImage2D(GlTexture2d, 0, placement.x, placement.y, w, h, GlRgba, GlUnsignedByte, image.data[0].addr)


proc renderIfNeeded*(familyBuffer: var GlyphFamilyBuffer, rune: Rune, font: Font, size: Vec2): GlyphPlacement =
  let placement = familyBuffer.placements.mgetOrPut(rune, GlyphPlacement()).addr

  if placement[].texture == 0:
    render(familyBuffer, placement[], rune, font, size)

  result = placement[]


proc glyphFamily*(font: Font): GlyphFamily =
  GlyphFamily(
    typefaceId: cast[int](font.typeface),
    size: font.size,
    underline: font.underline,
    strikethrough: font.strikethrough,
    noKerningAdjustments: font.noKerningAdjustments
  )

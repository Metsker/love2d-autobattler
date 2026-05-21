local UI = {}

-- Virtual frame size. Every scene lays out against this; main.lua renders
-- the scene to a 1920×1080 canvas and scales it into the actual window.
UI.VIRT_W = 1920
UI.VIRT_H = 1080

function UI.dims()
  return UI.VIRT_W, UI.VIRT_H
end

-- Single shared emoji font loaded at a high base size. Drawing at a smaller
-- target size scales the print call instead of loading a new font, which is
-- both faster and avoids repeated reads from the .love archive — the latter
-- can fail in love.js even when the file is present. Size 109 matches the
-- value that the sibling FarmBots project ships in production.
local EMOJI_BASE_SIZE = 109
local emojiFont

local function getEmojiFont()
  if not emojiFont then
    emojiFont = love.graphics.newFont(
      "assets/fonts/NotoEmoji-Regular.ttf", EMOJI_BASE_SIZE)
  end
  return emojiFont
end

-- Called from love.load so the font is loaded eagerly, while the .love archive
-- is freshly mounted. In love.js the synchronous read is most reliable here.
function UI.preloadEmoji()
  getEmojiFont()
end

function UI.drawEmoji(glyph, cx, cy, size, color)
  local font = getEmojiFont()
  local scale = size / EMOJI_BASE_SIZE
  local prev = love.graphics.getFont()
  love.graphics.setFont(font)
  local w = font:getWidth(glyph) * scale
  local h = font:getHeight() * scale
  if color then love.graphics.setColor(color) end
  love.graphics.print(glyph, cx - w / 2, cy - h / 2, 0, scale, scale)
  if color then love.graphics.setColor(1, 1, 1, 1) end
  if prev then love.graphics.setFont(prev) end
end

function UI.drawEmojiAt(glyph, x, y, size, color)
  local font = getEmojiFont()
  local scale = size / EMOJI_BASE_SIZE
  local prev = love.graphics.getFont()
  love.graphics.setFont(font)
  if color then love.graphics.setColor(color) end
  love.graphics.print(glyph, x, y, 0, scale, scale)
  if color then love.graphics.setColor(1, 1, 1, 1) end
  if prev then love.graphics.setFont(prev) end
end

return UI

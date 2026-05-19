local UI = {}

function UI.dims()
  return love.graphics.getWidth(), love.graphics.getHeight()
end

local emojiCache = {}

local function emojiFont(size)
  emojiCache[size] = emojiCache[size]
              or love.graphics.newFont("assets/fonts/NotoEmoji-Regular.ttf", size)
  return emojiCache[size]
end

function UI.drawEmoji(glyph, cx, cy, size, color)
  local font = emojiFont(size)
  local prev = love.graphics.getFont()
  love.graphics.setFont(font)
  local w = font:getWidth(glyph)
  local h = font:getHeight()
  if color then love.graphics.setColor(color) end
  love.graphics.print(glyph, cx - w / 2, cy - h / 2)
  if color then love.graphics.setColor(1, 1, 1, 1) end
  if prev then love.graphics.setFont(prev) end
end

function UI.drawEmojiAt(glyph, x, y, size, color)
  local font = emojiFont(size)
  local prev = love.graphics.getFont()
  love.graphics.setFont(font)
  if color then love.graphics.setColor(color) end
  love.graphics.print(glyph, x, y)
  if color then love.graphics.setColor(1, 1, 1, 1) end
  if prev then love.graphics.setFont(prev) end
end

return UI

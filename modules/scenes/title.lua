local UI = require("ui")

local Title = {}

function Title.draw()
  local W, H = UI.dims()
  love.graphics.clear(0.08, 0.08, 0.10, 1)

  UI.drawEmoji("\u{2694}", W / 2, H * 0.28, 120, {0.95, 0.8, 0.2, 1})

  local titleFont = resource:getFont("ui_xl")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setFont(titleFont)
  love.graphics.printf("AUTOBATTLER", 0, H * 0.46, W, "center")

  love.graphics.setFont(resource:getFont("ui_lg"))
  love.graphics.setColor(0.75, 0.75, 0.75, 1)
  love.graphics.printf("press SPACE to start", 0, H * 0.66, W, "center")
end

function Title.keypressed(k)
  if k == "space" or k == "return" then
    local Game = require("game")
    Game.switch("classpick")
  end
end

return Title
